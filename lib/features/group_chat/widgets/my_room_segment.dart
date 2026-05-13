import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../enums/group_chat_enums.dart';

// ═══════════════════════════════════════════════════
// 내 채팅방 세그먼트 (전체 / 그룹 / 오픈)
//
// 위치: lib/features/group_chat/widgets/my_room_segment.dart
// ═══════════════════════════════════════════════════

class MyRoomSegment extends StatelessWidget {
  final MyRoomFilter selected;
  final int totalCount;
  final int groupCount;
  final int openCount;
  final ValueChanged<MyRoomFilter> onChanged;

  const MyRoomSegment({
    super.key,
    required this.selected,
    required this.totalCount,
    required this.groupCount,
    required this.openCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _SegItem(
            label: '전체',
            count: totalCount,
            selected: selected == MyRoomFilter.all,
            onTap: () => onChanged(MyRoomFilter.all),
          ),
          _SegItem(
            label: '그룹',
            count: groupCount,
            selected: selected == MyRoomFilter.group,
            onTap: () => onChanged(MyRoomFilter.group),
          ),
          _SegItem(
            label: '오픈',
            count: openCount,
            selected: selected == MyRoomFilter.open,
            onTap: () => onChanged(MyRoomFilter.open),
          ),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SegItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.textSub,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.25)
                      : AppTheme.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white
                        : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}