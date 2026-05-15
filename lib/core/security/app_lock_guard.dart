import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../features/profile/screens/app_lock_screen.dart';
import '../../main.dart' show navigatorKey;
import 'app_lock_service.dart';

// ═══════════════════════════════════════════════════
// 🛡️ AppLockGuard (v2)
//
// 위치: lib/core/security/app_lock_guard.dart
//
// 변경 사항 (v1 → v2)
// - Navigator.of(context) 대신 main.dart의 navigatorKey 사용
//   (GoRouter 환경에서 안전하게 라우터 Navigator를 잡음)
// - debugPrint 추가 — 콘솔에서 동작 추적
//
// 동작
// - 앱 시작(cold start) 시 잠금 활성화 + PIN 있으면 잠금 화면 표시
// - 백그라운드 진입(paused/inactive) 시 즉시 잠금 화면 push
// - 잠금 화면이 이미 떠 있으면 중복 push 안 함
// ═══════════════════════════════════════════════════

class AppLockGuard extends StatefulWidget {
  final Widget child;

  const AppLockGuard({super.key, required this.child});

  @override
  State<AppLockGuard> createState() => _AppLockGuardState();
}

class _AppLockGuardState extends State<AppLockGuard>
    with WidgetsBindingObserver {
  bool _lockShown = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🛡️ [AppLockGuard] initState');
    WidgetsBinding.instance.addObserver(this);

    // 첫 프레임 직후 잠금 체크 (Navigator 준비된 후)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('🛡️ [AppLockGuard] postFrame — cold start check');
      await _maybeShowLock(reason: 'cold_start');
      _initialized = true;
    });
  }

  @override
  void dispose() {
    debugPrint('🛡️ [AppLockGuard] dispose');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
        '🛡️ [AppLockGuard] lifecycle=$state initialized=$_initialized');
    if (!_initialized) return;

    // paused / inactive 시 즉시 잠금 → 앱 스위처 미리보기 가리기
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _maybeShowLock(reason: 'background');
    }
  }

  Future<void> _maybeShowLock({required String reason}) async {
    debugPrint(
        '🛡️ [AppLockGuard] _maybeShowLock reason=$reason shown=$_lockShown');
    if (_lockShown) return;

    final enabled = await AppLockService.isLockEnabled();
    final hasPin = await AppLockService.hasPin();
    debugPrint('🛡️ [AppLockGuard] enabled=$enabled hasPin=$hasPin');

    if (!enabled || !hasPin) return;

    // ⭐ main.dart의 navigatorKey 사용 — 라우터 Navigator를 정확히 잡음
    final navigatorState = navigatorKey.currentState;
    if (navigatorState == null) {
      debugPrint(
          '🔴 [AppLockGuard] navigatorKey.currentState == null! 라우터 미준비');
      return;
    }

    _lockShown = true;
    debugPrint('🛡️ [AppLockGuard] pushing lock screen...');

    await navigatorState.push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => const AppLockScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    _lockShown = false;
    debugPrint('🛡️ [AppLockGuard] lock screen popped');
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}