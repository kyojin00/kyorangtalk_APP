// ════════════════════════════════════════════════════════════════
// 📞 OngoingCallBanner — 전역 통화중 배너
//
// ⭐ 수정 (시간초 일치):
//   - 이전: call.answeredAt 기반 (서버 RPC 시점)
//   - 이후: CallService.durationStream 구독 (Agora 첫 remote join 시점)
//   - ActiveCallScreen과 같은 source를 보므로 시간 일치
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show navigatorKey;
import '../models/call_model.dart';
import '../providers/ongoing_call_provider.dart';
import '../screens/active_call_screen.dart';
import '../services/call_service.dart';

class OngoingCallBanner extends ConsumerStatefulWidget {
  const OngoingCallBanner({super.key});

  @override
  ConsumerState<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends ConsumerState<OngoingCallBanner> {
  StreamSubscription<int>? _durationSub;
  int _durationSec = 0;

  // CallService와 동기 안 되는 fallback 시 1초 ticker
  Timer? _fallbackTicker;

  @override
  void initState() {
    super.initState();
    _durationSub = CallService.instance.durationStream.listen((sec) {
      if (!mounted) return;
      setState(() => _durationSec = sec);
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _fallbackTicker?.cancel();
    super.dispose();
  }

  void _ensureFallbackTicker(bool needed) {
    if (needed && _fallbackTicker == null) {
      _fallbackTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed && _fallbackTicker != null) {
      _fallbackTicker?.cancel();
      _fallbackTicker = null;
    }
  }

  String _formatSeconds(int sec) {
    final h = sec ~/ 3600;
    final m = ((sec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _returnToCall(CallModel call) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ActiveCallScreen(
          callId: call.id,
          isVideo: call.callType.isVideo,
          isInitiator:
              call.initiatorId == Supabase.instance.client.auth.currentUser?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnCallScreen = ref.watch(isOnActiveCallScreenProvider);
    final callAsync = ref.watch(myOngoingCallProvider);

    final call = callAsync.value;
    final shouldShow = call != null && !isOnCallScreen;

    if (!shouldShow) {
      _ensureFallbackTicker(false);
      return const SizedBox.shrink();
    }

    final topInset = MediaQuery.of(context).padding.top;
    final isActive = call.status == CallStatus.active;
    final isVideo = call.callType.isVideo;

    final service = CallService.instance;
    final inSameCall =
        service.isInCall && service.currentCallId == call.id;

    // ─── 시간/라벨 결정 ──────────────────────────────
    String label;
    if (isActive && inSameCall) {
      // ⭐ ActiveCallScreen과 같은 source — 시간 일치
      _ensureFallbackTicker(false);
      label = _formatSeconds(_durationSec);
    } else if (isActive && call.answeredAt != null) {
      // CallService와 동기 안 된 케이스 fallback
      _ensureFallbackTicker(true);
      final d = DateTime.now().difference(call.answeredAt!);
      final sec = d.inSeconds < 0 ? 0 : d.inSeconds;
      label = _formatSeconds(sec);
    } else if (call.status == CallStatus.ringing) {
      _ensureFallbackTicker(false);
      label = '연결 중...';
    } else {
      _ensureFallbackTicker(false);
      label = call.status.label;
    }

    return Positioned(
      top: topInset + 4,
      left: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          top: false,
          child: GestureDetector(
            onTap: () => _returnToCall(call),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isActive ? '통화 중' : '통화 진행 중',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '돌아가기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}