// ════════════════════════════════════════════════════════════════
// 📞 ActiveCallScreen
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/call_model.dart';
import '../providers/call_provider.dart';
import '../services/call_service.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  final String callId;
  final bool isVideo;
  final bool isInitiator;

  const ActiveCallScreen({
    super.key,
    required this.callId,
    required this.isVideo,
    required this.isInitiator,
  });

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  final _service = CallService.instance;

  bool _joining = true;
  String? _joinError;

  final Map<int, bool> _remoteUsers = {};
  int? _firstRemoteUid;

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = false;
  int _durationSec = 0;

  StreamSubscription<RemoteUserEvent>? _remoteSub;
  StreamSubscription<int>? _durationSub;

  String? _otherNickname;
  String? _otherAvatar;
  String? _groupRoomName;

  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    // ⭐ immersive 모드 제거 — 화면 잘림 원인이었음
    _loadCallContext();
    _setupListeners();
    _joinCall();

    if (widget.isVideo) _scheduleHideControls();
  }

  void _setupListeners() {
    _remoteSub = _service.remoteUserStream.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.type) {
          case RemoteUserEventType.joined:
            _remoteUsers[event.agoraUid] = widget.isVideo;
            _firstRemoteUid ??= event.agoraUid;
            break;
          case RemoteUserEventType.left:
            _remoteUsers.remove(event.agoraUid);
            if (_firstRemoteUid == event.agoraUid) {
              _firstRemoteUid = _remoteUsers.keys.isNotEmpty
                  ? _remoteUsers.keys.first
                  : null;
            }
            break;
          case RemoteUserEventType.videoEnabled:
            _remoteUsers[event.agoraUid] = event.videoEnabled ?? true;
            break;
          case RemoteUserEventType.videoMuted:
            _remoteUsers[event.agoraUid] = !(event.muted ?? false);
            break;
          case RemoteUserEventType.audioMuted:
            break;
        }
      });
    });

    _durationSub = _service.durationStream.listen((sec) {
      if (!mounted) return;
      setState(() => _durationSec = sec);
    });
  }

  Future<void> _joinCall() async {
    try {
      if (widget.isInitiator) {
        await _service.joinChannel(
          callId: widget.callId,
          isVideo: widget.isVideo,
        );
      } else {
        await _service.acceptCall(
          callId: widget.callId,
          isVideo: widget.isVideo,
        );
      }
      if (!mounted) return;
      setState(() {
        _joining = false;
        _micMuted = _service.micMuted;
        _cameraOff = _service.cameraOff;
        _speakerOn = _service.speakerOn;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinError = e.toString();
      });
    }
  }

  Future<void> _loadCallContext() async {
    final sb = Supabase.instance.client;
    try {
      final call = await sb
          .from('kyorangtalk_calls')
          .select('*')
          .eq('id', widget.callId)
          .maybeSingle();
      if (call == null) return;

      final myId = sb.auth.currentUser?.id;
      final roomType = call['room_type'] as String?;

      if (roomType == 'dm') {
        final initiatorId = call['initiator_id'] as String;
        final sourceRoomId = call['source_room_id'] as String;

        final room = await sb
            .from('kyorangtalk_rooms')
            .select('user1_id, user2_id')
            .eq('id', sourceRoomId)
            .maybeSingle();

        String? otherId;
        if (room != null) {
          final u1 = room['user1_id'] as String;
          final u2 = room['user2_id'] as String;
          otherId = u1 == myId ? u2 : u1;
        } else {
          otherId = initiatorId == myId ? null : initiatorId;
        }

        if (otherId != null) {
          final prof = await sb
              .from('kyorangtalk_profiles')
              .select('nickname, avatar_url')
              .eq('id', otherId)
              .maybeSingle();
          if (!mounted) return;
          setState(() {
            _otherNickname = prof?['nickname'] as String?;
            _otherAvatar = prof?['avatar_url'] as String?;
          });
        }
      } else {
        final room = await sb
            .from('kyorangtalk_group_rooms')
            .select('name')
            .eq('id', call['source_room_id'])
            .maybeSingle();
        if (!mounted) return;
        setState(() {
          _groupRoomName = room?['name'] as String?;
        });
      }
    } catch (e) {
      print('🔴 _loadCallContext 오류: $e');
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.isVideo) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _remoteSub?.cancel();
    _durationSub?.cancel();
    // ⭐ immersive 모드 해제도 제거 (애초에 적용 안 함)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallModel?>>(
      activeCallProvider(widget.callId),
      (prev, next) {
        next.whenData((call) {
          if (!mounted) return;
          if (call == null) {
            _exitScreen();
            return;
          }
          if (call.status.isFinished) {
            _exitScreen();
          }
        });
      },
    );

    if (_joining) {
      return _buildJoiningScreen();
    }
    if (_joinError != null) {
      return _buildErrorScreen();
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        // ⭐ extendBodyBehindAppBar: false (기본값) → 화면 영역이 정상 계산됨
        body: GestureDetector(
          onTap: widget.isVideo ? _showControls : null,
          child: SizedBox(
            // ⭐ 명시적 fullscreen — 화면 잘림 방지
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: widget.isVideo
                      ? _buildVideoView()
                      : _buildVoiceView(),
                ),
                if (!widget.isVideo || _controlsVisible) _buildTopBar(),
                if (!widget.isVideo || _controlsVisible)
                  _buildBottomControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 영상 뷰 ──────────────────────────────────────
  Widget _buildVideoView() {
    final engine = _getEngine();

    final remoteUid = _firstRemoteUid;
    final remoteVideoEnabled =
        remoteUid != null && (_remoteUsers[remoteUid] ?? false);

    return Stack(
      children: [
        if (remoteUid != null && remoteVideoEnabled && engine != null)
          Positioned.fill(
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: engine,
                canvas: VideoCanvas(uid: remoteUid),
                connection: RtcConnection(channelId: widget.callId),
              ),
            ),
          )
        else
          Positioned.fill(child: _buildWaitingForRemoteVideo()),

        if (!_cameraOff && engine != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            right: 16,
            child: GestureDetector(
              onTap: () => _service.switchCamera(),
              child: Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: engine,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaitingForRemoteVideo() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(
              url: _otherAvatar,
              name: _otherNickname ?? _groupRoomName,
              size: 100,
            ),
            const SizedBox(height: 24),
            Text(
              _firstRemoteUid == null
                  ? (widget.isInitiator ? '연결 중...' : '통화 연결 중...')
                  : '상대방이 카메라를 껐어요',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 음성 뷰 ──────────────────────────────────────
  Widget _buildVoiceView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withOpacity(0.8),
            AppTheme.bg,
          ],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final reservedTop = 70.0;
            final reservedBottom = 160.0;
            final availableHeight =
                constraints.maxHeight - reservedTop - reservedBottom;
            final avatarSize =
                (availableHeight * 0.4).clamp(80.0, 140.0);

            return Padding(
              padding: EdgeInsets.only(top: reservedTop),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AvatarWidget(
                    url: _otherAvatar,
                    name: _otherNickname ?? _groupRoomName,
                    size: avatarSize,
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _otherNickname ?? _groupRoomName ?? '...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _statusText(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _statusText() {
    if (_firstRemoteUid == null) return '호출 중...';
    return _formatDuration(_durationSec);
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── 상단 바 ──────────────────────────────────────
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isVideo
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  )
                : null,
          ),
          child: Row(
            children: [
              if (widget.isVideo) ...[
                Flexible(
                  child: Text(
                    _otherNickname ?? _groupRoomName ?? '통화',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _firstRemoteUid == null
                      ? '연결 중...'
                      : _formatDuration(_durationSec),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 하단 컨트롤 ──────────────────────────────────
  Widget _buildBottomControls() {
    final buttons = <Widget>[
      _ControlButton(
        icon: _micMuted ? Icons.mic_off : Icons.mic,
        isActive: _micMuted,
        label: _micMuted ? '음소거 해제' : '음소거',
        onTap: () async {
          await _service.toggleMic();
          setState(() => _micMuted = _service.micMuted);
        },
      ),
      if (widget.isVideo)
        _ControlButton(
          icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
          isActive: _cameraOff,
          label: _cameraOff ? '켜기' : '끄기',
          onTap: () async {
            await _service.toggleCamera();
            setState(() => _cameraOff = _service.cameraOff);
          },
        ),
      if (widget.isVideo)
        _ControlButton(
          icon: Icons.cameraswitch,
          isActive: false,
          label: '전환',
          onTap: () => _service.switchCamera(),
        ),
      if (!widget.isVideo)
        _ControlButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
          isActive: _speakerOn,
          label: _speakerOn ? '스피커' : '수화기',
          onTap: () async {
            await _service.toggleSpeaker();
            setState(() => _speakerOn = _service.speakerOn);
          },
        ),
      _ControlButton(
        icon: Icons.call_end,
        isActive: false,
        label: '끊기',
        color: const Color(0xFFEF4444),
        onTap: _endCall,
      ),
    ];

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 20),
          decoration: BoxDecoration(
            gradient: widget.isVideo
                ? LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: buttons
                .map((btn) => Expanded(
                      child: Center(child: btn),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _endCall() async {
    try {
      await _service.endCall();
    } catch (e) {
      print('🔴 endCall 오류: $e');
    }
    if (mounted) _exitScreen();
  }

  void _exitScreen() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _buildJoiningScreen() {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              '통화 연결 중...',
              style: TextStyle(color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFEF4444), size: 56),
              const SizedBox(height: 16),
              Text(
                '통화 연결 실패',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _joinError ?? '알 수 없는 오류',
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _exitScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  RtcEngine? _getEngine() => _service.engine;
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.isActive,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ??
        (isActive
            ? Colors.white.withOpacity(0.9)
            : Colors.white.withOpacity(0.15));
    final iconColor = color != null
        ? Colors.white
        : (isActive ? Colors.black87 : Colors.white);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bgColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}