import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/security/app_lock_service.dart';

// ═══════════════════════════════════════════════════
// 🔒 AppLockScreen — 앱 잠금 해제
//
// 진입 흐름
//   1) 화면 표시 직후 생체인증 사용 가능 + 활성화돼 있으면 자동 시도
//   2) 실패/취소 시 PIN 키패드 노출
//   3) 4자리 입력 → verifyPin → 성공 시 자동 pop(true)
//   4) 5회 실패 → 30초 카운트다운 + 키패드 비활성화
//
// 뒤로가기 차단 — PopScope (canPop: false)
// ═══════════════════════════════════════════════════

class AppLockScreen extends StatefulWidget {
  /// PIN 검증 후 호출. true 면 잠금 해제 성공.
  final VoidCallback? onUnlocked;

  const AppLockScreen({super.key, this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with TickerProviderStateMixin {
  String _entered = '';
  bool _verifying = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    ));

    _init();
  }

  Future<void> _init() async {
    _biometricAvailable = await AppLockService.canUseBiometric();
    _biometricEnabled = await AppLockService.isBiometricEnabled();

    // 잠금 상태 먼저 체크
    final isLocked = await AppLockService.isLockedOut();
    if (isLocked) {
      final remaining =
          await AppLockService.getRemainingLockoutSeconds();
      _startLockoutCountdown(remaining);
    }

    if (!mounted) return;
    setState(() {});

    // 자동 생체인증 시도
    if (_biometricAvailable && _biometricEnabled && !isLocked) {
      _tryBiometric();
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // 생체인증
  // ─────────────────────────────────────────────
  Future<void> _tryBiometric() async {
    final ok = await AppLockService.authenticateBiometric();
    if (!mounted) return;
    if (ok) {
      _onSuccess();
    }
  }

  // ─────────────────────────────────────────────
  // PIN 입력
  // ─────────────────────────────────────────────
  Future<void> _onDigit(String digit) async {
    if (_verifying || _lockoutSeconds > 0) return;
    if (_entered.length >= 4) return;

    HapticFeedback.lightImpact();
    setState(() => _entered += digit);

    if (_entered.length == 4) {
      await _verify();
    }
  }

  void _onBackspace() {
    if (_verifying || _lockoutSeconds > 0) return;
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final ok = await AppLockService.verifyPin(_entered);
    if (!mounted) return;

    if (ok) {
      _onSuccess();
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);

      // 5회 실패 → 잠금 시작
      final remaining =
          await AppLockService.getRemainingLockoutSeconds();
      if (remaining > 0) {
        _startLockoutCountdown(remaining);
      }

      if (!mounted) return;
      setState(() {
        _entered = '';
        _verifying = false;
      });
    }
  }

  void _onSuccess() {
    HapticFeedback.mediumImpact();
    widget.onUnlocked?.call();
    if (mounted) Navigator.of(context).pop(true);
  }

  // ─────────────────────────────────────────────
  // 잠금 카운트다운
  // ─────────────────────────────────────────────
  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSeconds = seconds);

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _lockoutSeconds--);
      if (_lockoutSeconds <= 0) {
        t.cancel();
      }
    });
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // 자물쇠 아이콘
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primary.withOpacity(0.25),
                        AppTheme.primary.withOpacity(0.10),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    color: AppTheme.primaryLight,
                    size: 36,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  '교랑톡 잠금',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMain,
                    letterSpacing: -0.4,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  _lockoutSeconds > 0
                      ? '$_lockoutSeconds초 후 다시 시도해주세요'
                      : 'PIN을 입력해주세요',
                  style: TextStyle(
                    fontSize: 14,
                    color: _lockoutSeconds > 0
                        ? const Color(0xFFEF4444)
                        : AppTheme.textSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 32),

                // PIN 도트
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) {
                    final dx = _shakeController.isAnimating
                        ? (8 *
                            (1 - _shakeAnim.value) *
                            ((_shakeController.value * 8).toInt() % 2 == 0
                                ? 1
                                : -1))
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _entered.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin:
                            const EdgeInsets.symmetric(horizontal: 10),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? AppTheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: filled
                                ? AppTheme.primary
                                : AppTheme.border,
                            width: 1.5,
                          ),
                          boxShadow: filled
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary
                                        .withOpacity(0.35),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                ),

                const Spacer(flex: 2),

                // 키패드
                _Keypad(
                  enabled: _lockoutSeconds == 0 && !_verifying,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  trailingButton: (_biometricAvailable && _biometricEnabled)
                      ? _BiometricButton(
                          enabled: _lockoutSeconds == 0,
                          onTap: _tryBiometric,
                        )
                      : null,
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 키패드 (3 x 4)
// ═══════════════════════════════════════════════════
class _Keypad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? trailingButton; // 좌하단 보조 버튼 (지문 등)

  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    this.trailingButton,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(['1', '2', '3']),
        const SizedBox(height: 14),
        _row(['4', '5', '6']),
        const SizedBox(height: 14),
        _row(['7', '8', '9']),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: trailingButton ?? const SizedBox(),
            ),
            const SizedBox(width: 18),
            _DigitButton(
              digit: '0',
              enabled: enabled,
              onTap: () => onDigit('0'),
            ),
            const SizedBox(width: 18),
            _BackspaceButton(
              enabled: enabled,
              onTap: onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < digits.length; i++) ...[
          _DigitButton(
            digit: digits[i],
            enabled: enabled,
            onTap: () => onDigit(digits[i]),
          ),
          if (i < digits.length - 1) const SizedBox(width: 18),
        ],
      ],
    );
  }
}

class _DigitButton extends StatelessWidget {
  final String digit;
  final bool enabled;
  final VoidCallback onTap;

  const _DigitButton({
    required this.digit,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? AppTheme.textMain
                    : AppTheme.textMuted,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackspaceButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _BackspaceButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 24,
              color: enabled
                  ? AppTheme.textMain
                  : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _BiometricButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withOpacity(0.12),
              border: Border.all(
                color: AppTheme.primary.withOpacity(0.3),
                width: 1.2,
              ),
            ),
            child: Icon(
              Icons.fingerprint_rounded,
              color: enabled
                  ? AppTheme.primaryLight
                  : AppTheme.textMuted,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}