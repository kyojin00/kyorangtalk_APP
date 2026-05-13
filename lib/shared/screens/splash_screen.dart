import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

// ═══════════════════════════════════════════════════
// 🌟 SplashScreen — 글자 애니메이션 (Google Fonts 적용)
//
// 흐름:
//  0.0s  ─ 검정 그라데이션 배경 등장
//  0.2s  ─ "교" 페이드인
//  0.7s  ─ "랑" 페이드인 (교 옆에 추가)
//  1.3s  ─ "교 랑" 유지
//  1.6s  ─ "교 랑" 페이드아웃 (위로 살짝)
//  2.0s  ─ "KYORANG" 등장 (Playfair Display, 부드러운 세리프)
//  2.8s  ─ 메인 이동
// ═══════════════════════════════════════════════════

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;

  // 한글 두 글자
  late AnimationController _gyoController;       // "교"
  late AnimationController _rangController;      // "랑"
  late AnimationController _koreanFadeOut;       // 교랑 사라짐

  // 영문
  late AnimationController _englishController;   // "KYORANG"

  late Animation<double> _gyoFade;
  late Animation<Offset> _gyoSlide;
  late Animation<double> _rangFade;
  late Animation<Offset> _rangSlide;

  late Animation<double> _koreanOutFade;
  late Animation<Offset> _koreanOutSlide;

  late Animation<double> _englishFade;
  late Animation<double> _englishScale;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // "교" 등장
    _gyoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _gyoFade = CurvedAnimation(
      parent: _gyoController,
      curve: Curves.easeOut,
    );
    _gyoSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _gyoController,
      curve: Curves.easeOutCubic,
    ));

    // "랑" 등장
    _rangController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _rangFade = CurvedAnimation(
      parent: _rangController,
      curve: Curves.easeOut,
    );
    _rangSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _rangController,
      curve: Curves.easeOutCubic,
    ));

    // "교 랑" 사라짐
    _koreanFadeOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _koreanOutFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _koreanFadeOut,
        curve: Curves.easeIn,
      ),
    );
    _koreanOutSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.3),
    ).animate(CurvedAnimation(
      parent: _koreanFadeOut,
      curve: Curves.easeIn,
    ));

    // "KYORANG" 등장
    _englishController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _englishFade = CurvedAnimation(
      parent: _englishController,
      curve: Curves.easeOut,
    );
    _englishScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _englishController,
        curve: Curves.easeOutCubic,
      ),
    );

    _runAnimation();
    _navigate();
  }

  Future<void> _runAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _gyoController.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _rangController.forward();

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _koreanFadeOut.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _englishController.forward();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _gyoController.dispose();
    _rangController.dispose();
    _koreanFadeOut.dispose();
    _englishController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));

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
          // ✨ 그라데이션 배경
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

          // ✨ 떠다니는 파티클
          AnimatedBuilder(
            animation: _glowController,
            builder: (_, __) {
              return CustomPaint(
                size: Size.infinite,
                painter: _ParticlePainter(
                    animation: _glowController.value),
              );
            },
          ),

          // ✨ 중앙 글자 애니메이션
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _gyoController,
                _rangController,
                _koreanFadeOut,
                _englishController,
              ]),
              builder: (_, __) {
                final isKoreanGone = _koreanFadeOut.value > 0.95;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // ─── 한글 "교 랑" ───────────────────
                    if (!isKoreanGone)
                      Opacity(
                        opacity: _koreanOutFade.value,
                        child: SlideTransition(
                          position: _koreanOutSlide,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // "교"
                              FadeTransition(
                                opacity: _gyoFade,
                                child: SlideTransition(
                                  position: _gyoSlide,
                                  child: const _KoreanLetter('교'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // "랑"
                              FadeTransition(
                                opacity: _rangFade,
                                child: SlideTransition(
                                  position: _rangSlide,
                                  child: const _KoreanLetter('랑'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ─── 영문 "KYORANG" (Playfair Display) ─────
                    if (isKoreanGone || _englishController.value > 0)
                      FadeTransition(
                        opacity: _englishFade,
                        child: ScaleTransition(
                          scale: _englishScale,
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                AppTheme.primaryLight,
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'KYORANG',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 54,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                letterSpacing: 4,
                                height: 1.0,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // ✨ 하단 워터마크
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _englishFade,
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
                  const SizedBox(height: 10),
                  Text(
                    'kyorang.com',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.5),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                      fontStyle: FontStyle.italic,
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

// ═══════════════════════════════════════════════════
// 🇰🇷 한글 글자 — Noto Serif KR
// ═══════════════════════════════════════════════════

class _KoreanLetter extends StatelessWidget {
  final String letter;
  const _KoreanLetter(this.letter);

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: GoogleFonts.notoSerifKr(
        fontSize: 88,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.0,
        shadows: [
          Shadow(
            color: AppTheme.primary.withOpacity(0.6),
            blurRadius: 30,
            offset: const Offset(0, 0),
          ),
          Shadow(
            color: AppTheme.primaryLight.withOpacity(0.4),
            blurRadius: 50,
            offset: const Offset(0, 0),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 떠다니는 파티클
// ═══════════════════════════════════════════════════

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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

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
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => true;
}