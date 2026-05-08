import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 🔍 풀스크린 다중 이미지 뷰어
// ═══════════════════════════════════════════════════
//
// 기능
// - PageView 좌우 스와이프
// - 페이지마다 InteractiveViewer (핀치 줌 + 더블탭 줌)
// - 상단 페이지 인디케이터 (3 / 10)
// - 다운로드 버튼 (현재 이미지만)
// - 단일 탭으로 UI 토글
//
// 사용법
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => MultiImageViewerScreen(
//       imageUrls: ['url1', 'url2', ...],
//       initialIndex: 0,
//       senderName: '홍길동',
//       time: '오후 2:34',
//     ),
//   ));
// ═══════════════════════════════════════════════════

class MultiImageViewerScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? senderName;
  final String? time;

  const MultiImageViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.senderName,
    this.time,
  });

  @override
  State<MultiImageViewerScreen> createState() =>
      _MultiImageViewerScreenState();
}

class _MultiImageViewerScreenState extends State<MultiImageViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _showUI = true;
  bool _downloading = false;

  // 페이지마다 변환 컨트롤러 (줌 상태)
  late List<TransformationController> _transformers;
  late List<AnimationController> _animControllers;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformers = List.generate(
      widget.imageUrls.length,
      (_) => TransformationController(),
    );
    _animControllers = List.generate(
      widget.imageUrls.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final t in _transformers) {
      t.dispose();
    }
    for (final c in _animControllers) {
      c.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDoubleTapDown(int index, TapDownDetails details) {
    final transformer = _transformers[index];
    final animController = _animControllers[index];
    final isZoomed = transformer.value.getMaxScaleOnAxis() > 1.0;

    Matrix4 target;
    if (isZoomed) {
      target = Matrix4.identity();
    } else {
      final size = MediaQuery.of(context).size;
      final x = -details.localPosition.dx * 1.5 + size.width / 4;
      final y = -details.localPosition.dy * 1.5 + size.height / 4;
      target = Matrix4.identity()
        ..translate(x, y)
        ..scale(2.5);
    }

    final animation = Matrix4Tween(
      begin: transformer.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: animController,
      curve: Curves.easeOut,
    ));

    animController.forward(from: 0);
    animation.addListener(() {
      transformer.value = animation.value;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: AppTheme.textMain),
        ),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _downloadCurrentImage() async {
    if (_downloading) return;
    setState(() => _downloading = true);

    try {
      final url = widget.imageUrls[_currentIndex];

      // ⭐ 권한 체크 (gal이 알아서 처리)
      // - Android 10+ (API 29+): 저장 권한 불필요 (Scoped Storage)
      // - Android 9 이하: WRITE_EXTERNAL_STORAGE
      // - iOS: NSPhotoLibraryAddUsageDescription
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) _showSnack('갤러리 저장 권한이 필요해요');
          return;
        }
      }

      // 임시 파일로 다운로드
      final tempDir = Directory.systemTemp;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final tempPath = '${tempDir.path}/kyorang_$ts.jpg';

      await Dio().download(url, tempPath);

      // 갤러리에 저장 (Kyorang 앨범 자동 생성)
      await Gal.putImage(tempPath, album: 'Kyorang');

      // 임시 파일 정리
      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (mounted) _showSnack('갤러리에 저장됐어요');
    } on GalException catch (e) {
      if (mounted) _showSnack('저장 실패: ${e.type.message}');
    } catch (e) {
      print('저장 실패: $e');
      if (mounted) _showSnack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.imageUrls.length > 1;
    final hintText = isMulti
        ? '좌우로 스와이프 · 두 번 탭 · 핀치로 확대/축소'
        : '두 번 탭 · 핀치로 확대/축소';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ─ 페이지뷰
          GestureDetector(
            onTap: () => setState(() => _showUI = !_showUI),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                // 다른 페이지 줌 리셋
                for (int j = 0; j < _transformers.length; j++) {
                  if (j != i) {
                    _transformers[j].value = Matrix4.identity();
                  }
                }
              },
              itemBuilder: (ctx, i) {
                return GestureDetector(
                  onDoubleTapDown: (details) =>
                      _onDoubleTapDown(i, details),
                  onDoubleTap: () {},
                  child: InteractiveViewer(
                    transformationController: _transformers[i],
                    minScale: 0.5,
                    maxScale: 5.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    child: Center(
                      child: Image.network(
                        widget.imageUrls[i],
                        fit: BoxFit.contain,
                        width: MediaQuery.of(context).size.width,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height:
                                MediaQuery.of(context).size.height,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes !=
                                        null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                                color: AppTheme.primary,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_outlined,
                                  color: AppTheme.textSub, size: 48),
                              const SizedBox(height: 8),
                              Text('이미지를 불러올 수 없어요',
                                  style: TextStyle(
                                      color: AppTheme.textSub,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ─ 상단 바 (뒤로가기 + 페이지 + 발신자 + 다운로드)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showUI,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xCC000000),
                        Colors.transparent,
                      ],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios,
                                color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          // 페이지 인디케이터 (다중일 때만)
                          if (isMulti)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${_currentIndex + 1} / ${widget.imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (widget.senderName != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.senderName!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.time != null)
                                    Text(
                                      widget.time!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          IconButton(
                            icon: _downloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.download_rounded,
                                    color: Colors.white,
                                  ),
                            onPressed: _downloading
                                ? null
                                : _downloadCurrentImage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ─ 하단 페이지 도트 인디케이터 (다중 + UI 표시 중)
          if (isMulti)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 36,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.imageUrls.length, (i) {
                    final active = i == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ),

          // ─ 하단 힌트
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                hintText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}