import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/reaction_provider.dart';

// ═══════════════════════════════════════════════════
// 메시지 버블 하단에 표시되는 반응 칩 모음
//
// - 같은 이모지끼리 그룹핑 + 카운트
// - 내가 누른 이모지는 강조
// - 칩 탭 → 토글
// ═══════════════════════════════════════════════════
class ReactionChips extends ConsumerWidget {
  final String messageId;
  final String roomId;
  final bool isGroup;
  final bool isMe;

  const ReactionChips({
    super.key,
    required this.messageId,
    required this.roomId,
    required this.isGroup,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final reactionsAsync = ref.watch(roomReactionsProvider(
      RoomReactionKey(roomId: roomId, isGroup: isGroup),
    ));

    final reactions = reactionsAsync.value?[messageId] ?? const [];
    if (reactions.isEmpty) return const SizedBox.shrink();

    final groups = groupReactions(reactions, myId);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
        children: groups.map((g) {
          return _ReactionChip(
            emoji:  g.emoji,
            count:  g.count,
            isMine: g.reactedByMe,
            onTap: () => toggleReaction(
              messageId: messageId,
              roomId:    roomId,
              emoji:     g.emoji,
              isGroup:   isGroup,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isMine
                ? AppTheme.primary.withOpacity(0.18)
                : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isMine
                  ? AppTheme.primary.withOpacity(0.6)
                  : AppTheme.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: isMine ? AppTheme.primary : AppTheme.textSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}