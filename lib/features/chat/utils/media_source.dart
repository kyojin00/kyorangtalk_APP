// lib/features/chat/utils/media_source.dart
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════
// 미디어 소스 헬퍼
//
// 위치: lib/features/chat/utils/media_source.dart
//
// 백업 복원 시 미디어 URL이 file:// (또는 절대경로)로 바뀌는데,
// CachedNetworkImage는 네트워크 전용이라 깨진다.
// 로컬/원격을 자동 판별해서 알맞은 위젯·Provider를 돌려준다.
// ═══════════════════════════════════════════════

/// 로컬 파일 경로(file:// 스킴 또는 절대경로)인지 판별
bool isLocalMediaPath(String url) =>
    url.startsWith('file://') || url.startsWith('/');

/// file:// 스킴을 제거해서 실제 파일시스템 경로 반환
String stripFileScheme(String url) =>
    url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;

/// 로컬/원격 자동 분기 이미지 위젯
Widget mediaImage({
  required String url,
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Widget? placeholder,
  Widget? errorWidget,
}) {
  final fallback = errorWidget ?? const _MediaError();

  if (isLocalMediaPath(url)) {
    final file = File(stripFileScheme(url));
    if (!file.existsSync()) return fallback;
    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  return CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    width: width,
    height: height,
    placeholder:
        placeholder != null ? (_, __) => placeholder : null,
    errorWidget: (_, __, ___) => fallback,
  );
}

/// 로컬/원격 자동 분기 ImageProvider
/// (PhotoView 등 ImageProvider가 필요한 곳에서 사용)
ImageProvider mediaImageProvider(String url) {
  if (isLocalMediaPath(url)) {
    return FileImage(File(stripFileScheme(url)));
  }
  return CachedNetworkImageProvider(url);
}

class _MediaError extends StatelessWidget {
  const _MediaError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgCard,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: AppTheme.textMuted,
        size: 32,
      ),
    );
  }
}