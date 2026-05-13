import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/photo_viewer_screen.dart';

// ═══════════════════════════════════════════════════
// 🖼 ProfileGallerySection — 갤러리 그리드
// (PhotoViewerScreen은 별도 파일에서 import만 함)
// ═══════════════════════════════════════════════════

class ProfileGallerySection extends StatelessWidget {
  final List<Map<String, dynamic>> photos;
  final bool isOwner;
  final VoidCallback? onAddPhoto;
  final void Function(int index)? onDelete;
  final void Function(int index)? onVisibilityChange;
  final void Function(int index)? onSetAsAvatar;

  const ProfileGallerySection({
    super.key,
    required this.photos,
    this.isOwner = false,
    this.onAddPhoto,
    this.onDelete,
    this.onVisibilityChange,
    this.onSetAsAvatar,
  });

  void _openViewer(BuildContext context, int initialIndex) {
    final urls =
        photos.map((p) => p['photo_url'] as String).toList();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          imageUrls: urls,
          initialIndex: initialIndex,
          isOwner: isOwner,
          onDelete: onDelete,
          onVisibilityChange: onVisibilityChange,
          onSetAsAvatar: onSetAsAvatar,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty && !isOwner) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.22),
                      AppTheme.primary.withOpacity(0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.primary, size: 13),
              ),
              const SizedBox(width: 8),
              Text(
                isOwner ? '내 사진' : '사진',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (photos.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${photos.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.primaryLight,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Spacer(),
              if (isOwner && onAddPhoto != null)
                _AddPhotoButton(onTap: onAddPhoto!),
            ],
          ),
        ),
        if (photos.isEmpty && isOwner)
          _EmptyState(onTap: onAddPhoto)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: photos.length,
              itemBuilder: (_, i) {
                final photo = photos[i];
                final url = photo['photo_url'] as String;
                final visibility =
                    photo['visibility'] as String? ?? 'friends';
                return _PhotoTile(
                  url: url,
                  visibility: visibility,
                  showVisibilityBadge: isOwner,
                  onTap: () => _openViewer(context, i),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final String visibility;
  final bool showVisibilityBadge;
  final VoidCallback onTap;

  const _PhotoTile({
    required this.url,
    required this.visibility,
    required this.showVisibilityBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppTheme.bgCard,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppTheme.bgCard,
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  color: AppTheme.border,
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: AppTheme.textSub,
                    size: 24,
                  ),
                ),
              ),
            ),
            if (showVisibilityBadge)
              Positioned(
                top: 6,
                right: 6,
                child: _VisibilityBadge(visibility: visibility),
              ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  final String visibility;

  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (visibility) {
      case 'public':
        icon = Icons.public_rounded;
        color = const Color(0xFF06B6D4);
        break;
      case 'specific':
        icon = Icons.lock_person_rounded;
        color = const Color(0xFFFBBF24);
        break;
      case 'friends':
      default:
        icon = Icons.people_alt_rounded;
        color = AppTheme.primary;
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.85)],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 11),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPhotoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary,
                AppTheme.primary.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded,
                  color: Colors.white, size: 14),
              SizedBox(width: 3),
              Text('사진 추가',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onTap;

  const _EmptyState({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.10),
                  AppTheme.primary.withOpacity(0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primary.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.25),
                        AppTheme.primary.withOpacity(0.12),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '사진을 추가해보세요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '친구들에게 일상을 공유해보세요',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}