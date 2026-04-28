import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../models/poll_model.dart';
import '../models/poll_vote_model.dart';
import '../providers/poll_provider.dart';

// ═══════════════════════════════════════════════════
// 📊 투표 버블 (RepaintBoundary로 부모 격리!)
// ═══════════════════════════════════════════════════

class PollBubble extends ConsumerWidget {
  final String pollId;
  final bool isMe;

  const PollBubble({
    super.key,
    required this.pollId,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⭐ RepaintBoundary로 격리하여 부모에 영향 안 주게!
    return RepaintBoundary(
      child: _PollBubbleContent(pollId: pollId, isMe: isMe),
    );
  }
}

// ═══════════════════════════════════════════════════
// 📊 실제 컨텐츠 (격리됨)
// ═══════════════════════════════════════════════════
class _PollBubbleContent extends ConsumerWidget {
  final String pollId;
  final bool isMe;

  const _PollBubbleContent({
    required this.pollId,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollAsync = ref.watch(singlePollProvider(pollId));
    final resultAsync = ref.watch(pollResultProvider(pollId));

    return pollAsync.when(
      loading: () => _buildSkeletonCard(),
      error: (e, _) => _buildErrorCard(),
      data: (poll) {
        if (poll == null) return _buildDeletedCard();
        return resultAsync.when(
          loading: () => _buildPollCard(context, poll, null),
          error: (_, __) => _buildPollCard(context, poll, null),
          data: (result) => _buildPollCard(context, poll, result),
        );
      },
    );
  }

  Widget _buildPollCard(
      BuildContext context, PollModel poll, PollResult? result) {
    final isEnded = poll.isEnded;

    return Container(
      // ⭐ 고정 너비 강제! (높이 변동 영향 최소화)
      constraints: const BoxConstraints(
        minWidth: 240,
        maxWidth: 280,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        border: Border.all(
          color: isEnded
              ? AppTheme.border
              : AppTheme.primary.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(poll, isEnded),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Text(
              poll.question,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
                height: 1.3,
              ),
            ),
          ),
          Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              children: _buildOptions(poll, result),
            ),
          ),
          // ⭐ 시간 표시는 별도 격리된 위젯으로!
          _PollFooter(poll: poll, totalVoters: result?.totalVoters ?? 0),
          if (!isEnded)
            _buildVoteButton(context, poll, result),
        ],
      ),
    );
  }

  Widget _buildHeader(PollModel poll, bool isEnded) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: isEnded
            ? AppTheme.border.withOpacity(0.3)
            : AppTheme.primary.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          Text(isEnded ? '🏁' : '📊',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            isEnded ? '마감된 투표' : '투표',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isEnded ? AppTheme.textSub : AppTheme.primary,
            ),
          ),
          const Spacer(),
          if (poll.isAnonymous) ...[
            Icon(Icons.visibility_off_outlined,
                size: 11, color: AppTheme.textMuted),
            const SizedBox(width: 3),
            Text('익명',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
          ],
          if (poll.allowMultiple) ...[
            if (poll.isAnonymous) const SizedBox(width: 6),
            Icon(Icons.check_box_outlined,
                size: 11, color: AppTheme.textMuted),
            const SizedBox(width: 3),
            Text('복수',
                style: TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildOptions(PollModel poll, PollResult? result) {
    final widgets = <Widget>[];

    for (int i = 0; i < poll.options.length; i++) {
      final option = poll.options[i];

      final optionResult = result?.options.firstWhere(
        (r) => r.optionId == option.id,
        orElse: () => PollOptionResult(
          optionId: option.id,
          optionText: option.text,
          voteCount: 0,
        ),
      );
      final voteCount = optionResult?.voteCount ?? 0;
      final totalVotes = result?.totalVotes ?? 0;
      final percentage = totalVotes > 0
          ? (voteCount / totalVotes * 100)
          : 0.0;

      final isMySelected = result?.myChoices.contains(option.id) ?? false;
      final isTop = result != null &&
          result.totalVoters > 0 &&
          result.topOption?.optionId == option.id;

      widgets.add(_buildOptionItem(
        option: option,
        voteCount: voteCount,
        percentage: percentage,
        isMySelected: isMySelected,
        isTop: isTop,
      ));

      if (i < poll.options.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }

    return widgets;
  }

  Widget _buildOptionItem({
    required PollOption option,
    required int voteCount,
    required double percentage,
    required bool isMySelected,
    required bool isTop,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isMySelected)
              Container(
                width: 16, height: 16,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 12),
              ),
            Expanded(
              child: Text(
                option.text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isMySelected || isTop
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isMySelected
                      ? AppTheme.primary
                      : AppTheme.textMain,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$voteCount명',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isTop ? AppTheme.primary : AppTheme.textSub,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            FractionallySizedBox(
              widthFactor: percentage / 100,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isMySelected
                        ? [const Color(0xFFA78BFA), AppTheme.primary]
                        : isTop
                            ? [AppTheme.primary.withOpacity(0.7), AppTheme.primary]
                            : [AppTheme.border, AppTheme.textMuted],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoteButton(
      BuildContext context, PollModel poll, PollResult? result) {
    final iVoted = result?.iVoted ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showVoteDialog(context, pollId: pollId),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: iVoted
                  ? AppTheme.primary.withOpacity(0.1)
                  : AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
              border: iVoted
                  ? Border.all(color: AppTheme.primary.withOpacity(0.3))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iVoted ? Icons.edit_outlined : Icons.how_to_vote,
                  size: 14,
                  color: iVoted ? AppTheme.primary : Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  iVoted ? '투표 수정' : '투표하기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: iVoted ? AppTheme.primary : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    // ⭐ 고정 크기로 변경! (로딩 중에도 같은 크기)
    return Container(
      width: 240,
      height: 200,  // ⭐ 고정 높이 추가
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text('투표를 불러올 수 없어요',
          style: TextStyle(
              fontSize: 13, color: AppTheme.textSub)),
    );
  }

  Widget _buildDeletedCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline,
              size: 16, color: AppTheme.textSub),
          const SizedBox(width: 6),
          Text('삭제된 투표예요',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSub,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// ⏰ Footer (시간 표시 - 격리됨)
// ═══════════════════════════════════════════════════
//
// ⭐ 핵심: 시간 표시를 별도 StatefulWidget으로 분리!
//    1초마다 자체적으로 setState 하지만 부모 영향 X
// ═══════════════════════════════════════════════════
class _PollFooter extends StatefulWidget {
  final PollModel poll;
  final int totalVoters;

  const _PollFooter({
    required this.poll,
    required this.totalVoters,
  });

  @override
  State<_PollFooter> createState() => _PollFooterState();
}

class _PollFooterState extends State<_PollFooter> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: AppTheme.bg.withOpacity(0.3),
          border: Border(
            top: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.people_outline,
                size: 11, color: AppTheme.textMuted),
            const SizedBox(width: 3),
            Text('${widget.totalVoters}명 참여',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(width: 8),
            Container(
              width: 2, height: 2,
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              widget.poll.isEnded ? Icons.lock_outline : Icons.schedule,
              size: 11,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                widget.poll.remainingTimeText,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 🗳️ 투표하기 다이얼로그
// ═══════════════════════════════════════════════════

Future<void> showVoteDialog(
  BuildContext context, {
  required String pollId,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _VoteSheet(pollId: pollId),
  );
}

class _VoteSheet extends ConsumerStatefulWidget {
  final String pollId;

  const _VoteSheet({required this.pollId});

  @override
  ConsumerState<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends ConsumerState<_VoteSheet> {
  final _selectedIds = <int>{};
  bool _initialized = false;
  bool _submitting = false;
  bool _showVoters = false;

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser!.id;
    final pollAsync = ref.watch(singlePollProvider(widget.pollId));
    final resultAsync = ref.watch(pollResultProvider(widget.pollId));

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: pollAsync.when(
          loading: () => _buildLoading(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('투표를 불러올 수 없어요',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          data: (poll) {
            if (poll == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('삭제된 투표예요',
                    style: TextStyle(color: AppTheme.textSub)),
              );
            }
            return resultAsync.when(
              loading: () => _buildLoading(),
              error: (_, __) => _buildLoading(),
              data: (result) {
                if (!_initialized) {
                  _selectedIds.clear();
                  _selectedIds.addAll(result.myChoices);
                  _initialized = true;
                }
                return _buildContent(poll, result, myId);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
  }

  Widget _buildContent(PollModel poll, PollResult result, String myId) {
    final isCreator = poll.createdBy == myId;
    final isEnded = poll.isEnded;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Text(isEnded ? '🏁' : '📊',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEnded ? '마감된 투표' : '투표하기',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              if (isCreator)
                PopupMenuButton<String>(
                  color: AppTheme.bgCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  icon: Icon(Icons.more_vert,
                      color: AppTheme.textSub, size: 22),
                  onSelected: (value) {
                    if (value == 'close') {
                      _closePoll();
                    } else if (value == 'delete') {
                      _deletePoll();
                    }
                  },
                  itemBuilder: (_) => [
                    if (!isEnded)
                      PopupMenuItem(
                        value: 'close',
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                color: AppTheme.textMain, size: 18),
                            const SizedBox(width: 10),
                            Text('투표 마감',
                                style: TextStyle(
                                    color: AppTheme.textMain,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              color: Color(0xFFEF4444), size: 18),
                          SizedBox(width: 10),
                          Text('투표 삭제',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              IconButton(
                icon: Icon(Icons.close,
                    color: AppTheme.textSub, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              if (poll.creatorNickname != null) ...[
                Text(
                  '${poll.creatorNickname}님',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 2, height: 2,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (poll.isAnonymous) ...[
                Icon(Icons.visibility_off_outlined,
                    size: 12, color: AppTheme.textMuted),
                const SizedBox(width: 3),
                Text('익명',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 6),
              ],
              if (poll.allowMultiple) ...[
                Icon(Icons.check_box_outlined,
                    size: 12, color: AppTheme.textMuted),
                const SizedBox(width: 3),
                Text('복수 선택',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
              ],
              const Spacer(),
              Text(
                poll.remainingTimeText,
                style: TextStyle(
                  fontSize: 11,
                  color: isEnded
                      ? const Color(0xFFEF4444)
                      : AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              poll.question,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
                height: 1.4,
              ),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              children: [
                ..._buildOptionList(poll, result, isEnded),
                if (!poll.isAnonymous && result.totalVoters > 0) ...[
                  const SizedBox(height: 12),
                  _buildVotersToggle(result),
                ],
              ],
            ),
          ),
        ),
        if (!isEnded)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                if (result.iVoted)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _cancelVote,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '투표 취소',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (result.iVoted) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _selectedIds.isEmpty || _submitting
                        ? null
                        : _submitVote,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            result.iVoted ? '투표 수정' : '투표하기',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildOptionList(
      PollModel poll, PollResult result, bool isEnded) {
    return poll.options.map((option) {
      final optionResult = result.options.firstWhere(
        (r) => r.optionId == option.id,
        orElse: () => PollOptionResult(
          optionId: option.id,
          optionText: option.text,
          voteCount: 0,
        ),
      );

      final isSelected = _selectedIds.contains(option.id);
      final voteCount = optionResult.voteCount;
      final percentage = result.totalVotes > 0
          ? (voteCount / result.totalVotes * 100)
          : 0.0;
      final isTop = result.totalVoters > 0 &&
          result.topOption?.optionId == option.id;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: isEnded ? null : () => _toggleOption(option.id, poll),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withOpacity(0.1)
                  : AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: poll.allowMultiple
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                        borderRadius: poll.allowMultiple
                            ? BorderRadius.circular(6)
                            : null,
                        color: isSelected
                            ? AppTheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.border,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected || isTop
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$voteCount명',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isTop
                            ? AppTheme.primary
                            : AppTheme.textSub,
                      ),
                    ),
                  ],
                ),
                if (_showVoters &&
                    !poll.isAnonymous &&
                    optionResult.voters.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: optionResult.voters.map((voter) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          voter.userNickname ?? '알 수 없음',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppTheme.border,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: percentage / 100,
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary
                                    : isTop
                                        ? AppTheme.primary.withOpacity(0.6)
                                        : AppTheme.textMuted,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${percentage.toStringAsFixed(0)}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
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
    }).toList();
  }

  Widget _buildVotersToggle(PollResult result) {
    return InkWell(
      onTap: () => setState(() => _showVoters = !_showVoters),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _showVoters
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 14,
              color: AppTheme.textSub,
            ),
            const SizedBox(width: 4),
            Text(
              _showVoters
                  ? '투표자 숨기기'
                  : '투표자 보기 (${result.totalVoters}명)',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSub,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleOption(int optionId, PollModel poll) {
    setState(() {
      if (poll.allowMultiple) {
        if (_selectedIds.contains(optionId)) {
          _selectedIds.remove(optionId);
        } else {
          _selectedIds.add(optionId);
        }
      } else {
        _selectedIds.clear();
        _selectedIds.add(optionId);
      }
    });
  }

  Future<void> _submitVote() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _submitting = true);

    try {
      await vote(
        pollId: widget.pollId,
        optionIds: _selectedIds.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('투표가 반영됐어요'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('투표 실패: $e')),
        );
      }
    }
  }

  Future<void> _cancelVote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('투표 취소',
            style: TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          '정말 투표를 취소하시겠어요?\n나중에 다시 투표할 수 있어요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('아니요',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('취소하기',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _submitting = true);

    try {
      await cancelVote(widget.pollId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('투표를 취소했어요'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: $e')),
        );
      }
    }
  }

  Future<void> _closePoll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('투표 마감',
            style: TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          '투표를 지금 마감하시겠어요?\n더 이상 투표할 수 없게 돼요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('아니요',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('마감',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await closePoll(widget.pollId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투표를 마감했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('마감 실패: $e')),
        );
      }
    }
  }

  Future<void> _deletePoll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('투표 삭제',
            style: TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
            )),
        content: Text(
          '정말 이 투표를 삭제하시겠어요?\n모든 투표 기록이 함께 삭제돼요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await deletePoll(widget.pollId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투표를 삭제했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }
}