import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class EmailSignupScreen extends ConsumerStatefulWidget {
  const EmailSignupScreen({super.key});

  @override
  ConsumerState<EmailSignupScreen> createState() =>
      _EmailSignupScreenState();
}

class _EmailSignupScreenState extends ConsumerState<EmailSignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;

    if (email.isEmpty || password.isEmpty || passwordConfirm.isEmpty) {
      setState(() => _error = '모든 항목을 입력해주세요');
      return;
    }

    if (!email.contains('@')) {
      setState(() => _error = '올바른 이메일 형식이 아니에요');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 해요');
      return;
    }

    if (password != passwordConfirm) {
      setState(() => _error = '비밀번호가 일치하지 않아요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 이메일 회원가입
      await ref.read(authServiceProvider).signUpWithEmail(email, password);

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Column(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mark_email_read_outlined,
                      color: AppTheme.primary, size: 32),
                ),
                const SizedBox(height: 12),
                Text('인증 메일 발송',
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '환영해요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '가입 메일이 발송됐어요!\n메일함에서 인증 링크를 클릭해주세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                  ),
                  child: const Text('확인',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        final msg = e.toString();
        if (msg.contains('already')) {
          _error = '이미 가입된 이메일이에요';
        } else if (msg.contains('invalid')) {
          _error = '올바른 이메일 형식이 아니에요';
        } else {
          _error = '회원가입 중 오류가 발생했어요';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color:
                                    AppTheme.primary.withOpacity(0.3)),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: AppTheme.primaryLight,
                            size: 30,
                          ),
                        ),

                        const SizedBox(height: 24),

                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.white,
                              AppTheme.primaryLight,
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            '이메일로 가입',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '이메일과 비밀번호를 입력해주세요',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),

                        const SizedBox(height: 40),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFEF4444)
                                      .withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFEF4444),
                                    size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 이메일
                        const _FieldLabel(label: '이메일'),
                        const SizedBox(height: 8),
                        _GlassTextField(
                          controller: _emailController,
                          hint: 'example@kyorang.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),

                        const SizedBox(height: 20),

                        // 비밀번호
                        const _FieldLabel(label: '비밀번호'),
                        const SizedBox(height: 8),
                        _GlassTextField(
                          controller: _passwordController,
                          hint: '6자 이상 입력',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white.withOpacity(0.5),
                              size: 20,
                            ),
                            onPressed: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // 비밀번호 확인
                        const _FieldLabel(label: '비밀번호 확인'),
                        const SizedBox(height: 8),
                        _GlassTextField(
                          controller: _passwordConfirmController,
                          hint: '비밀번호 다시 입력',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePasswordConfirm,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePasswordConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white.withOpacity(0.5),
                              size: 20,
                            ),
                            onPressed: () => setState(() =>
                                _obscurePasswordConfirm =
                                    !_obscurePasswordConfirm),
                          ),
                          onSubmitted: (_) => _handleSignup(),
                        ),

                        const SizedBox(height: 32),

                        // 회원가입 버튼
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primary,
                                AppTheme.primaryLight,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppTheme.primary.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _loading ? null : _handleSignup,
                              borderRadius: BorderRadius.circular(16),
                              child: Center(
                                child: _loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        '회원가입 완료',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
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
// 필드 라벨
// ═══════════════════════════════════════════════
class _FieldLabel extends StatelessWidget {
  final String label;
  final String? hint;

  const _FieldLabel({required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// 글라스 텍스트필드
// ═══════════════════════════════════════════════
class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final void Function(String)? onSubmitted;
  final int? maxLength;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onSubmitted,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autocorrect: false,
        onSubmitted: onSubmitted,
        maxLength: maxLength,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withOpacity(0.5),
            size: 20,
          ),
          suffixIcon: suffixIcon,
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
          filled: false,
        ),
      ),
    );
  }
}