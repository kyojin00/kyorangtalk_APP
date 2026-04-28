import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? url;
  final String? name;
  final double size;

  const AvatarWidget({super.key, this.url, this.name, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final initial = (name ?? '?').substring(0, 1).toUpperCase();

    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size, height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallback(initial),
          errorWidget: (_, __, ___) => _fallback(initial),
        ),
      );
    }
    return _fallback(initial);
  }

  Widget _fallback(String initial) {
    return Container(
      width: size, height: size,
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