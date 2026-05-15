import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/security/app_lock_service.dart';

// ═══════════════════════════════════════════════════
// 🔐 AppLockSetupScreen — PIN 설정 / 변경
//
// 모드
//   new    : PIN 입력 → 한 번 더 → 저장
//   change : 현재 PIN 확인 → 새 PIN → 한 번 더 → 저장
//
// 완료 시 Navigator.pop(true), 취소 시 Navigator.pop(false)
// ═══════════════════════════════════════════════════

enum AppLockSetupMode { newPin, changePin }

enum _Step { current, enter, confirm }

class AppLockSetupScreen extends StatefulWidget {
  final AppLockSetupMode mode;

  const AppLockSetupScreen({
    super.key,
    this.mode = AppLockSetupMode.newPin,
  });

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen>
    with TickerProviderStateMixin {
  late _Step _step;
  String _entered = '';
  String _firstPin = '';
  bool _busy = false;
  String? _error;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _step = widget.mode == AppLockSetupMode.changePin
        ? _Step.current
        : _Step.enter;

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.mode) {
      case AppLockSetupMode.newPin:
        return 'PIN 설정';
      case AppLockSetupMode.changePin:
        return 'PIN 변경';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _Step.current:
        return '현재 PIN을 입력해주세요';
      case _Step.enter:
        return widget.mode == AppLockSetupMode.changePin
            ? '새 PIN 4자리를 입력해주세요'
            : 'PIN 4자리를 입력해주세요';
      case _Step.confirm:
        return '한 번 더 입력해주세요';
    }
  }

  // ─────────────────────────────────────────────
  // PIN 입력
  // ─────────────────────────────────────────────
  Future<void> _onDigit(String digit) async {
    if (_busy) return;
    if (_entered.length >= 4) return;

    HapticFeedback.lightImpact();
    setState(() {
      _entered += digit;
      _error = null;
    });

    if (_entered.length == 4) {
      await _handle4Digit();
    }
  }

  void _onBackspace() {
    if (_busy) return;
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _handle4Digit() async {
    setState(() => _busy = true);

    switch (_step) {
      case _Step.current:
        await _verifyCurrent();
        break;
      case _Step.enter:
        _moveToConfirm();
        break;
      case _Step.confirm:
        await _saveNewPin();
        break;
    }
  }

  // ─────────────────────────────────────────────
  // 현재 PIN 확인
  // ─────────────────────────────────────────────
  Future<void> _verifyCurrent() async {
    final ok = await AppLockService.verifyPin(_entered);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _step = _Step.enter;
        _entered = '';
        _busy = false;
        _error = null;
      });
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() {
        _entered = '';
        _busy = false;
        _error = '현재 PIN이 일치하지 않아요';
      });
    }
  }

  // ─────────────────────────────────────────────
  // 새 PIN 1단계 → 2단계
  // ─────────────────────────────────────────────
  void _moveToConfirm() {
    setState(() {
      _firstPin = _entered;
      _step = _Step.confirm;
      _entered = '';
      _busy = false;
    });
  }

  // ─────────────────────────────────────────────
  // 새 PIN 2단계 → 저장
  // ─────────────────────────────────────────────
  Future<void> _saveNewPin() async {
    if (_entered != _firstPin) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() {
        _step = _Step.enter;
        _entered = '';
        _firstPin = '';
        _busy = false;
        _error = 'PIN이 일치하지 않아요. 처음부터 다시 입력해주세요';
      });
      return;
    }

    try {
      await AppLockService.setPin(_entered);
      // 첫 설정인 경우 잠금도 자동 활성화
      if (widget.mode == AppLockSetupMode.newPin) {
        await AppLockService.setLockEnabled(true);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '저장 실패: $e';
      });
    }
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textMain, size: 18),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _title,
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                width: 72,
                height: 72,
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
                  _step == _Step.confirm
                      ? Icons.check_rounded
                      : Icons.lock_outline_rounded,
                  color: AppTheme.primaryLight,
                  size: 32,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                _subtitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 6),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _error != null
                    ? Text(
                        _error!,
                        key: const ValueKey('err'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: const Color(0xFFEF4444),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      )
                    : Text(
                        _hint(),
                        key: const ValueKey('hint'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSub,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),

              const SizedBox(height: 28),

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
                      offset: Offset(dx, 0), child: child);
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

              _Keypad(
                enabled: !_busy,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _hint() {
    switch (_step) {
      case _Step.current:
        return '현재 사용 중인 PIN을 입력해주세요';
      case _Step.enter:
        return '숫자 4자리';
      case _Step.confirm:
        return '확인을 위해 동일한 PIN을 입력해주세요';
    }
  }
}

// ═══════════════════════════════════════════════════
// 키패드 (3 x 4)
// ═══════════════════════════════════════════════════
class _Keypad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
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
            const SizedBox(width: 72, height: 72),
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