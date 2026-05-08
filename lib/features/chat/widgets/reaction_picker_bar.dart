import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/reaction_provider.dart';

// ═══════════════════════════════════════════════════
// 메시지 옵션 시트 상단의 퀵 리액션 바 (디스코드 스타일)
//
// 사용법: showMessageOptions의 시트 안에서 ListTile들 위에 배치
// ═══════════════════════════════════════════════════
class ReactionPickerBar extends StatelessWidget {
  final void Function(String emoji) onSelected;

  const ReactionPickerBar({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: kQuickReactions.map((emoji) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(emoji),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 6),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}