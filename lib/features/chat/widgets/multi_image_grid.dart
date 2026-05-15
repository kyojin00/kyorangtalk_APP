import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/multi_image_viewer_screen.dart';

// ═══════════════════════════════════════════════════
// 🖼️ 다중 이미지 그리드 말풍선
// ═══════════════════════════════════════════════════
//
// 메시지 안에서 여러 장 이미지를 카카오톡 스타일로 표시
//   1장 : 큰 정사각 이미지
//   2장 : 좌우 분할
//   3장 : 큰 이미지(좌) + 작은 2장(우 상하)
//   4장 : 2x2 그리드
//   5장+: 2x2 그리드 + 마지막 칸에 "+N" 오버레이
//
// ⭐ 캐싱: cached_network_image 적용
//   - 같은 URL은 디스크 + 메모리 캐시
//   - 스크롤 시 재요청 없음
//   - 첫 로드 후 인스턴트
// ═══════════════════════════════════════════════════

class MultiImageGrid extends StatelessWidget {
  final List<String> imageUrls;
  final bool isMe;
  final String timeStr;
  final String? senderName;

  const MultiImageGrid({
    super.key,
    required this.imageUrls,
    required this.isMe,
    required this.timeStr,
    this.senderName,
  });

  /// 말풍선 한 변의 크기 (정사각)
  static const double _size = 240.0;

  /// 이미지 사이 간격
  static const double _gap = 2.0;

  void _open(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiImageViewerScreen(
          imageUrls: imageUrls,
          initialIndex: index,
          senderName: isMe ? '나' : senderName,
          time: timeStr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    final count = imageUrls.length;
    Widget content;

    if (count == 1) {
      content = _buildSingle(context);
    } else if (count == 2) {
      content = _build2(context);
    } else if (count == 3) {
      content = _build3(context);
    } else {
      content = _build4Plus(context);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: _size,
        height: _size,
        child: content,
      ),
    );
  }

  // ─── 1장
  Widget _buildSingle(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context, 0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ImageTile(url: imageUrls[0]),
          // 단일에는 줌 아이콘 표시 (단일 모드 일관성)
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.zoom_in,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2장 (좌우 분할)
  Widget _build2(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _open(context, 0),
            child: _ImageTile(url: imageUrls[0]),
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: GestureDetector(
            onTap: () => _open(context, 1),
            child: _ImageTile(url: imageUrls[1]),
          ),
        ),
      ],
    );
  }

  // ─── 3장 (큰 좌측 + 작은 2장 우측)
  Widget _build3(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => _open(context, 0),
            child: _ImageTile(url: imageUrls[0]),
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 1),
                  child: _ImageTile(url: imageUrls[1]),
                ),
              ),
              const SizedBox(height: _gap),
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 2),
                  child: _ImageTile(url: imageUrls[2]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 4장 이상 (2x2 그리드, 5장+는 마지막 칸에 +N)
  Widget _build4Plus(BuildContext context) {
    final extra = imageUrls.length - 4;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 0),
                  child: _ImageTile(url: imageUrls[0]),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 1),
                  child: _ImageTile(url: imageUrls[1]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _gap),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 2),
                  child: _ImageTile(url: imageUrls[2]),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 3),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ImageTile(url: imageUrls[3]),
                      if (extra > 0)
                        Container(
                          color: Colors.black.withOpacity(0.55),
                          alignment: Alignment.center,
                          child: Text(
                            '+$extra',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 개별 이미지 타일 (로딩/에러 상태 포함)
// ⭐ CachedNetworkImage로 자동 캐싱
// ═══════════════════════════════════════════════════
class _ImageTile extends StatelessWidget {
  final String url;
  const _ImageTile({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // 메모리 캐시 크기 제한 (썸네일이므로 작게)
      memCacheWidth: 480,
      // 페이드인 부드럽게
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (_, __) => Container(
        color: AppTheme.border,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: AppTheme.border,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: AppTheme.textSub,
          size: 24,
        ),
      ),
    );
  }
}