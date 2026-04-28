import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';

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
  State<ImageViewerScreen> createState() =>
      _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _showUI      = true;
  bool _downloading = false;

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
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final isZoomed =
        _transformController.value.getMaxScaleOnAxis() > 1.0;

    Matrix4 target;
    if (isZoomed) {
      target = Matrix4.identity();
    } else {
      final size = MediaQuery.of(context).size;
      final x =
          -details.localPosition.dx * 1.5 + size.width / 4;
      final y =
          -details.localPosition.dy * 1.5 + size.height / 4;
      target = Matrix4.identity()
        ..translate(x, y)
        ..scale(2.5);
    }

    _animation = Matrix4Tween(
      begin: _transformController.value,
      end:   target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve:  Curves.easeOut,
    ));

    _animController.forward(from: 0);
    _animation!.addListener(() {
      _transformController.value = _animation!.value;
    });
  }

  Future<void> _scanMediaFile(String path) async {
    try {
      await _platform.invokeMethod('scanFile', {'path': path});
      print('갤러리 스캔 완료');
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

  Future<void> _downloadImage() async {
    setState(() => _downloading = true);

    try {
      PermissionStatus status =
          await Permission.photos.request();
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

      print('저장 경로: $savePath');

      await Dio().download(widget.imageUrl, savePath);
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
                onDoubleTap:     () {},
                child: InteractiveViewer(
                  transformationController:
                      _transformController,
                  minScale:     0.5,
                  maxScale:     5.0,
                  panEnabled:   true,
                  scaleEnabled: true,
                  child: Image.network(
                    widget.imageUrl,
                    fit:   BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        width: MediaQuery.of(context)
                            .size
                            .width,
                        height: MediaQuery.of(context)
                            .size
                            .height,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress
                                        .expectedTotalBytes !=
                                    null
                                ? progress
                                        .cumulativeBytesLoaded /
                                    progress
                                        .expectedTotalBytes!
                                : null,
                            color:       AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) =>
                        Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                              Icons.broken_image_outlined,
                              color: AppTheme.textSub,
                              size: 48),
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
            ),

            AnimatedOpacity(
              opacity:  _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showUI,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
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
                            icon: const Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                                size:  20),
                            onPressed: () =>
                                Navigator.pop(context),
                          ),
                          const Spacer(),
                          if (widget.senderName != null)
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.senderName!,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight:
                                          FontWeight.w600),
                                ),
                                if (widget.time != null)
                                  Text(
                                    widget.time!,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11),
                                  ),
                              ],
                            ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: _downloading
                                ? const SizedBox(
                                    width:  20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color:
                                                Colors.white))
                                : const Icon(
                                    Icons.download_rounded,
                                    color: Colors.white),
                            onPressed: _downloading
                                ? null
                                : _downloadImage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              bottom:
                  MediaQuery.of(context).padding.bottom + 16,
              left:  0,
              right: 0,
              child: AnimatedOpacity(
                opacity:  _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Text(
                  '두 번 탭 · 핀치로 확대/축소',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}