import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// ✨ SuggestionsSection — 리디자인 + 메시지 보내기
//
// 변경:
// - 헤더: 그라데이션 아이콘 컨테이너
// - 미니 카드: NEW 뱃지 그라데이션
// - 더보기 카드: 그라데이션 보더 + 색상
// - 디테일 시트: [관심없음] [메시지] [친구추가]
// - 전체 모달: 각 아이템에 [×] [💬] [친구추가]
// ═══════════════════════════════════════════════

const _kVisibleLimit = 5;
const _kCardWidth = 76.0;
const _kAvatarSize = 54.0;

class SuggestionsSection extends StatefulWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onTap;
  final void Function(SuggestedFriend) onAdd;
  final void Function(String) onDismiss;

  /// ⭐ 메시지 보내기 콜백 (부모에서 DM 진입 로직 연결)
  final void Function(SuggestedFriend)? onMessage;

  const SuggestionsSection({
    super.key,
    required this.suggestions,
    required this.onTap,
    required this.onAdd,
    required this.onDismiss,
    this.onMessage,
  });

  @override
  State<SuggestionsSection> createState() =>
      _SuggestionsSectionState();
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
        // 헤더
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.22),
                          AppTheme.primary.withOpacity(0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: AppTheme.primary, size: 12),
                  ),
                  const SizedBox(width: 8),
                  Text('알 수도 있는 친구',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          letterSpacing: -0.3)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${widget.suggestions.length}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.primaryLight,
                            fontWeight: FontWeight.w800)),
                  ),
                  const Spacer(),
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
        ),

        // 카드 영역
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? SizedBox(
                  height: 102,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    physics: const BouncingScrollPhysics(),
                    itemCount:
                        visible.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (hasMore && i == visible.length) {
                        return _MoreCard(
                          count: moreCount,
                          onTap: () => _showAllSheet(
                            context,
                            suggestions: widget.suggestions,
                            onAdd: widget.onAdd,
                            onDismiss: widget.onDismiss,
                            onMessage: widget.onMessage,
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
                          onMessage: widget.onMessage,
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 8),
        Container(height: 0.5, color: AppTheme.border.withOpacity(0.5)),
      ],
    );
  }

  static void _showDetailSheet(
    BuildContext context, {
    required SuggestedFriend suggestion,
    required void Function(SuggestedFriend) onAdd,
    required void Function(String) onDismiss,
    void Function(SuggestedFriend)? onMessage,
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
        onMessage: onMessage == null
            ? null
            : () {
                Navigator.pop(context);
                onMessage(suggestion);
              },
      ),
    );
  }

  static void _showAllSheet(
    BuildContext context, {
    required List<SuggestedFriend> suggestions,
    required void Function(SuggestedFriend) onAdd,
    required void Function(String) onDismiss,
    void Function(SuggestedFriend)? onMessage,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AllSuggestionsSheet(
        suggestions: suggestions,
        onAdd: onAdd,
        onDismiss: onDismiss,
        onMessage: onMessage,
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 미니 카드
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
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: suggestion.isNewUser
                        ? [
                            BoxShadow(
                              color: AppTheme.primary
                                  .withOpacity(0.3),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                  child: AvatarWidget(
                    url: suggestion.avatarUrl,
                    name: suggestion.nickname,
                    size: _kAvatarSize,
                  ),
                ),
                if (suggestion.isNewUser)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.85),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: AppTheme.bg, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              suggestion.nickname,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
                letterSpacing: -0.2,
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
// 더보기 카드
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
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.18),
                    AppTheme.primary.withOpacity(0.08),
                  ],
                ),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.3),
                    width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryLight,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '더보기',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryLight,
                letterSpacing: -0.2,
              ),
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
  final VoidCallback? onMessage;

  const _DetailSheet({
    required this.suggestion,
    required this.onAdd,
    required this.onDismiss,
    this.onMessage,
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
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.25),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: AvatarWidget(
                      url: suggestion.avatarUrl,
                      name: suggestion.nickname,
                      size: 80,
                    ),
                  ),
                  if (suggestion.isNewUser)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary,
                              AppTheme.primary.withOpacity(0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.bgCard, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary
                                  .withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                suggestion.nickname,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMain,
                  letterSpacing: -0.4,
                ),
              ),
              if (suggestion.statusMessage != null &&
                  suggestion.statusMessage!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  suggestion.statusMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSub,
                    height: 1.4,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              if (suggestion.mutualNicknames.isNotEmpty)
                _MutualText(suggestion: suggestion),
              const SizedBox(height: 22),

              // 액션 버튼들
              Row(
                children: [
                  // 관심 없음
                  Expanded(
                    flex: 2,
                    child: _OutlineButton(
                      label: '관심 없음',
                      onTap: onDismiss,
                    ),
                  ),
                  if (onMessage != null) ...[
                    const SizedBox(width: 8),
                    // ⭐ 메시지 (cyan)
                    Expanded(
                      flex: 2,
                      child: _GradientActionButton(
                        icon: Icons.chat_bubble_rounded,
                        label: '메시지',
                        colors: const [
                          Color(0xFF06B6D4),
                          Color(0xFF0891B2)
                        ],
                        shadowColor: const Color(0xFF06B6D4),
                        onTap: onMessage!,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // 친구 추가 (primary)
                  Expanded(
                    flex: 3,
                    child: _GradientActionButton(
                      icon: Icons.person_add_alt_1_rounded,
                      label: '친구 추가',
                      colors: [
                        AppTheme.primary,
                        AppTheme.primary.withOpacity(0.85),
                      ],
                      shadowColor: AppTheme.primary,
                      onTap: onAdd,
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

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final Color shadowColor;
  final VoidCallback onTap;

  const _GradientActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.shadowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 15),
                  const SizedBox(width: 5),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                ],
              ),
            ),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.10),
            AppTheme.primary.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.2), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_alt_rounded,
              color: AppTheme.primary, size: 13),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMain,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
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
// 전체 모달
// ═══════════════════════════════════════════════
class _AllSuggestionsSheet extends StatefulWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onAdd;
  final void Function(String) onDismiss;
  final void Function(SuggestedFriend)? onMessage;

  const _AllSuggestionsSheet({
    required this.suggestions,
    required this.onAdd,
    required this.onDismiss,
    this.onMessage,
  });

  @override
  State<_AllSuggestionsSheet> createState() =>
      _AllSuggestionsSheetState();
}

