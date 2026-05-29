import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 🖼️ ImageViewerScreen
//
// ⭐ v2 변경:
//  - 상하단 그라데이션 강화로 구분 명확화
//  - 다운로드 아이콘 → 점 3개 (more_vert) 메뉴 버튼
//  - BottomSheet 액션: 다운로드 / 상세 보기
//  - 상세 보기: 이미지 정보 (크기, 용량, 형식, 출처)
//  - file:// URL 지원 (백업 복원된 이미지 표시 + 갤러리 저장)
// ═══════════════════════════════════════════════════
class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? senderName;
  final String? time;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.senderName,
    this.time,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _showUI = true;
  bool _downloading = false;

  // ⭐ 이미지 메타 (상세 보기용)
  int? _imageWidth;
  int? _imageHeight;
  int? _fileSizeBytes;
  bool _isLocalFile = false;

  static const _platform =
      MethodChannel('com.kyorang.kyorang_talk/media');

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    // file:// URL 판별
    _isLocalFile = widget.imageUrl.startsWith('file://') ||
        (widget.imageUrl.startsWith('/') &&
            !widget.imageUrl.startsWith('//'));

    _loadImageInfo();
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String get _localPath {
    if (widget.imageUrl.startsWith('file://')) {
      return widget.imageUrl.replaceFirst('file://', '');
    }
    return widget.imageUrl;
  }

  // ⭐ ImageProvider 생성 (if-else로 타입 명시)
  ImageProvider _provider() {
    if (_isLocalFile) {
      return FileImage(File(_localPath));
    }
    return NetworkImage(widget.imageUrl);
  }

  // ───────────────────────────────────────────────
  // 이미지 메타 로드
  // ───────────────────────────────────────────────
  Future<void> _loadImageInfo() async {
    // 이미지 크기
    try {
      final ImageProvider provider = _provider();

      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (e, __) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final info = await completer.future
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _imageWidth = info.image.width;
        _imageHeight = info.image.height;
      });
    } catch (_) {}

    // 파일 크기
    try {
      if (_isLocalFile) {
        final file = File(_localPath);
        if (await file.exists()) {
          final size = await file.length();
          if (!mounted) return;
          setState(() => _fileSizeBytes = size);
        }
      } else {
        final response = await Dio()
            .head(widget.imageUrl)
            .timeout(const Duration(seconds: 10));
        final contentLength =
            response.headers.value('content-length');
        if (contentLength != null) {
          final size = int.tryParse(contentLength);
          if (size != null) {
            if (!mounted) return;
            setState(() => _fileSizeBytes = size);
          }
        }
      }
    } catch (_) {}
  }

  // ───────────────────────────────────────────────
  // 더블탭 줌
  // ───────────────────────────────────────────────
  void _onDoubleTapDown(TapDownDetails details) {
    final isZoomed =
        _transformController.value.getMaxScaleOnAxis() > 1.0;

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

    _animation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _animController.forward(from: 0);
    _animation!.addListener(() {
      _transformController.value = _animation!.value;
    });
  }

  Future<void> _scanMediaFile(String path) async {
    try {
      await _platform.invokeMethod('scanFile', {'path': path});
    } catch (e) {
      print('갤러리 스캔 실패 (파일은 저장됨): $e');
    }
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
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ───────────────────────────────────────────────
  // 다운로드 (file:// 도 지원)
  // ───────────────────────────────────────────────
  Future<void> _downloadImage() async {
    setState(() => _downloading = true);

    try {
      PermissionStatus status = await Permission.photos.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }

      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('저장소 권한이 필요해요'),
              backgroundColor: AppTheme.bgCard,
              action: SnackBarAction(
                label: '설정',
                textColor: AppTheme.primary,
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return;
      }

      final isImage = widget.imageUrl
          .toLowerCase()
          .contains(RegExp(r'\.(jpg|jpeg|png|gif|webp)'));

      Directory dir;
      if (isImage) {
        dir = Directory('/storage/emulated/0/Pictures/교랑톡');
      } else {
        dir = Directory('/storage/emulated/0/Download');
      }

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileName =
          'kyorangtalk_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = '${dir.path}/$fileName';

      if (_isLocalFile) {
        // ⭐ 로컬 파일이면 복사
        final src = File(_localPath);
        if (await src.exists()) {
          await src.copy(savePath);
        } else {
          throw Exception('원본 파일을 찾을 수 없어요');
        }
      } else {
        // 서버면 다운로드
        await Dio().download(widget.imageUrl, savePath);
      }

      await _scanMediaFile(savePath);

      await Future.delayed(const Duration(milliseconds: 200));
      _showSnack(isImage ? '갤러리에 저장됐어요' : '다운로드 폴더에 저장됐어요');
    } catch (e) {
      print('저장 실패: $e');
      _showSnack('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ───────────────────────────────────────────────
  // 액션 시트 (점 3개 메뉴)
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
                _downloadImage();
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

              // 타이틀
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
                      value: _getFileType(),
                    ),
                    _DetailRow(
                      label: '이미지 크기',
                      value: (_imageWidth != null &&
                              _imageHeight != null)
                          ? '${_imageWidth} × ${_imageHeight}'
                          : '확인 중...',
                    ),
                    _DetailRow(
                      label: '파일 크기',
                      value: _fileSizeBytes != null
                          ? _fmtBytes(_fileSizeBytes!)
                          : '확인 중...',
                    ),
                    _DetailRow(
                      label: '출처',
                      value: _isLocalFile
                          ? '백업에서 복원됨'
                          : '서버',
                      isLast: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 닫기 버튼
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
  String _getFileType() {
    final url = widget.imageUrl.toLowerCase();
    final clean = url.split('?').first.split('#').first;
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
  Widget _buildImage() {
    final size = MediaQuery.of(context).size;

    if (_isLocalFile) {
      return Image.file(
        File(_localPath),
        fit: BoxFit.contain,
        width: size.width,
        errorBuilder: _errorBuilder,
      );
    }

    return Image.network(
      widget.imageUrl,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            Center(
              child: GestureDetector(
                onDoubleTapDown: _onDoubleTapDown,
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.5,
                  maxScale: 5.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: _buildImage(),
                ),
              ),
            ),

            _buildTopBar(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
                    Expanded(
                      child: widget.senderName != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.senderName!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
                          : const SizedBox.shrink(),
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

  Widget _buildBottomBar() {
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
                  '두 번 탭 · 핀치로 확대/축소',
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