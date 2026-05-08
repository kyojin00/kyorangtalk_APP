import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/friends_provider.dart';

// ═══════════════════════════════════════════════
// 친구 관리 바텀시트
//
// 위치: lib/features/friends/sheets/friend_manage_sheet.dart
//
// 친구 목록을 보면서 각 친구 옆 더보기 버튼으로
// "친구 삭제" / "차단하기" 액션을 실행할 수 있는 시트.
//
// 콜백:
//   - onRemove(friendId)            : 친구 삭제
//   - onBlock(friendId, nickname)   : 차단 (확인 다이얼로그는 부모가 띄움)
// ═══════════════════════════════════════════════

class FriendManageSheet extends ConsumerStatefulWidget {
  final String myId;
  final void Function(String friendId) onRemove;
  final void Function(String friendId, String nickname) onBlock;

  const FriendManageSheet({
    super.key,
    required this.myId,
    required this.onRemove,
    required this.onBlock,
  });

  @override
  ConsumerState<FriendManageSheet> createState() =>
      _FriendManageSheetState();
}

class _FriendManageSheetState extends ConsumerState<FriendManageSheet> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('친구 관리',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(
                    color: AppTheme.textMain, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '친구 검색...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  prefixIcon: Icon(Icons.search,
                      color: AppTheme.textSub, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close,
                              color: AppTheme.textSub, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          Divider(color: AppTheme.border, height: 1),
          Expanded(
            child: friendsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary)),
              error: (e, _) => Center(
                  child: Text('오류: $e',
                      style: TextStyle(color: AppTheme.textSub))),
              data: (friends) {
                final filtered = _search.isEmpty
                    ? friends
                    : friends
                        .where((f) => f.nickname
                            .toLowerCase()
                            .contains(_search.toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _search.isNotEmpty
                          ? '"$_search" 검색 결과가 없어요'
                          : '친구가 없어요',
                      style: TextStyle(
                          color: AppTheme.textSub, fontSize: 14),
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final friend = filtered[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: AppTheme.border)),
                      ),
                      child: Row(
                        children: [
                          AvatarWidget(
                              url: friend.avatarUrl,
                              name: friend.nickname,
                              size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(friend.nickname,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMain)),
                                if (friend.statusMessage != null &&
                                    friend.statusMessage!.isNotEmpty)
                                  Text(friend.statusMessage!,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSub),
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            color: AppTheme.bgCard,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            icon: Icon(Icons.more_horiz,
                                color: AppTheme.textSub),
                            onSelected: (value) {
                              if (value == 'delete') {
                                widget.onRemove(friend.friendId);
                              } else if (value == 'block') {
                                widget.onBlock(
                                    friend.friendId, friend.nickname);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_remove_outlined,
                                        color: AppTheme.textSub,
                                        size: 18),
                                    const SizedBox(width: 10),
                                    Text('친구 삭제',
                                        style: TextStyle(
                                            color: AppTheme.textMain,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'block',
                                child: Row(
                                  children: [
                                    Icon(Icons.block,
                                        color: Color(0xFFEF4444),
                                        size: 18),
                                    SizedBox(width: 10),
                                    Text('차단하기',
                                        style: TextStyle(
                                            color:
                                                Color(0xFFEF4444),
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}