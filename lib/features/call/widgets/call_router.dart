// ════════════════════════════════════════════════════════════════
// 📞 CallRouter
//
// 앱 최상위 어딘가에 한 번만 배치.
// incomingCallProvider를 listen해서 ringing 통화가 감지되면
// 자동으로 IncomingCallScreen을 띄움.
//
// ⭐ 수정: Navigator.of(context) → navigatorKey 사용
//   builder 안 Stack의 context는 Navigator의 ABOVE라서 Navigator.of(context)
//   가 못 찾음. 전역 navigatorKey를 사용해야 함.
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart' show navigatorKey;
import '../models/call_model.dart';
import '../providers/call_provider.dart';
import '../screens/incoming_call_screen.dart';

class CallRouter extends ConsumerStatefulWidget {
  const CallRouter({super.key});

  @override
  ConsumerState<CallRouter> createState() => _CallRouterState();
}

class _CallRouterState extends ConsumerState<CallRouter> {
  String? _shownCallId;
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CallModel?>>(incomingCallProvider, (prev, next) {
      next.whenData((call) {
        if (call == null) {
          _shownCallId = null;
          return;
        }

        // 같은 통화에 대해 중복 표시 방지
        if (_shownCallId == call.id) return;
        if (_isNavigating) return;

        // ringing 상태일 때만 화면 띄움
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
      // ⭐ context 대신 전역 navigatorKey 사용
      // app.dart의 Stack 안 context는 MaterialApp의 Navigator 위에 있어서
      // Navigator.of(context)가 동작하지 않음
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        print('🔴 [CallRouter] navigatorKey.currentState == null');
        _shownCallId = null;
        return;
      }

      print('🟢 [CallRouter] IncomingCallScreen 표시: ${call.id}');

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
    } catch (e) {
      print('🔴 [CallRouter] _showIncomingCall 오류: $e');
    } finally {
      _isNavigating = false;
    }
  }
}