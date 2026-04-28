import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'phone_login_screen.dart';
import 'email_login_screen.dart';
import 'signup_method_screen.dart';

class LoginMethodScreen extends ConsumerStatefulWidget {
  const LoginMethodScreen({super.key});

  @override
  ConsumerState<LoginMethodScreen> createState() =>
      _LoginMethodScreenState();
}

class _LoginMethodScreenState extends ConsumerState<LoginMethodScreen> {
  bool _googleLoading = false;

  Future<void> _handleGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
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

  void _goToEmail() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const EmailLoginScreen(),
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

  void _goToSignup() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SignupMethodScreen(),
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
                // 뒤로가기
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // ✨ 타이틀
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.white,
                              AppTheme.primaryLight,
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            '로그인',
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
                          '어떤 방법으로 로그인하시겠어요?',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),

                        const SizedBox(height: 48),

                        // ✨ 이메일 로그인
                        _MethodButton(
                          onTap: _goToEmail,
                          icon: Icons.email_outlined,
                          iconColor: AppTheme.primaryLight,
                          iconBg:
                              AppTheme.primary.withOpacity(0.2),
                          title: '이메일로 로그인',
                          subtitle: '이메일과 비밀번호로 로그인',
                        ),

                        const SizedBox(height: 12),

                        // ✨ 전화번호 로그인
                        _MethodButton(
                          onTap: _goToPhone,
                          icon: Icons.phone_android_rounded,
                          iconColor: const Color(0xFF10B981),
                          iconBg: const Color(0xFF10B981)
                              .withOpacity(0.15),
                          title: '전화번호로 로그인',
                          subtitle: '휴대폰 번호로 간편 로그인',
                        ),

                        const SizedBox(height: 12),

                        // ✨ 구글 로그인
                        _MethodButton(
                          onTap:
                              _googleLoading ? null : _handleGoogle,
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
                          title: 'Google로 로그인',
                          subtitle: 'Google 계정으로 빠른 로그인',
                        ),

                        const Spacer(),

                        // 회원가입 유도
                        Center(
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                '아직 계정이 없으신가요?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withOpacity(0.5),
                                ),
                              ),
                              TextButton(
                                onPressed: _goToSignup,
                                child: Text(
                                  '회원가입하기',
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
// 로그인 방법 버튼 (공통)
// ═══════════════════════════════════════════════
class _MethodButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? customIcon;
  final Color? iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool loading;

  const _MethodButton({
    this.onTap,
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
    return Container(
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
                  Icons.arrow_forward_ios,
                  color: Colors.white.withOpacity(0.3),
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}