class _AllSuggestionsSheetState
    extends State<_AllSuggestionsSheet> {
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.25),
                          AppTheme.primary.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: AppTheme.primary, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '알 수도 있는 친구',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_items.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primaryLight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
                height: 0.5,
                color: AppTheme.border.withOpacity(0.5)),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 6),
                physics: const BouncingScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, __) => Container(
                    height: 0.5,
                    color: AppTheme.border.withOpacity(0.4),
                    margin: const EdgeInsets.only(left: 70)),
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
                        _items.removeWhere(
                            (x) => x.userId == s.userId);
                      });
                    },
                    onMessage: widget.onMessage == null
                        ? null
                        : () => widget.onMessage!(s),
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
  final VoidCallback? onMessage;

  const _AllListTile({
    required this.suggestion,
    required this.isAdded,
    required this.onAdd,
    required this.onDismiss,
    this.onMessage,
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
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: suggestion.isNewUser
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: AvatarWidget(
                  url: suggestion.avatarUrl,
                  name: suggestion.nickname,
                  size: 42,
                ),
              ),
              if (suggestion.isNewUser)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.85),
                        ],
                      ),
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
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
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
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 닫기
          _RoundIconButton(
            icon: Icons.close_rounded,
            color: AppTheme.textSub,
            bgColor: AppTheme.bg,
            onTap: onDismiss,
          ),
          if (onMessage != null) ...[
            const SizedBox(width: 4),
            // ⭐ 메시지 (cyan)
            _RoundIconButton(
              icon: Icons.chat_bubble_rounded,
              color: Colors.white,
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
              ),
              shadowColor: const Color(0xFF06B6D4),
              onTap: onMessage!,
            ),
          ],
          const SizedBox(width: 4),
          // 친구 추가 (primary 작은 버튼)
          Container(
            height: 30,
            decoration: BoxDecoration(
              gradient: isAdded
                  ? null
                  : LinearGradient(
                      colors: [
                        AppTheme.primary,
                        AppTheme.primary.withOpacity(0.85),
                      ],
                    ),
              color: isAdded ? AppTheme.bg : null,
              borderRadius: BorderRadius.circular(9),
              border: isAdded
                  ? Border.all(color: AppTheme.border)
                  : null,
              boxShadow: isAdded
                  ? null
                  : [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isAdded ? null : onAdd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11),
                    child: Center(
                      child: Text(
                        isAdded ? '요청됨' : '추가',
                        style: TextStyle(
                          color: isAdded
                              ? AppTheme.textSub
                              : Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 작은 원형 아이콘 버튼
// ═══════════════════════════════════════════════
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final Gradient? gradient;
  final Color? shadowColor;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.bgColor,
    this.gradient,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? bgColor : null,
        shape: BoxShape.circle,
        border: gradient == null
            ? Border.all(color: AppTheme.border)
            : null,
        boxShadow: shadowColor != null
            ? [
                BoxShadow(
                  color: shadowColor!.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(icon, color: color, size: 14),
            ),
          ),
        ),
      ),
    );
  }
}