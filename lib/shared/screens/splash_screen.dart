import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _dotsController;
  late AnimationController _fadeController;

  late Animation<double> _glowAnimation;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    // ✨ 로고는 이미 네이티브 스플래시에 있음 (크기 100% 유지)
    // 나머지 요소들만 페이드인

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // 부가 요소들 페이드인
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOut,
      ),
    );

    // 바로 페이드인 시작
    _fadeController.forward();

    _navigate();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _dotsController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    if (session == null) {
      context.go('/login');
      return;
    }

    try {
      final userResponse = await supabase.auth.getUser();
      final user = userResponse.user;

      if (user == null) {
        print('유저가 존재하지 않음, 세션 정리');
        await supabase.auth.signOut();
        if (mounted) context.go('/login');
        return;
      }

      final data = await supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final hasProfile = data != null &&
          (data['nickname'] as String?)?.isNotEmpty == true;

      if (hasProfile) {
        await handlePendingNotification();
        if (!mounted) return;
        context.go('/main');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      print('스플래시 오류: $e');
      try {
        await supabase.auth.signOut();
      } catch (_) {}
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ✨ 동일한 그라데이션 배경 (네이티브와 완벽히 일치)
          Container(
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

          // ✨ 파티클 (페이드인)
          FadeTransition(
            opacity: _fadeInAnimation,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (_, __) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _ParticlePainter(
                      animation: _glowController.value),
                );
              },
            ),
          ),

          // ✨ 중앙 컨텐츠
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고 (네이티브와 똑같은 위치/크기, 글로우만 추가)
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (_, __) {
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary
                                .withOpacity(_glowAnimation.value),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: AppTheme.primaryLight
                                .withOpacity(
                                    _glowAnimation.value * 0.5),
                            blurRadius: 60,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primary,
                                AppTheme.primaryLight,
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text(
                                  '💬',
                                  style: TextStyle(fontSize: 56),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // ✨ 앱 이름 (부드럽게 페이드인)
                FadeTransition(
                  opacity: _fadeInAnimation,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Colors.white,
                        AppTheme.primaryLight,
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      '교랑톡',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                FadeTransition(
                  opacity: _fadeInAnimation,
                  child: Text(
                    '친구들과 편하게 이야기해요',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                const SizedBox(height: 60),

                // ✨ 점 3개 애니메이션
                FadeTransition(
                  opacity: _fadeInAnimation,
                  child: AnimatedBuilder(
                    animation: _dotsController,
                    builder: (_, __) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final delay = i * 0.2;
                          final progress =
                              (_dotsController.value - delay)
                                  .clamp(0.0, 1.0);
                          final scale = math.sin(progress * math.pi);

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4),
                            child: Container(
                              width: 8 + (scale * 4),
                              height: 8 + (scale * 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryLight
                                    .withOpacity(
                                        0.4 + (scale * 0.6)),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ✨ 하단 워터마크
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeInAnimation,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.0),
                          AppTheme.primaryLight,
                          AppTheme.primary.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'KYORANG TALK',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 떠다니는 파티클
class _ParticlePainter extends CustomPainter {
  final double animation;

  _ParticlePainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);

    for (int i = 0; i < 6; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y = baseY + math.sin(animation * 2 * math.pi + i) * 15;
      final radius = 3.0 + random.nextDouble() * 4;
      final opacity = 0.1 + random.nextDouble() * 0.2;

      final paint = Paint()
        ..color = const Color(0xFFA78BFA).withOpacity(opacity)
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    for (int i = 0; i < 12; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y = baseY + math.cos(animation * 2 * math.pi + i) * 10;
      final radius = 1.0 + random.nextDouble() * 1.5;
      final opacity = 0.15 + random.nextDouble() * 0.25;

      final paint = Paint()
        ..color = const Color(0xFF7C3AED).withOpacity(opacity)
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => true;
}