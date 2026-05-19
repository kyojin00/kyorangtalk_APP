// ════════════════════════════════════════════════════════════════
// 📞 IncomingCallScreen
//
// ⭐ 버그 수정 이력:
//   v1-v4: navigator 조작 방식 시도 — 모두 실패
//   v5: 위젯 교체 방식 — 여전히 사라짐 (status=declined 감지 후 exit)
//   v6: CallKitService.setIncomingScreenActive로 native decline 차단
//   v7 (current): 토큰 prefetch 추가 — 받기 누를 때 통화 연결 빨라짐
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/call_model.dart';
import '../providers/call_provider.dart';
import '../services/call_kit_service.dart';
import '../services/call_service.dart';
import 'active_call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final CallModel call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState
    extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  String? _callerNickname;
  String? _callerAvatar;
  String? _roomName;

  bool _processing = false;
  bool _accepted = false;
  bool _seenRingingCall = false;
  DateTime? _mountedAt;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();

    // ⭐⭐⭐ 핵심: native actionCallDecline 차단 ON
    CallKitService.instance.setIncomingScreenActive(true);

    // ⭐ 토큰 prefetch — 사용자가 받기 누를 때 토큰 즉시 사용
    //   IncomingCallScreen 떠 있는 동안 백그라운드에서 fetch
    CallService.instance.prefetchToken(widget.call.id);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _loadCallerInfo();

    if (widget.call.status == CallStatus.ringing) {
      _seenRingingCall = true;
    }

    print('🔵 [IncomingCall] mounted callId=${widget.call.id} '
        'status=${widget.call.status.name}');
  }

  @override
  void dispose() {
    print('🔵 [IncomingCall] dispose callId=${widget.call.id}');

    // ⭐⭐⭐ native actionCallDecline 차단 OFF
    CallKitService.instance.setIncomingScreenActive(false);

    _pulseCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadCallerInfo() async {
    final sb = Supabase.instance.client;
    try {
      final profile = await sb
          .from('kyorangtalk_profiles')
          .select('nickname, avatar_url')
          .eq('id', widget.call.initiatorId)
          .maybeSingle();

      String? roomName;
      if (widget.call.roomType == CallRoomType.group) {
        final room = await sb
            .from('kyorangtalk_group_rooms')
            .select('name')
            .eq('id', widget.call.sourceRoomId)
            .maybeSingle();
        roomName = room?['name'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _callerNickname = profile?['nickname'] as String? ?? '알 수 없음';
        _callerAvatar = profile?['avatar_url'] as String?;
        _roomName = roomName;
      });
    } catch (e) {
      print('🔴 _loadCallerInfo 오류: $e');
    }
  }

  bool _shouldAutoPop(CallModel? call) {
    if (_accepted) return false;
    if (_processing) return false;

    final elapsed = DateTime.now()
        .difference(_mountedAt ?? DateTime.now())
        .inMilliseconds;
    if (elapsed < 1000) return false;

    if (call == null) {
      if (!_seenRingingCall) return false;
      print('🔴 [IncomingCall guard] call=null after valid → POP');
      return true;
    }

    if (call.status == CallStatus.ringing) {
      _seenRingingCall = true;
      return false;
    }

    if (call.status.isFinished) {
      print(
          '🔴 [IncomingCall guard] status=${call.status.name} → POP');
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallModel?>>(
      activeCallProvider(widget.call.id),
      (prev, next) {
        next.whenData((call) {
          if (!mounted) return;
          if (_shouldAutoPop(call)) {
            Navigator.of(context).pop();
          }
        });
      },
    );

    // _accepted=true면 ActiveCallScreen 위젯으로 교체 (Navigator 안 건드림)
    if (_accepted) {
      return ActiveCallScreen(
        callId: widget.call.id,
        isVideo: widget.call.callType.isVideo,
        isInitiator: false,
      );
    }

    final isVideo = widget.call.callType.isVideo;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primary.withOpacity(0.9),
                AppTheme.bg,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                Text(
                  isVideo ? '영상 통화 수신 중' : '음성 통화 수신 중',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (_roomName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _roomName!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],

                const Spacer(),

                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) {
                    final scale = 1.0 + (_pulseCtrl.value * 0.08);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 160 * scale,
                          height: 160 * scale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(
                              0.15 - (_pulseCtrl.value * 0.10),
                            ),
                          ),
                        ),
                        Container(
                          width: 140 * scale,
                          height: 140 * scale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(
                              0.20 - (_pulseCtrl.value * 0.10),
                            ),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: AvatarWidget(
                    url: _callerAvatar,
                    name: _callerNickname,
                    size: 120,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  _callerNickname ?? '...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const Spacer(flex: 2),

                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _CallActionButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFEF4444),
                        label: '거절',
                        onTap: _processing ? null : _decline,
                      ),
                      _CallActionButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        color: const Color(0xFF22C55E),
                        label: '받기',
                        onTap: _processing ? null : _accept,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════
  // 받기
  // ════════════════════════════════════════════════
  Future<void> _accept() async {
    if (_processing) return;
    setState(() => _processing = true);
    print('🔵 [_accept] start callId=${widget.call.id}');

    final service = CallService.instance;
    final isVideo = widget.call.callType.isVideo;

    try {
      final ok = await service.requestPermissions(video: isVideo);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('마이크${isVideo ? "/카메라" : ""} 권한이 필요해요'),
          ),
        );
        setState(() => _processing = false);
        return;
      }
      print('🟢 [_accept] 권한 OK');

      if (!mounted) return;

      print('🟢 [_accept] _accepted=true → build에서 ActiveCallScreen으로 교체');
      setState(() {
        _accepted = true;
        _processing = false;
      });
    } catch (e) {
      print('🔴 [_accept] 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('통화 받기 실패: $e')),
        );
        setState(() => _processing = false);
      }
    }
  }

  // ════════════════════════════════════════════════
  // 거절
  // ════════════════════════════════════════════════
  Future<void> _decline() async {
    if (_processing) return;
    setState(() => _processing = true);
    print('🔵 [_decline] callId=${widget.call.id}');

    try {
      await CallKitService.instance.endCall(widget.call.id);
    } catch (_) {}

    try {
      await CallService.instance.declineCall(widget.call.id);
    } catch (e) {
      print('🔴 decline RPC 오류: $e');
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}