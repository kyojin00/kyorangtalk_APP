import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../features/call/providers/call_provider.dart';
import '../../features/call/providers/ongoing_call_provider.dart';
import '../../main.dart';

// ═══════════════════════════════════════════════════
// 🌟 SplashScreen
//
// ⭐ 속도 최적화:
//   - 기존: 2.8초 강제 대기 + 통화 없을 때도 3초 폴링 = ~6초+
//   - 변경: 800ms 최소 표시 + 통화 없으면 즉시 통과 = ~800ms
//   - 인증 체크는 라우터 redirect에 위임 (중복 제거)
//
// 디자인 vs 속도 trade-off:
//   _kMinDisplayMs를 조정해서 균형 맞춤
//   - 0    = 카톡식 (네이티브 스플래시 끝나자마자 친구 화면)
//   - 400  = 한글 글자만 살짝 보이고 사라짐
//   - 800  = 한글 → 영어 전환 시작 (기본값)
//   - 1500 = 한글 → 영어 전환 완료 (전체 애니메이션)
// ═══════════════════════════════════════════════════

const int _kMinDisplayMs = 800;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;

  late AnimationController _gyoController;
  late AnimationController _rangController;
  late AnimationController _koreanFadeOut;
  late AnimationController _englishController;

  late Animation<double> _gyoFade;
  late Animation<Offset> _gyoSlide;
  late Animation<double> _rangFade;
  late Animation<Offset> _rangSlide;

  late Animation<double> _koreanOutFade;
  late Animation<Offset> _koreanOutSlide;

  late Animation<double> _englishFade;
  late Animation<double> _englishScale;

  bool _callEverActive = false;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

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
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _gyoController.forward();

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _rangController.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _koreanFadeOut.forward();

    await Future.delayed(const Duration(milliseconds: 300));
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

  // ⭐ 변경: 강제 2.8초 대기 제거, 라우터 redirect에 인증 체크 위임
  Future<void> _navigate() async {
    // 최소 표시 시간만 유지 (디자인 vs 속도 균형)
    await Future.delayed(const Duration(milliseconds: _kMinDisplayMs));
    if (!mounted) return;

    // 통화 흐름 대기 (통화 없으면 즉시 통과 ← 핵심)
    await _waitForCallFlowToFinish();
    if (!mounted) return;

    // pending 알림 처리 (있을 때만 빠르게)
    try {
      await handlePendingNotification();
    } catch (e) {
      print('pending notification 처리 오류: $e');
    }
    if (!mounted) return;

    // 라우터 redirect가 알아서 처리:
    //   - 세션 없음 → /login
    //   - 프로필 없음 → /onboarding
    //   - 정상 → /main
    final session = Supabase.instance.client.auth.currentSession;
    context.go(session != null ? '/main' : '/login');
  }

  /// 통화 흐름이 끝날 때까지 대기
  /// ⭐ 변경: 통화 흔적이 전혀 없으면 즉시 종료 (3초 폴링 헛돎 제거)
  Future<void> _waitForCallFlowToFinish() async {
    // ⭐ 빠른 종료: 통화 흔적이 전혀 없으면 즉시 통과
    //   대부분의 일반적인 앱 시작 경우 여기서 즉시 return
    final incoming = ref.read(incomingCallProvider).valueOrNull;
    final ongoing = ref.read(myOngoingCallProvider).valueOrNull;
    if (incoming == null && ongoing == null && !_callEverActive) {
      return;
    }

    // 1) ringing 종료 대기
    while (mounted) {
      final cur = ref.read(incomingCallProvider).valueOrNull;
      if (cur == null) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;

    // 2) ActiveCallScreen 등장 감지 (3초 → 500ms로 축소)
    //   여기까지 왔으면 통화 흔적이 있는 상태이므로 짧게 폴링
    bool wasEverOnCallScreen = false;
    final start = DateTime.now();
    while (mounted &&
        DateTime.now().difference(start).inMilliseconds < 500) {
      if (ref.read(isOnActiveCallScreenProvider)) {
        wasEverOnCallScreen = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted || !wasEverOnCallScreen) return;

    // 3) ActiveCallScreen dispose 대기
    while (mounted) {
      if (!ref.read(isOnActiveCallScreenProvider)) {
        await Future.delayed(const Duration(milliseconds: 200));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(incomingCallProvider).valueOrNull;
    final ongoing = ref.watch(myOngoingCallProvider).valueOrNull;
    final hasCall = incoming != null || ongoing != null;

    if (hasCall) {
      _callEverActive = true;
    }

    if (hasCall || _callEverActive) {
      return const Scaffold(
        backgroundColor: Color(0xFF080810),
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
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
                    if (!isKoreanGone)
                      Opacity(
                        opacity: _koreanOutFade.value,
                        child: SlideTransition(
                          position: _koreanOutSlide,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: _gyoFade,
                                child: SlideTransition(
                                  position: _gyoSlide,
                                  child: const _KoreanLetter('교'),
                                ),
                              ),
                              const SizedBox(width: 16),
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