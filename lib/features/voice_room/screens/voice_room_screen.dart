import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../services/voice_room_service.dart';

// ═══════════════════════════════════════════════════════════════
// 🎙️ VoiceRoomScreen — 디스코드 스타일 보이스 룸
//
// 위치: lib/features/voice_room/screens/voice_room_screen.dart
//
// 사용법:
// - 기존 룸 입장: VoiceRoomScreen(voiceRoomId: '...')
// - 새 룸 생성:   VoiceRoomScreen(voiceRoomId: null, groupRoomId: '...')
// ═══════════════════════════════════════════════════════════════

class VoiceRoomScreen extends ConsumerStatefulWidget {
  /// 입장할 룸 ID. null 이면 groupRoomId 를 사용해 새로 생성
  final String? voiceRoomId;

  /// 새 룸 생성 시 그룹 ID (voiceRoomId 가 null 일 때만 필요)
  final String? groupRoomId;

  final String? title;

  const VoiceRoomScreen({
    super.key,
    required this.voiceRoomId,
    this.groupRoomId,
    this.title,
  }) : assert(voiceRoomId != null || groupRoomId != null,
            'voiceRoomId 또는 groupRoomId 중 하나는 반드시 있어야 함');

  @override
  ConsumerState<VoiceRoomScreen> createState() =>
      _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends ConsumerState<VoiceRoomScreen> {
  bool _joining = true;
  String? _joinError;
  String? _resolvedVoiceRoomId;

  @override
  void initState() {
    super.initState();
    // 화면 첫 프레임 직후 비동기 진행 (Navigator 전환 애니메이션과 병렬)
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      String voiceRoomId;
      String? groupRoomIdForPush;

      if (widget.voiceRoomId != null) {
        // 기존 룸 입장
        voiceRoomId = widget.voiceRoomId!;
      } else {
        // 새 룸 생성
        final groupId = widget.groupRoomId!;
        voiceRoomId = await VoiceRoomService.instance.startRoom(
          groupRoomId: groupId,
          title: widget.title,
        );
        groupRoomIdForPush = groupId; // 푸시 알림 발송용
      }

      _resolvedVoiceRoomId = voiceRoomId;

      await VoiceRoomService.instance.joinRoom(
        voiceRoomId,
        groupRoomIdForPush: groupRoomIdForPush,
      );

      if (mounted) setState(() => _joining = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _joinError = e.toString();
        });
      }
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('보이스 룸 나가기',
            style: TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          '보이스 룸에서 나갈까요?',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '나가기',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await VoiceRoomService.instance.leaveRoom();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmEndAsHost() async {
    final voiceRoomId = _resolvedVoiceRoomId;
    if (voiceRoomId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('룸 종료',
            style: TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          '모든 참가자를 내보내고 보이스 룸을 종료할까요?',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '종료',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await VoiceRoomService.instance.endRoomAsHost(voiceRoomId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('종료 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(voiceRoomStateProvider);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_joining) {
          // 입장 중인 경우 그냥 취소하고 나가기
          await VoiceRoomService.instance.leaveRoom();
          if (mounted) Navigator.pop(context);
        } else {
          await _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1419),
        body: _joining
            ? _buildLoading()
            : _joinError != null
                ? _buildError()
                : stateAsync.when(
                    loading: () => _buildLoading(),
                    error: (e, _) => Center(
                      child: Text('오류: $e',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    data: (state) => _buildRoom(context, state),
                  ),
      ),
    );
  }

  /// 로딩 화면 — 입장 중 표시. 헤더(나가기 X)는 미리 그려놓아서
  /// 사용자 입장에서 화면이 즉시 떠 보이게.
  Widget _buildLoading() {
    return SafeArea(
      child: Column(
        children: [
          // 헤더는 미리 표시
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () async {
                    await VoiceRoomService.instance.leaveRoom();
                    if (mounted) Navigator.pop(context);
                  },
                ),
                Expanded(
                  child: Text(
                    widget.title ?? '보이스 룸',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white70),
                  SizedBox(height: 16),
                  Text(
                    '보이스 룸 연결 중...',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              '보이스 룸 입장 실패',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _joinError ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('돌아가기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoom(BuildContext context, VoiceRoomState state) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(state),
          Expanded(
            child: _buildParticipantsGrid(state),
          ),
          _buildControlBar(state),
        ],
      ),
    );
  }

  Widget _buildHeader(VoiceRoomState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.expand_more, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: '최소화',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? '보이스 룸',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${state.participants.length}명 참여 중',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () => _showMenu(state),
            tooltip: '메뉴',
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsGrid(VoiceRoomState state) {
    final participants = state.participants;
    if (participants.isEmpty) {
      return const Center(
        child: Text(
          '참가자가 없어요',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final count = participants.length;
    final crossAxisCount = count <= 4
        ? 2
        : count <= 9
            ? 3
            : 4;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: count,
      itemBuilder: (_, i) {
        final p = participants[i];
        final isSpeaking = state.speakingUids.contains(p.agoraUid);
        final isMe = p.agoraUid == state.myAgoraUid;

        if (p.isCameraOn) {
          return _VideoTile(
            participant: p,
            state: state,
            isMe: isMe,
            isSpeaking: isSpeaking,
          );
        }
        return _AvatarTile(
          participant: p,
          isSpeaking: isSpeaking,
        );
      },
    );
  }

  Widget _buildControlBar(VoiceRoomState state) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlButton(
            icon: state.micEnabled
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            label: state.micEnabled ? '마이크' : '음소거',
            color: state.micEnabled ? AppTheme.primary : Colors.white24,
            onTap: () async {
              try {
                await VoiceRoomService.instance.toggleMic();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('마이크 토글 실패: $e')),
                  );
                }
              }
            },
          ),
          _CtrlButton(
            icon: state.cameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: '카메라',
            color:
                state.cameraEnabled ? AppTheme.primary : Colors.white24,
            onTap: () async {
              try {
                await VoiceRoomService.instance.toggleCamera();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('카메라 토글 실패: $e')),
                  );
                }
              }
            },
          ),
          if (state.cameraEnabled)
            _CtrlButton(
              icon: Icons.cameraswitch_rounded,
              label: '전환',
              color: Colors.white24,
              onTap: () {
                VoiceRoomService.instance.switchCamera();
              },
            ),
          _CtrlButton(
            icon: Icons.call_end_rounded,
            label: '나가기',
            color: const Color(0xFFEF4444),
            onTap: _confirmLeave,
          ),
        ],
      ),
    );
  }

  void _showMenu(VoiceRoomState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.stop_circle_rounded,
                  color: Color(0xFFEF4444)),
              title: const Text(
                '룸 종료 (방장)',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                '모든 참가자가 나가집니다',
                style: TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmEndAsHost();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 아바타 타일 (카메라 OFF)
// ═══════════════════════════════════════════════════════════════
class _AvatarTile extends StatelessWidget {
  final VoiceRoomParticipant participant;
  final bool isSpeaking;

  const _AvatarTile({
    required this.participant,
    required this.isSpeaking,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = participant.nickname ?? '...';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeaking
              ? const Color(0xFF22C55E)
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            children: [
              AvatarWidget(
                url: participant.avatarUrl,
                name: nickname,
                size: 60,
              ),
              if (participant.isMuted)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1A1F2E), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.mic_off,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nickname,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 비디오 타일 (카메라 ON)
// ═══════════════════════════════════════════════════════════════
class _VideoTile extends StatelessWidget {
  final VoiceRoomParticipant participant;
  final VoiceRoomState state;
  final bool isMe;
  final bool isSpeaking;

  const _VideoTile({
    required this.participant,
    required this.state,
    required this.isMe,
    required this.isSpeaking,
  });

  @override
  Widget build(BuildContext context) {
    final engine = VoiceRoomService.instance.engine;
    final nickname = participant.nickname ?? '...';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeaking
              ? const Color(0xFF22C55E)
              : Colors.white12,
          width: 2,
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (engine != null && state.channel != null)
              isMe
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: engine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: engine,
                        canvas: VideoCanvas(uid: participant.agoraUid),
                        connection: RtcConnection(
                          channelId: state.channel,
                        ),
                      ),
                    ),
            if (participant.isMuted)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.mic_off,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  nickname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CtrlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}