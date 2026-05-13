import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 알 수도 있는 친구 섹션
//
// 위치: lib/features/friends/widgets/suggestions_section.dart
//
// 특징:
// - 헤더 탭하면 접기/펼치기 토글
// - 카드 작음 (아바타 + 닉네임만)
// - 카드 탭 → 디테일 시트
// - 화면 초과 시 마지막에 "+N명" 카드
// - "+N명" 탭 → 전체 모달
// - 디테일/모달에서 "OOO 외 N명과 친구" 형식만 표시
// ═══════════════════════════════════════════════

const _kVisibleLimit = 5;
const _kCardWidth = 72.0;
const _kAvatarSize = 50.0;

class SuggestionsSection extends StatefulWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onTap;       // 호환성 유지용 (이제 안 씀)
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
  State<SuggestionsSection> createState() => _SuggestionsSectionState();
}

class _SuggestionsSectionState extends State<SuggestionsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final visible = widget.suggestions.take(_kVisibleLimit).toList();
    final hasMore = widget.suggestions.length > _kVisibleLimit;
    final moreCount = widget.suggestions.length - _kVisibleLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⭐ 클릭 가능한 헤더
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppTheme.primary, size: 14),
                const SizedBox(width: 6),
                Text('알 수도 있는 친구',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
                const SizedBox(width: 6),
                Text('${widget.suggestions.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                // 펼침/접힘 인디케이터
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textSub,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ⭐ 카드 영역 — 접힘 애니메이션
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? SizedBox(
                  height: 96,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: visible.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (hasMore && i == visible.length) {
                        return _MoreCard(
                          count: moreCount,
                          onTap: () => _showAllSheet(
                            context,
                            suggestions: widget.suggestions,
                            onAdd: widget.onAdd,
                            onDismiss: widget.onDismiss,
                          ),
                        );
                      }
                      final s = visible[i];
                      return _MiniCard(
                        suggestion: s,
                        onTap: () => _showDetailSheet(
                          context,
                          suggestion: s,
                          onAdd: widget.onAdd,
                          onDismiss: widget.onDismiss,
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 8),
        Divider(color: AppTheme.border, height: 1),
      ],
    );
  }

  static void _showDetailSheet(
    BuildContext context, {
    required SuggestedFriend suggestion,
    required void Function(SuggestedFriend) onAdd,
    required void Function(String) onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(
        suggestion: suggestion,
        onAdd: () {
          Navigator.pop(context);
          onAdd(suggestion);
        },
        onDismiss: () {
          Navigator.pop(context);
          onDismiss(suggestion.userId);
        },
      ),
    );
  }

  static void _showAllSheet(
    BuildContext context, {
    required List<SuggestedFriend> suggestions,
    required void Function(SuggestedFriend) onAdd,
    required void Function(String) onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AllSuggestionsSheet(
        suggestions: suggestions,
        onAdd: onAdd,
        onDismiss: onDismiss,
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 작은 카드 — 아바타 + 닉네임
// ═══════════════════════════════════════════════
class _MiniCard extends StatelessWidget {
  final SuggestedFriend suggestion;
  final VoidCallback onTap;

  const _MiniCard({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _kCardWidth,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(
                  url:  suggestion.avatarUrl,
                  name: suggestion.nickname,
                  size: _kAvatarSize,
                ),
                if (suggestion.isNewUser)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppTheme.bg, width: 1.2),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 6.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              suggestion.nickname,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// +N명 더보기 카드
// ═══════════════════════════════════════════════
class _MoreCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MoreCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _kCardWidth,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bgCard,
                border: Border.all(color: AppTheme.border, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '더보기',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSub,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 디테일 시트
// ═══════════════════════════════════════════════
class _DetailSheet extends StatelessWidget {
  final SuggestedFriend suggestion;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  const _DetailSheet({
    required this.suggestion,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarWidget(
                    url:  suggestion.avatarUrl,
                    name: suggestion.nickname,
                    size: 76,
                  ),
                  if (suggestion.isNewUser)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: AppTheme.bgCard, width: 2),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                suggestion.nickname,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              ),
              if (suggestion.statusMessage != null &&
                  suggestion.statusMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  suggestion.statusMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSub,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              if (suggestion.mutualNicknames.isNotEmpty)
                _MutualText(suggestion: suggestion),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '관심 없음',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: onAdd,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        '친구 추가',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutualText extends StatelessWidget {
  final SuggestedFriend suggestion;
  const _MutualText({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final names = suggestion.mutualNicknames;
    final first = names.first;
    final rest = names.length - 1;
    final text =
        rest > 0 ? '$first 외 $rest명과 친구' : '$first 님과 친구';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              color: AppTheme.primary, size: 13),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMain,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 전체 보기 모달
// ═══════════════════════════════════════════════
class _AllSuggestionsSheet extends StatefulWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onAdd;
  final void Function(String) onDismiss;

  const _AllSuggestionsSheet({
    required this.suggestions,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  State<_AllSuggestionsSheet> createState() =>
      _AllSuggestionsSheetState();
}

class _AllSuggestionsSheetState extends State<_AllSuggestionsSheet> {
  late List<SuggestedFriend> _items;
  final Set<String> _added = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.suggestions);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '알 수도 있는 친구',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_items.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _items.length,
                separatorBuilder: (_, __) => Divider(
                    color: AppTheme.border, height: 1, indent: 68),
                itemBuilder: (_, i) {
                  final s = _items[i];
                  final isAdded = _added.contains(s.userId);
                  return _AllListTile(
                    suggestion: s,
                    isAdded: isAdded,
                    onAdd: () {
                      setState(() => _added.add(s.userId));
                      widget.onAdd(s);
                    },
                    onDismiss: () {
                      widget.onDismiss(s.userId);
                      setState(() {
                        _items.removeWhere((x) => x.userId == s.userId);
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllListTile extends StatelessWidget {
  final SuggestedFriend suggestion;
  final bool isAdded;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  const _AllListTile({
    required this.suggestion,
    required this.isAdded,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final names = suggestion.mutualNicknames;
    String? mutualText;
    if (names.isNotEmpty) {
      final first = names.first;
      final rest = names.length - 1;
      mutualText =
          rest > 0 ? '$first 외 $rest명과 친구' : '$first 님과 친구';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarWidget(
                url:  suggestion.avatarUrl,
                name: suggestion.nickname,
                size: 40,
              ),
              if (suggestion.isNewUser)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 3.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: AppTheme.bgCard, width: 1.2),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 6.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.nickname,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (mutualText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    mutualText,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close,
                color: AppTheme.textSub, size: 16),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 2),
          ElevatedButton(
            onPressed: isAdded ? null : onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.bg,
              disabledForegroundColor: AppTheme.textSub,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isAdded ? '요청됨' : '친구 추가',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}