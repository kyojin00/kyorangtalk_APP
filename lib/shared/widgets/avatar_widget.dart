import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? url;
  final String? name;
  final double size;

  const AvatarWidget({super.key, this.url, this.name, this.size = 46});

  // ⭐ 안전한 이니셜 추출
  // - null / 빈 문자열 / 공백만 있는 경우 '?' 반환
  // - 이모지나 한글 첫 글자도 안전하게 추출 (characters 사용)
  String _safeInitial() {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return '?';
    try {
      // characters로 grapheme cluster 단위 추출 (이모지 안전)
      final first = n.characters.first;
      return first.toUpperCase();
    } catch (_) {
      return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _safeInitial();

    if (url != null && url!.isNotEmpty) {
      // ⭐ 디스플레이 픽셀 밀도 고려한 메모리 캐시 사이즈
      // (16dp 아이콘에 4096x4096 들고 있는 일 방지)
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
      final cacheSize = (size * dpr).round();

      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // ⭐ 메모리 캐시 크기 제한 — RAM 크게 절약
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          // ⭐ 페이드인 부드럽게
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: const Duration(milliseconds: 80),
          placeholder: (_, __) => _fallback(initial),
          errorWidget: (_, __, ___) => _fallback(initial),
        ),
      );
    }
    return _fallback(initial);
  }

  Widget _fallback(String initial) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, Color(0xFF4C1D95)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}