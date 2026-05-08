import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../chat/models/chat_room_model.dart';
import '../../chat/providers/chat_provider.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../profile/screens/my_profile_screen.dart';
import '../models/friend_model.dart';
import '../providers/friends_provider.dart';
import '../widgets/friend_tile.dart';
import '../widgets/panel_menu_item.dart';
import '../widgets/suggestions_section.dart';
import '../sheets/add_friend_sheet.dart';
import '../sheets/friend_manage_sheet.dart';
import '../sheets/requests_sheet.dart';

// ⭐ 하위 호환성 re-export
// 이 파일을 import하던 기존 코드(app.dart, chat_list_screen.dart,
// chat_room_screen.dart, main_screen.dart, settings_screen.dart,
// group_chat_list_screen.dart)가 변경 없이도 FriendModel,
// SuggestedFriend, 5개 provider를 그대로 쓸 수 있도록 다시 내보냄.
export '../models/friend_model.dart';
export '../providers/friends_provider.dart';

// ═══════════════════════════════════════════════
// 친구 메인 스크린
//
// 위치: lib/features/friends/screens/friends_screen.dart
// ═══════════════════════════════════════════════

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _search = '';
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  late AnimationController _panelController;
  late Animation<Offset> _panelAnimation;
  bool _isPanelOpen = false;
  final Set<String> _dismissedSuggestions = {};

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _panelAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _panelController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════
  // 사이드 패널
  // ═════════════════════════════════════════════
  void _openPanel() {
    setState(() => _isPanelOpen = true);
    _panelController.forward();
  }

  void _closePanel() {
    _panelController.reverse().then((_) {
      if (mounted) setState(() => _isPanelOpen = false);
    });
  }

  // ═════════════════════════════════════════════
  // Provider 새로고침
  // ═════════════════════════════════════════════
  void _invalidateAll() {
    ref.invalidate(friendsProvider);
    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(sentRequestsProvider);
    ref.invalidate(myProfileProvider);
    ref.invalidate(friendSuggestionsProvider);
  }

  // ═════════════════════════════════════════════
  // 채팅 시작
  // ═════════════════════════════════════════════
  Future<void> _startChat(FriendModel friend) async {
    final supabase = Supabase.instance.client;

    final existing = await supabase
        .from('kyorangtalk_rooms')
        .select('*')
        .or('and(user1_id.eq.$_myId,user2_id.eq.${friend.friendId}),'
            'and(user1_id.eq.${friend.friendId},user2_id.eq.$_myId)')
        .maybeSingle();

    String roomId;
    if (existing != null) {
      roomId = existing['id'] as String;
    } else {
      final newRoom = await supabase
          .from('kyorangtalk_rooms')
          .insert({'user1_id': _myId, 'user2_id': friend.friendId})
          .select()
          .single();
      roomId = newRoom['id'] as String;
    }

    if (!mounted) return;

    final room = ChatRoomModel(
      partnerId:       friend.friendId,
      partnerUsername: friend.nickname,
      partnerName:     friend.nickname,
      partnerAvatar:   friend.avatarUrl,
      lastMessage:     '',
      lastTime:        DateTime.now(),
      unreadCount:     0,
      isSent:          false,
      roomId:          roomId,
    );

    context.push('/main/chat/${room.roomId}', extra: room);
  }

  // ═════════════════════════════════════════════
  // 프로필 열기
  // ═════════════════════════════════════════════
  void _openProfile(FriendModel friend) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId:    friend.friendId,
          nickname:  friend.nickname,
          avatarUrl: friend.avatarUrl,
        ),
      ),
    );
  }

  void _openSuggestedProfile(SuggestedFriend s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId:    s.userId,
          nickname:  s.nickname,
          avatarUrl: s.avatarUrl,
        ),
      ),
    ).then((_) => _invalidateAll());
  }

  void _openMyProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MyProfileScreen(),
      ),
    );
    ref.invalidate(myProfileProvider);
    ref.invalidate(friendsProvider);
  }

  // ═════════════════════════════════════════════
  // 친구 요청 (보내기/수락/거절/취소)
  // ═════════════════════════════════════════════
  Future<void> _sendSuggestionRequest(SuggestedFriend s) async {
    try {
      await Supabase.instance.client
          .from('kyorangtalk_friends')
          .insert({
        'requester_id': _myId,
        'receiver_id':  s.userId,
        'status':       'pending',
      });
      _invalidateAll();
      if (mounted) _showSnack('${s.nickname}님에게 친구 요청을 보냈어요');
    } catch (e) {
      if (mounted) _showSnack('요청 실패: $e');
    }
  }

  void _dismissSuggestion(String userId) {
    setState(() => _dismissedSuggestions.add(userId));
  }

  Future<void> _acceptRequest(String requestId) async {
    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .update({'status': 'accepted'})
        .eq('id', requestId);
    _invalidateAll();
  }

  Future<void> _rejectRequest(String requestId) async {
    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .update({'status': 'rejected'})
        .eq('id', requestId);
    _invalidateAll();
  }

  Future<void> _cancelRequest(String requestId) async {
    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .delete()
        .eq('id', requestId);
    _invalidateAll();
    if (mounted) _showSnack('친구 요청을 취소했어요');
  }

  // ═════════════════════════════════════════════
  // 친구 삭제 / 차단
  // ═════════════════════════════════════════════
  Future<void> _removeFriend(String friendId) async {
    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .delete()
        .or('and(requester_id.eq.$_myId,receiver_id.eq.$friendId),'
            'and(requester_id.eq.$friendId,receiver_id.eq.$_myId)');
    _invalidateAll();
    if (mounted) _showSnack('친구를 삭제했어요');
  }

  Future<void> _blockFriend(String friendId, String nickname) async {
    final supabase = Supabase.instance.client;

    await supabase
        .from('kyorangtalk_friends')
        .delete()
        .or('and(requester_id.eq.$_myId,receiver_id.eq.$friendId),'
            'and(requester_id.eq.$friendId,receiver_id.eq.$_myId)');

    await supabase.from('kyorangtalk_blocks').insert({
      'blocker_id': _myId,
      'blocked_id': friendId,
    });

    _invalidateAll();
    ref.invalidate(chatRoomsProvider);

    if (mounted) _showSnack('$nickname님을 차단했어요');
  }

  // ═════════════════════════════════════════════
  // 스낵바
  // ═════════════════════════════════════════════
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ═════════════════════════════════════════════
  // 시트 호출
  // ═════════════════════════════════════════════
  void _showAddFriendDialog() {
    _closePanel();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddFriendSheet(
        myId: _myId,
        onSent: _invalidateAll,
      ),
    );
  }

  void _showRequestsSheet() {
    _closePanel();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RequestsSheet(
        onAccept: _acceptRequest,
        onReject: _rejectRequest,
        onCancel: _cancelRequest,
      ),
    );
  }

  void _showFriendManageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FriendManageSheet(
        myId: _myId,
        onRemove: (friendId) {
          Navigator.pop(ctx);
          _removeFriend(friendId);
        },
        onBlock: (friendId, nickname) {
          Navigator.pop(ctx);
          _showBlockConfirm(friendId, nickname);
        },
      ),
    );
  }

  void _showBlockConfirm(String friendId, String nickname) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('차단하기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '$nickname님을 차단하면 서로 메시지를 주고받을 수 없어요.\n친구 관계도 해제돼요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _blockFriend(friendId, nickname);
            },
            child: const Text('차단',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════
  // build
  // ═════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final friendsAsync     = ref.watch(friendsProvider);
    final pendingAsync     = ref.watch(pendingRequestsProvider);
    final myProfileAsync   = ref.watch(myProfileProvider);
    final suggestionsAsync = ref.watch(friendSuggestionsProvider);
    final pendingCount     = pendingAsync.value?.length ?? 0;

    final suggestions = (suggestionsAsync.value ?? [])
        .where((s) => !_dismissedSuggestions.contains(s.userId))
        .toList();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppTheme.bg,
          body: SafeArea(
            child: Column(
              children: [
                // ── 헤더 ──
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      Text('친구',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain)),
                      const Spacer(),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(Icons.more_vert,
                                color: AppTheme.textSub),
                            onPressed: _openPanel,
                          ),
                          if (pendingCount > 0)
                            Positioned(
                              top: 6, right: 6,
                              child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── 내 프로필 ──
                myProfileAsync.when(
                  loading: () => const SizedBox(height: 80),
                  error: (_, __) => const SizedBox(),
                  data: (prof) {
                    final nickname =
                        prof?['nickname'] as String? ?? '';
                    final avatar =
                        prof?['avatar_url'] as String?;
                    final statusMessage =
                        prof?['status_message'] as String?;
                    return InkWell(
                      onTap: _openMyProfile,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: AppTheme.border)),
                        ),
                        child: Row(
                          children: [
                            AvatarWidget(
                                url:  avatar,
                                name: nickname,
                                size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(nickname,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight.w700,
                                          color:
                                              AppTheme.textMain)),
                                  if (statusMessage != null &&
                                      statusMessage.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(statusMessage,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.textSub),
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis),
                                  ],
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: AppTheme.textSub, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // ── 검색바 ──
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) =>
                          setState(() => _search = v),
                      style: TextStyle(
                          color: AppTheme.textMain, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '친구 검색...',
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                        prefixIcon: Icon(Icons.search,
                            color: AppTheme.textSub, size: 18),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close,
                                    color: AppTheme.textSub,
                                    size: 16),
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

                // ── 추천 + 친구 목록 ──
                Expanded(
                  child: friendsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    ),
                    error: (e, _) => Center(
                      child: Text('오류: $e',
                          style:
                              TextStyle(color: AppTheme.textSub)),
                    ),
                    data: (friends) {
                      final filtered = _search.isEmpty
                          ? friends
                          : friends
                              .where((f) => f.nickname
                                  .toLowerCase()
                                  .contains(_search.toLowerCase()))
                              .toList();

                      return CustomScrollView(
                        slivers: [
                          if (_search.isEmpty &&
                              suggestions.isNotEmpty)
                            SliverToBoxAdapter(
                              child: SuggestionsSection(
                                suggestions: suggestions,
                                onTap:       _openSuggestedProfile,
                                onAdd:       _sendSuggestionRequest,
                                onDismiss:   _dismissSuggestion,
                              ),
                            ),

                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                      20, 12, 20, 4),
                              child: Row(
                                children: [
                                  Text('친구 목록',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSub,
                                          fontWeight:
                                              FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  Text('${friends.length}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSub,
                                          fontWeight:
                                              FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),

                          if (filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Text('👥',
                                        style:
                                            TextStyle(fontSize: 48)),
                                    const SizedBox(height: 16),
                                    Text(
                                      _search.isNotEmpty
                                          ? '"$_search" 검색 결과가 없어요'
                                          : '아직 친구가 없어요',
                                      style: TextStyle(
                                          color: AppTheme.textSub,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(height: 12),
                                    if (_search.isEmpty)
                                      TextButton.icon(
                                        onPressed:
                                            _showAddFriendDialog,
                                        icon: const Icon(
                                            Icons
                                                .person_add_outlined,
                                            color: AppTheme.primary,
                                            size: 18),
                                        label: const Text('친구 추가',
                                            style: TextStyle(
                                                color:
                                                    AppTheme.primary)),
                                      ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) {
                                  final friend = filtered[i];
                                  return FriendTile(
                                    friend: friend,
                                    onTap:  () =>
                                        _openProfile(friend),
                                    onChat: () =>
                                        _startChat(friend),
                                  );
                                },
                                childCount: filtered.length,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 사이드 패널 dimmer ──
        if (_isPanelOpen)
          GestureDetector(
            onTap: _closePanel,
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),

        // ── 사이드 패널 본체 ──
        if (_isPanelOpen)
          Positioned(
            top: 0, right: 0, bottom: 0,
            width: 260,
            child: SlideTransition(
              position: _panelAnimation,
              child: Material(
                color: AppTheme.bgCard,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            20, 20, 16, 16),
                        child: Row(
                          children: [
                            Text('메뉴',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textMain)),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: AppTheme.textSub,
                                  size: 20),
                              onPressed: _closePanel,
                            ),
                          ],
                        ),
                      ),
                      Divider(color: AppTheme.border, height: 1),
                      const SizedBox(height: 8),
                      PanelMenuItem(
                        icon: Icons.person_add_outlined,
                        label: '친구 추가',
                        onTap: _showAddFriendDialog,
                      ),
                      PanelMenuItem(
                        icon: Icons.mark_email_unread_outlined,
                        label: '친구 요청함',
                        badge: pendingCount,
                        onTap: _showRequestsSheet,
                      ),
                      PanelMenuItem(
                        icon: Icons.people_outlined,
                        label: '친구 관리',
                        onTap: () {
                          _closePanel();
                          _showFriendManageSheet();
                        },
                      ),
                      PanelMenuItem(
                        icon: Icons.refresh_rounded,
                        label: '새로고침',
                        onTap: () {
                          _closePanel();
                          _invalidateAll();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}