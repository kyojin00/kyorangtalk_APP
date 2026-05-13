import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 📸 PhotoViewerScreen — 풀스크린 뷰어
// 수정: SizedBox.expand로 화면 꽉 차게 (BoxFit.contain 비율 유지)
// ═══════════════════════════════════════════════════

class PhotoViewerScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final bool isOwner;
  final void Function(int index)? onDelete;
  final void Function(int index)? onVisibilityChange;
  final void Function(int index)? onSetAsAvatar;

  const PhotoViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.isOwner = false,
    this.onDelete,
    this.onVisibilityChange,
    this.onSetAsAvatar,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => _ZoomableImage(
              url: widget.imageUrls[i],
              onTap: () => Navigator.pop(context),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _GlassIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (widget.imageUrls.length > 1)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.imageUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (widget.isOwner)
                    _GlassIconButton(
                      icon: Icons.more_horiz_rounded,
                      onTap: _showOptionsMenu,
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
          ),
          if (widget.imageUrls.length > 1 &&
              widget.imageUrls.length <= 10)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children:
                        List.generate(widget.imageUrls.length, (i) {
                      final active = i == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 3),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (widget.onSetAsAvatar != null)
                _MenuRow(
                  icon: Icons.account_circle_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  label: '프로필 사진으로 설정',
                  labelColor: AppTheme.textMain,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onSetAsAvatar!(_currentIndex);
                  },
                ),
              if (widget.onVisibilityChange != null)
                _MenuRow(
                  icon: Icons.visibility_outlined,
                  iconColor: AppTheme.primary,
                  label: '공개 범위 설정',
                  labelColor: AppTheme.textMain,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onVisibilityChange!(_currentIndex);
                  },
                ),
              if (widget.onDelete != null)
                _MenuRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: '사진 삭제',
                  labelColor: const Color(0xFFEF4444),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await _confirmDelete(context);
                    if (confirm == true) {
                      widget.onDelete!(_currentIndex);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext ctx) {
    return showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('사진 삭제',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: -0.3)),
        content: Text('이 사진을 삭제할까요?',
            style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 14,
                letterSpacing: -0.2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('취소',
                style: TextStyle(
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('삭제',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 줌 가능한 이미지 — ⭐ SizedBox.expand로 화면 꽉 채움
// ═══════════════════════════════════════════════════
class _ZoomableImage extends StatefulWidget {
  final String url;
  final VoidCallback onTap;

  const _ZoomableImage({required this.url, required this.onTap});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller =
      TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _anim;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animController.addListener(() {
      if (_anim != null) {
        _controller.value = _anim!.value;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;

    final Matrix4 endMatrix;
    if (_controller.value != Matrix4.identity()) {
      endMatrix = Matrix4.identity();
    } else {
      endMatrix = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }

    _anim = Matrix4Tween(
      begin: _controller.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1.0,
        maxScale: 4.0,
        // ⭐ SizedBox.expand로 화면 전체 차지 + BoxFit.contain으로 비율 유지
        child: SizedBox.expand(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_rounded,
                      color: Colors.white.withOpacity(0.4),
                      size: 48),
                  const SizedBox(height: 12),
                  Text('사진을 불러올 수 없어요',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      iconColor.withOpacity(0.25),
                      iconColor.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}