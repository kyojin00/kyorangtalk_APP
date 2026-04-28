import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'login_method_screen.dart';
import 'signup_method_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _particleController;
  late AnimationController _fadeController;
  late Animation<double> _logoScaleAnim;
  late Animation<double> _logoGlowAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _logoScaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _logoGlowAnim = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _particleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginMethodScreen(),
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
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SignupMethodScreen(),
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
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (_, __) => CustomPaint(
                painter: _ParticlePainter(_particleController.value),
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
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (_, __) => Transform.scale(
                        scale: _logoScaleAnim.value,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary
                                    .withOpacity(_logoGlowAnim.value),
                                blurRadius: 50,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
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
                        '교랑톡',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '친구들과 편하게 이야기해요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.6),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(flex: 3),
                    Text(
                      '시작할 준비가 되셨나요?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
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
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _goToLogin,
                          borderRadius: BorderRadius.circular(16),
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  '로그인하기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _goToSignup,
                          borderRadius: BorderRadius.circular(16),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_alt_1_rounded,
                                    color: Colors.white.withOpacity(0.9),
                                    size: 20),
                                const SizedBox(width: 10),
                                const Text(
                                  '회원가입하기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      '시작하면 이용약관 및 개인정보처리방침에 동의합니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double progress;

  _ParticlePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);

    for (int i = 0; i < 25; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.3 + random.nextDouble() * 0.7;
      final y = (baseY + progress * size.height * speed) % size.height;

      final radius = 1.0 + random.nextDouble() * 2.5;
      final opacity = 0.2 + random.nextDouble() * 0.4;

      final paint = Paint()
        ..color = const Color(0xFF7C3AED).withOpacity(opacity * 0.6)
        ..style = PaintingStyle.fill
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress;
}