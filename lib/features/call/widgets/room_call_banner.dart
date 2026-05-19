// ════════════════════════════════════════════════════════════════
// 📞 RoomCallBanner — 채팅방 내부 통화 배너
//
// 위치: lib/features/call/widgets/room_call_banner.dart
//
// 동작:
//   - 이 방에 진행 중 통화(ringing/active)가 있으면 표시
//   - 내 참가 상태에 따라 액션 분기:
//       * accepted (이미 통화 중): "복귀하기" → ActiveCallScreen
//       * invited  (DM에서 받기 전): "받기"   → acceptCall + ActiveCallScreen
//       * null / left / declined / missed
//             - 그룹: "참여하기" → joinActiveGroupCall + ActiveCallScreen
//             - DM:   배너 숨김 (받기는 풀스크린 IncomingCallScreen이 담당)
//
// 사용:
//   RoomCallBanner(roomId: room.roomId, isGroup: false)   // DM
//   RoomCallBanner(roomId: room.id,     isGroup: true)    // 그룹
//
// 위치는 보통 AppBar 바로 아래 (pinnedMessage 배너 위/아래 어디든).
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../models/call_model.dart';
import '../providers/ongoing_call_provider.dart';
import '../screens/active_call_screen.dart';
import '../services/call_service.dart';

class RoomCallBanner extends ConsumerStatefulWidget {
  final String roomId;
  final bool isGroup;

  const RoomCallBanner({
    super.key,
    required this.roomId,
    required this.isGroup,
  });

  @override
  ConsumerState<RoomCallBanner> createState() => _RoomCallBannerState();
}

class _RoomCallBannerState extends ConsumerState<RoomCallBanner> {
  bool _processing = false;

  Future<void> _joinOrReturn({
    required CallModel call,
    required CallParticipantStatus? myStatus,
  }) async {
    if (_processing) return;
    setState(() => _processing = true);

    final service = CallService.instance;
    final isVideo = call.callType.isVideo;

    try {
      // ─── 이미 통화 중 (복귀) ─────────────────────────
      if (myStatus == CallParticipantStatus.accepted) {
        if (!mounted) return;
        _openCallScreen(call);
        return;
      }

      // ─── 권한 체크 ──────────────────────────────────
      final ok = await service.requestPermissions(video: isVideo);
      if (!ok) {
        if (!mounted) return;
        _showSnack('마이크${isVideo ? "/카메라" : ""} 권한이 필요해요');
        return;
      }

      // ─── invited 상태 (받기) ────────────────────────
      if (myStatus == CallParticipantStatus.invited) {
        await service.acceptCall(callId: call.id, isVideo: isVideo);
        if (!mounted) return;
        _openCallScreen(call);
        return;
      }

      // ─── 그룹 — 도중 참여 ───────────────────────────
      if (widget.isGroup) {
        final joined = await service.joinActiveGroupCall(
          callId: call.id,
          isVideo: isVideo,
        );
        if (!joined) {
          if (!mounted) return;
          _showSnack('통화에 참여할 수 없어요');
          return;
        }
        if (!mounted) return;
        _openCallScreen(call);
        return;
      }

      // ─── DM이면서 참가자 아님 — 정상 흐름 아님 ────
      if (!mounted) return;
      _showSnack('통화에 참여할 수 없어요');
    } catch (e) {
      if (mounted) _showSnack('통화 참여 실패: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _openCallScreen(CallModel call) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ActiveCallScreen(
          callId: call.id,
          isVideo: call.callType.isVideo,
          isInitiator: call.initiatorId == myId,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callAsync = ref.watch(roomActiveCallProvider(widget.roomId));
    final call = callAsync.value;
    if (call == null) return const SizedBox.shrink();

    final myStatusAsync = ref.watch(myParticipantStatusProvider(call.id));
    final myStatus = myStatusAsync.value;

    // DM에서 내가 참가자 아니면 표시 안 함 (있을 수 없는 상태)
    if (!widget.isGroup &&
        myStatus != CallParticipantStatus.accepted &&
        myStatus != CallParticipantStatus.invited) {
      return const SizedBox.shrink();
    }

    // DM에서 invited 상태면 풀스크린 IncomingCallScreen이 뜨고 있을 것
    // → 배너로 중복 표시 피하기 위해 숨김 (정책 선택)
    if (!widget.isGroup && myStatus == CallParticipantStatus.invited) {
      return const SizedBox.shrink();
    }

    // 액션 라벨 결정
    String actionLabel;
    if (myStatus == CallParticipantStatus.accepted) {
      actionLabel = '복귀하기';
    } else if (myStatus == CallParticipantStatus.invited) {
      actionLabel = '받기';
    } else {
      actionLabel = '참여하기';
    }

    // 좌측 라벨
    String titleLabel;
    if (myStatus == CallParticipantStatus.accepted) {
      titleLabel = '통화 중';
    } else if (call.status == CallStatus.ringing) {
      titleLabel = widget.isGroup ? '그룹 통화 호출 중' : '통화 호출 중';
    } else {
      titleLabel = widget.isGroup ? '그룹 통화 진행 중' : '통화 진행 중';
    }

    final isVideo = call.callType.isVideo;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: AppTheme.primaryLight,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titleLabel,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: actionLabel,
              processing: _processing,
              onTap: () =>
                  _joinOrReturn(call: call, myStatus: myStatus),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool processing;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.processing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: processing ? null : onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: processing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }
}