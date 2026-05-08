import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 알 수도 있는 친구 섹션 (가로 스크롤)
//
// 위치: lib/features/friends/widgets/suggestions_section.dart
//
// - SuggestionsSection : 섹션 헤더 + 가로 ListView
// - _SuggestionCard    : 개별 카드 (같은 파일 내부에서만 사용)
// ═══════════════════════════════════════════════

class SuggestionsSection extends StatelessWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onTap;
  final void Function(SuggestedFriend) onAdd;
  final void Function(String) onDismiss;

  const SuggestionsSection({
    super.key,
    required this.suggestions,
    required this.onTap,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text('알 수도 있는 친구',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain)),
              const SizedBox(width: 6),
              Text('${suggestions.length}',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: suggestions.length,
            itemBuilder: (_, i) {
              final s = suggestions[i];
              return _SuggestionCard(
                suggestion: s,
                onTap:     () => onTap(s),
                onAdd:     () => onAdd(s),
                onDismiss: () => onDismiss(s.userId),
              );
            },
          ),
        ),
        Divider(color: AppTheme.border, height: 1),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final SuggestedFriend suggestion;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  const _SuggestionCard({
    required this.suggestion,
    required this.onTap,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final mutualText = suggestion.mutualNicknames.isNotEmpty
        ? '${suggestion.mutualNicknames.first}'
            '${suggestion.mutualCount > 1 ? ' 외 ${suggestion.mutualCount - 1}명' : ''}과 친구'
        : '공통 친구 ${suggestion.mutualCount}명';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 4),
                AvatarWidget(
                  url:  suggestion.avatarUrl,
                  name: suggestion.nickname,
                  size: 60,
                ),
                const SizedBox(height: 10),
                Text(
                  suggestion.nickname,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  mutualText,
                  style: TextStyle(
                      fontSize: 10.5, color: AppTheme.textSub),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_alt_1_rounded,
                            color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('친구 추가',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: -4, right: -4,
              child: GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Icon(Icons.close,
                      color: AppTheme.textSub, size: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}