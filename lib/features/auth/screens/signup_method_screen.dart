import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'phone_login_screen.dart';
import 'email_signup_screen.dart';
import 'login_method_screen.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';

class SignupMethodScreen extends ConsumerStatefulWidget {
  const SignupMethodScreen({super.key});

  @override
  ConsumerState<SignupMethodScreen> createState() =>
      _SignupMethodScreenState();
}

class _SignupMethodScreenState extends ConsumerState<SignupMethodScreen> {
  bool _googleLoading = false;
  bool _agreedTerms = false;
  bool _agreedPrivacy = false;
  bool _agreedMarketing = false;

  bool get _canProceed => _agreedTerms && _agreedPrivacy;
  bool get _allAgreed =>
      _agreedTerms && _agreedPrivacy && _agreedMarketing;

  void _toggleAll(bool? value) {
    setState(() {
      final newValue = value ?? false;
      _agreedTerms = newValue;
      _agreedPrivacy = newValue;
      _agreedMarketing = newValue;
    });
  }

  void _showRequiredError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('필수 약관에 동의해주세요'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleGoogle() async {
    if (!_canProceed) {
      _showRequiredError();
      return;
    }

    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // 약관 동의 시간은 온보딩에서 저장
      _saveAgreementToPrefs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google 로그인 중 오류가 발생했어요')),
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // 약관 동의 정보를 임시로 저장 (온보딩에서 DB에 기록)
  void _saveAgreementToPrefs() {
    // static 변수 또는 SharedPreferences에 저장
    TempSignupAgreement.termsAgreed = _agreedTerms;
    TempSignupAgreement.privacyAgreed = _agreedPrivacy;
    TempSignupAgreement.marketingAgreed = _agreedMarketing;
  }

  void _goToEmail() {
    if (!_canProceed) {
      _showRequiredError();
      return;
    }
    _saveAgreementToPrefs();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const EmailSignupScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  void _goToPhone() {
    if (!_canProceed) {
      _showRequiredError();
      return;
    }
    _saveAgreementToPrefs();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PhoneLoginScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginMethodScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A0B3D),
                    Color(0xFF0F0F1F),
                    Color(0xFF080810),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -100, left: -50, right: -50,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.white,
                              AppTheme.primaryLight,
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            '회원가입',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '어떤 방법으로 가입하시겠어요?',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),

                        const SizedBox(height: 32),

                        _MethodButton(
                          onTap: _goToEmail,
                          disabled: !_canProceed,
                          icon: Icons.email_outlined,
                          iconColor: AppTheme.primaryLight,
                          iconBg: AppTheme.primary.withOpacity(0.2),
                          title: '이메일로 가입',
                          subtitle: '이메일과 비밀번호로 가입',
                        ),

                        const SizedBox(height: 12),

                        _MethodButton(
                          onTap: _goToPhone,
                          disabled: !_canProceed,
                          icon: Icons.phone_android_rounded,
                          iconColor: const Color(0xFF10B981),
                          iconBg: const Color(0xFF10B981)
                              .withOpacity(0.15),
                          title: '전화번호로 가입',
                          subtitle: '휴대폰 번호로 간편 가입',
                        ),

                        const SizedBox(height: 12),

                        _MethodButton(
                          onTap: _googleLoading || !_canProceed
                              ? null
                              : _handleGoogle,
                          disabled: !_canProceed,
                          loading: _googleLoading,
                          customIcon: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                          iconBg: Colors.white.withOpacity(0.1),
                          title: 'Google로 가입',
                          subtitle: 'Google 계정으로 빠른 가입',
                        ),

                        const SizedBox(height: 24),

                        // ✨ 약관 동의 섹션
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              // 전체 동의
                              InkWell(
                                onTap: () => _toggleAll(!_allAgreed),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          vertical: 4),
                                  child: Row(
                                    children: [
                                      _Checkbox(
                                        value: _allAgreed,
                                        onChanged: (v) =>
                                            _toggleAll(v),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '전체 동의',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              Divider(
                                color:
                                    Colors.white.withOpacity(0.1),
                                height: 24,
                              ),

                              // 이용약관 (필수)
                              _AgreementRow(
                                checked: _agreedTerms,
                                onChanged: (v) => setState(
                                    () => _agreedTerms = v ?? false),
                                text: '이용약관 동의',
                                required: true,
                                onViewTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const TermsOfServiceScreen(),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 8),

                              // 개인정보처리방침 (필수)
                              _AgreementRow(
                                checked: _agreedPrivacy,
                                onChanged: (v) => setState(() =>
                                    _agreedPrivacy = v ?? false),
                                text: '개인정보처리방침 동의',
                                required: true,
                                onViewTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PrivacyPolicyScreen(),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 8),

                              // 마케팅 알림 (선택)
                              _AgreementRow(
                                checked: _agreedMarketing,
                                onChanged: (v) => setState(() =>
                                    _agreedMarketing = v ?? false),
                                text: '마케팅 알림 수신',
                                required: false,
                                onViewTap: null,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        Center(
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                '이미 계정이 있으신가요?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withOpacity(0.5),
                                ),
                              ),
                              TextButton(
                                onPressed: _goToLogin,
                                child: Text(
                                  '로그인하기',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.primaryLight,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 약관 동의 임시 저장 (온보딩에서 사용)
// ═══════════════════════════════════════════════
class TempSignupAgreement {
  static bool termsAgreed = false;
  static bool privacyAgreed = false;
  static bool marketingAgreed = false;

  static void clear() {
    termsAgreed = false;
    privacyAgreed = false;
    marketingAgreed = false;
  }
}

// ═══════════════════════════════════════════════
// 커스텀 체크박스
// ═══════════════════════════════════════════════
class _Checkbox extends StatelessWidget {
  final bool value;
  final Function(bool?) onChanged;

  const _Checkbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value
                ? AppTheme.primary
                : Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: value
            ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 14,
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 약관 동의 행
// ═══════════════════════════════════════════════
class _AgreementRow extends StatelessWidget {
  final bool checked;
  final Function(bool?) onChanged;
  final String text;
  final bool required;
  final VoidCallback? onViewTap;

  const _AgreementRow({
    required this.checked,
    required this.onChanged,
    required this.text,
    required this.required,
    required this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Checkbox(value: checked, onChanged: onChanged),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!checked),
            child: Row(
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  required ? '(필수)' : '(선택)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: required
                        ? AppTheme.primary
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onViewTap != null)
          GestureDetector(
            onTap: onViewTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '보기',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                      decoration: TextDecoration.underline,
                      decorationColor:
                          Colors.white.withOpacity(0.3),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// 회원가입 방법 버튼
// ═══════════════════════════════════════════════
class _MethodButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool disabled;
  final IconData? icon;
  final Widget? customIcon;
  final Color? iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool loading;

  const _MethodButton({
    this.onTap,
    this.disabled = false,
    this.icon,
    this.customIcon,
    this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: loading
                        ? Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: iconColor ?? Colors.white,
                              ),
                            ),
                          )
                        : Center(
                            child: customIcon ??
                                Icon(icon,
                                    color: iconColor, size: 22),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    disabled ? Icons.lock_outline : Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.3),
                    size: disabled ? 16 : 14,
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