import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../services/link_preview_service.dart';

// ═══════════════════════════════════════════════════
// 🔗 OG 미리보기 카드
// ═══════════════════════════════════════════════════
//
// 사용:
//   LinkPreviewCard(
//     url: 'https://example.com/article',
//     isMe: true,
//   )
//
// 동작:
//   - 첫 빌드 시 LinkPreviewService.fetch(url) 호출
//   - 로딩 중엔 스켈레톤
//   - 결과 받으면 이미지 + 제목 + 설명 + 도메인 카드
//   - 카드 탭하면 외부 브라우저 (또는 우리 앱 딥링크면 그쪽으로)
// ═══════════════════════════════════════════════════

class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isMe;

  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.isMe,
  });

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  late final Future<LinkPreview?> _future;

  @override
  void initState() {
    super.initState();
    print('🔗 [Card] initState 호출됨 url=${widget.url}');
    _future = LinkPreviewService.fetch(widget.url);
  }

  Future<void> _open() async {
    try {
      await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkPreview?>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _Skeleton(isMe: widget.isMe);
        }
        final preview = snap.data;
        if (preview == null) return const SizedBox.shrink();
        return _Card(preview: preview, isMe: widget.isMe, onTap: _open);
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// 실제 카드
// ═══════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final LinkPreview preview;
  final bool isMe;
  final VoidCallback onTap;

  const _Card({
    required this.preview,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = preview.image != null && preview.image!.isNotEmpty;
    final maxWidth = MediaQuery.of(context).size.width * 0.7;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              AspectRatio(
                aspectRatio: 1.91, // OG 권장 비율
                child: Image.network(
                  preview.image!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.border,
                    alignment: Alignment.center,
                    child: Icon(Icons.broken_image,
                        color: AppTheme.textMuted, size: 32),
                  ),
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: AppTheme.border,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview.title != null && preview.title!.isNotEmpty)
                    Text(
                      preview.title!,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (preview.description != null &&
                      preview.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.description!,
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.link,
                          size: 11, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          preview.siteName?.isNotEmpty == true
                              ? preview.siteName!
                              : preview.hostName,
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 로딩 스켈레톤
// ═══════════════════════════════════════════════════

class _Skeleton extends StatelessWidget {
  final bool isMe;
  const _Skeleton({required this.isMe});

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.link, color: AppTheme.textMuted, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    height: 10,
                    width: double.infinity,
                    color: AppTheme.border),
                const SizedBox(height: 6),
                Container(
                    height: 8, width: 100, color: AppTheme.border),
              ],
            ),
          ),
        ],
      ),
    );
  }
}