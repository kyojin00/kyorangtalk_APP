import 'dart:async';
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
// ⭐ v2 변경:
//  - 상하단 그라데이션 강화로 구분 명확화
//  - 다운로드 아이콘 → 점 3개 (more_vert) 메뉴
//  - BottomSheet 액션: 다운로드 / 상세 보기
//  - 상세 보기: 페이지별 이미지 정보 (크기, 용량, 형식, 출처, 페이지)
//  - file:// URL 지원 (백업 복원된 이미지 표시 + 갤러리 저장)
//
// 기능
// - PageView 좌우 스와이프
// - 페이지마다 InteractiveViewer (핀치 줌 + 더블탭 줌)
// - 상단 페이지 인디케이터 (3 / 10)
// - 단일 탭으로 UI 토글
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

  // ⭐ 페이지별 이미지 메타 캐시
  late List<_ImageInfo> _imageInfos;

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
    _imageInfos = List.generate(
      widget.imageUrls.length,
      (i) => _ImageInfo(
        url: widget.imageUrls[i],
        isLocalFile: _isLocalUrl(widget.imageUrls[i]),
      ),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    // 첫 페이지 메타 로드
    _loadImageInfo(_currentIndex);
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

  // ───────────────────────────────────────────────
  // file:// URL 처리
  // ───────────────────────────────────────────────
  bool _isLocalUrl(String url) =>
      url.startsWith('file://') ||
      (url.startsWith('/') && !url.startsWith('//'));

  String _localPathFromUrl(String url) =>
      url.startsWith('file://') ? url.replaceFirst('file://', '') : url;

  // ⭐ ImageProvider 생성 (if-else 로 타입 명시)
  ImageProvider _providerFor(String url, bool isLocal) {
    if (isLocal) {
      return FileImage(File(_localPathFromUrl(url)));
    }
    return NetworkImage(url);
  }

  // ───────────────────────────────────────────────
  // 이미지 메타 로드 (페이지별, lazy)
  // ───────────────────────────────────────────────
  Future<void> _loadImageInfo(int index) async {
    if (index < 0 || index >= _imageInfos.length) return;
    final info = _imageInfos[index];
    if (info.loaded) return;

    int? width;
    int? height;
    int? fileSize;

    // 이미지 크기 (width × height)
    try {
      final ImageProvider provider =
          _providerFor(info.url, info.isLocalFile);

      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (imgInfo, _) {
          if (!completer.isCompleted) completer.complete(imgInfo);
          stream.removeListener(listener);
        },
        onError: (e, __) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final imgInfo =
          await completer.future.timeout(const Duration(seconds: 10));
      width = imgInfo.image.width;
      height = imgInfo.image.height;
    } catch (_) {}

    // 파일 크기
    try {
      if (info.isLocalFile) {
        final file = File(_localPathFromUrl(info.url));
        if (await file.exists()) {
          fileSize = await file.length();
        }
      } else {
        final response = await Dio()
            .head(info.url)
            .timeout(const Duration(seconds: 10));
        final cl = response.headers.value('content-length');
        if (cl != null) fileSize = int.tryParse(cl);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _imageInfos[index] = info.copyWith(
        width: width,
        height: height,
        fileSize: fileSize,
        loaded: true,
      );
    });
  }

  // ───────────────────────────────────────────────
  // 페이지 변경
  // ───────────────────────────────────────────────
  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);

    // 다른 페이지 줌 리셋
    for (int j = 0; j < _transformers.length; j++) {
      if (j != i) {
        _transformers[j].value = Matrix4.identity();
      }
    }

    // 현재 페이지 메타 로드
    _loadImageInfo(i);
  }

  // ───────────────────────────────────────────────
  // 더블탭 줌
  // ───────────────────────────────────────────────
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

  // ───────────────────────────────────────────────
  // 다운로드 (file:// 도 지원)
  // ───────────────────────────────────────────────
  Future<void> _downloadCurrentImage() async {
    if (_downloading) return;
    setState(() => _downloading = true);

    try {
      final url = widget.imageUrls[_currentIndex];
      final isLocal = _isLocalUrl(url);

      // 권한 체크
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) _showSnack('갤러리 저장 권한이 필요해요');
          return;
        }
      }

      if (isLocal) {
        // ⭐ 로컬 파일이면 바로 갤러리에 저장
        final localPath = _localPathFromUrl(url);
        await Gal.putImage(localPath, album: 'Kyorang');
      } else {
        // 서버면 다운로드 후 갤러리에 저장
        final tempDir = Directory.systemTemp;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final tempPath = '${tempDir.path}/kyorang_$ts.jpg';

        await Dio().download(url, tempPath);
        await Gal.putImage(tempPath, album: 'Kyorang');

        try {
          await File(tempPath).delete();
        } catch (_) {}
      }

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

  // ───────────────────────────────────────────────
  // 액션 시트 (점 3개)
  // ───────────────────────────────────────────────
  void _showActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            _ActionRow(
              icon: Icons.download_rounded,
              label: '다운로드',
              onTap: () {
                Navigator.pop(context);
                _downloadCurrentImage();
              },
            ),
            _ActionRow(
              icon: Icons.info_outline_rounded,
              label: '상세 보기',
              onTap: () {
                Navigator.pop(context);
                _showDetails();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 상세 보기 시트
  // ───────────────────────────────────────────────
  void _showDetails() {
    final info = _imageInfos[_currentIndex];
    final isMulti = widget.imageUrls.length > 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 핸들
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 타이틀 + 페이지 인디케이터
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '이미지 정보',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (isMulti)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.imageUrls.length}',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 정보 카드
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    if (widget.senderName != null)
                      _DetailRow(
                        label: '보낸 사람',
                        value: widget.senderName!,
                      ),
                    if (widget.time != null)
                      _DetailRow(
                        label: '받은 시간',
                        value: widget.time!,
                      ),
                    _DetailRow(
                      label: '파일 형식',
                      value: _getFileType(info.url),
                    ),
                    _DetailRow(
                      label: '이미지 크기',
                      value: (info.width != null && info.height != null)
                          ? '${info.width} × ${info.height}'
                          : '확인 중...',
                    ),
                    _DetailRow(
                      label: '파일 크기',
                      value: info.fileSize != null
                          ? _fmtBytes(info.fileSize!)
                          : '확인 중...',
                    ),
                    _DetailRow(
                      label: '출처',
                      value: info.isLocalFile ? '백업에서 복원됨' : '서버',
                      isLast: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 닫기
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.bg,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    '닫기',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 유틸
  // ───────────────────────────────────────────────
  String _getFileType(String url) {
    final lower = url.toLowerCase();
    final clean = lower.split('?').first.split('#').first;
    if (clean.endsWith('.jpg') || clean.endsWith('.jpeg')) return 'JPEG';
    if (clean.endsWith('.png')) return 'PNG';
    if (clean.endsWith('.gif')) return 'GIF';
    if (clean.endsWith('.webp')) return 'WEBP';
    if (clean.endsWith('.bmp')) return 'BMP';
    if (clean.endsWith('.heic')) return 'HEIC';
    return '이미지';
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  // ───────────────────────────────────────────────
  // 이미지 렌더링 (file:// vs https 분기)
  // ───────────────────────────────────────────────
  Widget _buildImage(int i) {
    final url = widget.imageUrls[i];
    final isLocal = _isLocalUrl(url);
    final size = MediaQuery.of(context).size;

    if (isLocal) {
      return Image.file(
        File(_localPathFromUrl(url)),
        fit: BoxFit.contain,
        width: size.width,
        errorBuilder: _errorBuilder,
      );
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      width: size.width,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
              color: AppTheme.primary,
              strokeWidth: 2,
            ),
          ),
        );
      },
      errorBuilder: _errorBuilder,
    );
  }

  Widget _errorBuilder(_, __, ___) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined,
                color: AppTheme.textSub, size: 48),
            const SizedBox(height: 8),
            Text('이미지를 불러올 수 없어요',
                style:
                    TextStyle(color: AppTheme.textSub, fontSize: 13)),
          ],
        ),
      );

  // ───────────────────────────────────────────────
  // build
  // ───────────────────────────────────────────────
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
              onPageChanged: _onPageChanged,
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
                    child: Center(child: _buildImage(i)),
                  ),
                );
              },
            ),
          ),

          // ─ 상단 바 (강화된 그라데이션)
          _buildTopBar(isMulti),

          // ─ 하단 도트 인디케이터
          if (isMulti) _buildDotsIndicator(),

          // ─ 하단 바 (그라데이션 + 힌트)
          _buildBottomBar(hintText),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 상단 바
  // ───────────────────────────────────────────────
  Widget _buildTopBar(bool isMulti) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showUI ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_showUI,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.85),
                  Colors.black.withOpacity(0.6),
                  Colors.black.withOpacity(0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 0.85, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),

                    // 가운데: 다중이면 페이지, 단일이면 발신자
                    Expanded(
                      child: Center(
                        child: isMulti
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${_currentIndex + 1} / ${widget.imageUrls.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : (widget.senderName != null
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.senderName!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w700,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                      if (widget.time != null)
                                        Text(
                                          widget.time!,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black54,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  )
                                : const SizedBox.shrink()),
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
                              Icons.more_vert_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                      onPressed: _downloading ? null : _showActionSheet,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 하단 도트 인디케이터 (다중일 때만)
  // ───────────────────────────────────────────────
  Widget _buildDotsIndicator() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 52,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showUI ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
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
    );
  }

  // ───────────────────────────────────────────────
  // 하단 바 (그라데이션 + 힌트)
  // ───────────────────────────────────────────────
  Widget _buildBottomBar(String hintText) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showUI ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.75),
                  Colors.black.withOpacity(0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                    top: 32, bottom: 18, left: 16, right: 16),
                child: Text(
                  hintText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 이미지 메타 정보
// ═══════════════════════════════════════════════════
class _ImageInfo {
  final String url;
  final bool isLocalFile;
  final int? width;
  final int? height;
  final int? fileSize;
  final bool loaded;

  _ImageInfo({
    required this.url,
    required this.isLocalFile,
    this.width,
    this.height,
    this.fileSize,
    this.loaded = false,
  });

  _ImageInfo copyWith({
    int? width,
    int? height,
    int? fileSize,
    bool? loaded,
  }) {
    return _ImageInfo(
      url: url,
      isLocalFile: isLocalFile,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      loaded: loaded ?? this.loaded,
    );
  }
}

// ═══════════════════════════════════════════════════
// 액션 시트 아이템
// ═══════════════════════════════════════════════════
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? AppTheme.textMain,
              size: 22,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: labelColor ?? AppTheme.textMain,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 상세 보기 행
// ═══════════════════════════════════════════════════
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.border.withOpacity(0.5),
                  width: 1,
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}