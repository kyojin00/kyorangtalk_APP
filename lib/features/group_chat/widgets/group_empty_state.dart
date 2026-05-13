import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 💬 GroupEmptyState — 빈 채팅 상태
//
// - 큰 이모지 + 그라데이션 원
// - 그룹 이름 강조
// - 안내 메시지
// ═══════════════════════════════════════════════════

class GroupEmptyState extends StatelessWidget {
  final String roomName;

  const GroupEmptyState({super.key, required this.roomName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 이모지 + 그라데이션 원
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.2),
                  AppTheme.primary.withOpacity(0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('💬', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 20),

          // 그룹 이름
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                AppTheme.primaryLight,
                AppTheme.primary,
              ],
            ).createShader(bounds),
            child: Text(
              roomName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),

          // 안내
          Text(
            '아직 메시지가 없어요',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '첫 메시지를 보내볼까요?',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12.5,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}