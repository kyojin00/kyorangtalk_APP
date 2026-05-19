// ════════════════════════════════════════════════════════════════
// 📞 CallRouter
//
// ringing 통화 감지 시 IncomingCallScreen을 root navigator에 push.
//
// ⭐ 수정 (GoRouter stack wipeout 대응):
//   - 앱 cold start 시 SplashScreen 위에 IncomingCallScreen push되지만,
//     SplashScreen이 context.go('/main')로 redirect 시 GoRouter가
//     imperative push 라우트를 전부 wipeout함 → IncomingCallScreen 사라짐.
//   - 300ms 주기로 ringing call이 있는데 IncomingCallScreen이 사라졌으면
//     (CallKitService.incomingScreenActive == false) 다시 push.
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart' show navigatorKey;
import '../models/call_model.dart';
import '../providers/call_provider.dart';
import '../screens/incoming_call_screen.dart';
import '../services/call_kit_service.dart';

class CallRouter extends ConsumerStatefulWidget {
  const CallRouter({super.key});

  @override
  ConsumerState<CallRouter> createState() => _CallRouterState();
}

class _CallRouterState extends ConsumerState<CallRouter> {
  String? _shownCallId;
  bool _isNavigating = false;
  Timer? _recheckTimer;

  @override
  void initState() {
    super.initState();
    // ⭐ GoRouter가 SplashScreen → /main 이동 시 imperative push된 IncomingCallScreen을
    //   wipeout하는 경우 대응: 주기적으로 살아있는지 확인 후 다시 push
    _recheckTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _recheck(),
    );
  }

  @override
  void dispose() {
    _recheckTimer?.cancel();
    super.dispose();
  }

  void _recheck() {
    if (_isNavigating) return;
    if (!mounted) return;

    final asyncCall = ref.read(incomingCallProvider);
    final call = asyncCall.valueOrNull;

    if (call == null) {
      _shownCallId = null;
      return;
    }
    if (!call.isIncoming) return;

    // IncomingCallScreen이 실제로 살아있으면 skip
    if (CallKitService.instance.incomingScreenActive) {
      _shownCallId = call.id;
      return;
    }

    // ringing call이 있는데 IncomingCallScreen은 없음 = GoRouter 등이 날린 경우
    print('🔄 [CallRouter] IncomingCallScreen 사라짐 감지 — 재push: ${call.id}');
    _shownCallId = null;
    _showIncomingCall(call);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallModel?>>(incomingCallProvider, (prev, next) {
      next.whenData((call) {
        if (call == null) {
          _shownCallId = null;
          return;
        }
        if (_shownCallId == call.id) return;
        if (_isNavigating) return;
        if (!call.isIncoming) return;

        _shownCallId = call.id;
        _showIncomingCall(call);
      });
    });

    return const SizedBox.shrink();
  }

  Future<void> _showIncomingCall(CallModel call) async {
    _isNavigating = true;
    try {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        print('🔴 [CallRouter] navigatorKey.currentState == null');
        _shownCallId = null;
        return;
      }

      print('🟢 [CallRouter] IncomingCallScreen push: ${call.id}');

      await navigator.push(
        PageRouteBuilder(
          opaque: true,
          fullscreenDialog: true,
          pageBuilder: (_, __, ___) => IncomingCallScreen(call: call),
          transitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(opacity: anim, child: child);
          },
        ),
      );

      // push가 pop으로 resolve됨 (통화 종료 또는 사용자가 닫음)
      print('🔵 [CallRouter] IncomingCallScreen pop됨: ${call.id}');
    } catch (e) {
      print('🔴 [CallRouter] _showIncomingCall 오류: $e');
    } finally {
      _isNavigating = false;
    }
  }
}