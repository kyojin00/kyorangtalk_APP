import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../enums/group_chat_enums.dart';

// ═══════════════════════════════════════════════════
// 오픈채팅 정렬 시트
//
// 위치: lib/features/group_chat/sheets/sort_sheet.dart
// ═══════════════════════════════════════════════════

Future<OpenRoomSort?> showSortSheet({
  required BuildContext context,
  required OpenRoomSort current,
}) {
  return showModalBottomSheet<OpenRoomSort>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SortSheetBody(current: current),
  );
}

class _SortSheetBody extends StatelessWidget {
  final OpenRoomSort current;
  const _SortSheetBody({required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '정렬 방식',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          ...OpenRoomSort.values.map((sort) {
            final selected = current == sort;
            return InkWell(
              onTap: () => Navigator.pop(context, sort),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                color: selected
                    ? AppTheme.primary.withOpacity(0.08)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withOpacity(0.15)
                            : AppTheme.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        sort.icon,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSub,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        sort.label,
                        style: TextStyle(
                          fontSize: 15,
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textMain,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}