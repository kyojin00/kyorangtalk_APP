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
export '../models/friend_model.dart';
export '../providers/friends_provider.dart';

// ═══════════════════════════════════════════════
// 친구 메인 스크린 — 리디자인
//
// 변경:
// - 헤더: SliverAppBar 스타일, 큰 타이틀
// - 내 프로필: 그라데이션 + 액션 버튼
// - 검색바: 더 부드러운 음영 + 포커스 효과
// - 친구 목록: 카운트 강조 + 그루핑
// - 빈 상태: 일러스트 + CTA 강화
// - 사이드 패널: 헤더에 프로필 미니카드
// ═══════════════════════════════════════════════

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
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
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _panelController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
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
  // 친구 요청
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

  void _dismissSuggestion(String userId) async {
    setState(() => _dismissedSuggestions.add(userId));
    await dismissFriendSuggestion(userId);
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
  // 즐겨찾기 토글
  // ═════════════════════════════════════════════
  Future<void> _toggleFavorite(FriendModel friend) async {
    try {
      final isNowFavorite = await toggleFriendFavorite(friend.friendId);
      _invalidateAll();
      if (mounted) {
        _showSnack(isNowFavorite
            ? '${friend.nickname}님을 즐겨찾기에 추가했어요'
            : '${friend.nickname}님을 즐겨찾기에서 해제했어요');
      }
    } catch (e) {
      if (mounted) _showSnack('즐겨찾기 변경 실패');
    }
  }

  // ═════════════════════════════════════════════
  // 신고 시트
  // ═════════════════════════════════════════════
  void _showReportSheet(FriendModel friend) {
    String selectedReason = 'spam';
    final descriptionController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    '${friend.nickname}님 신고',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '사유 선택',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub,
                    ),
                  ),
                  const SizedBox(height: 4),

                  ...const [
                    ['spam', '스팸/광고'],
                    ['harassment', '괴롭힘/욕설'],
                    ['inappropriate', '부적절한 콘텐츠'],
                    ['fake', '사칭/허위 정보'],
                    ['other', '기타'],
                  ].map((r) => RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: r[0],
                        groupValue: selectedReason,
                        onChanged: (v) => setSheetState(
                            () => selectedReason = v ?? 'spam'),
                        activeColor: AppTheme.primary,
                        title: Text(
                          r[1],
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textMain,
                          ),
                        ),
                      )),

                  const SizedBox(height: 12),
                  Text(
                    '자세한 내용 (선택)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    maxLength: 500,
                    style: TextStyle(
                        color: AppTheme.textMain, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '추가로 알려주실 내용이 있다면 적어주세요',
                      hintStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppTheme.primary),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '취소',
                            style: TextStyle(color: AppTheme.textSub),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              await reportFriend(
                                reportedUserId: friend.friendId,
                                reason: selectedReason,
                                description: descriptionController
                                        .text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
                              );
                              if (mounted) _showSnack('신고가 접수됐어요');
                            } catch (e) {
                              if (mounted) _showSnack('신고 실패');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '신고하기',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════
  // 친구 삭제 확인
  // ═════════════════════════════════════════════
  void _confirmRemoveFriend(FriendModel friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '친구 삭제',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '${friend.nickname}님을 친구 목록에서 삭제할까요?',
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
              _removeFriend(friend.friendId);
            },
            child: const Text(
              '삭제',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                color: AppTheme.textMain, fontWeight: FontWeight.w700)),
        content: Text(
          '$nickname님을 차단하면 서로 메시지를 주고받을 수 없어요.\n친구 관계도 해제돼요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
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
                // ─────────────────────────────────────────
                // ✨ 헤더 — 큰 타이틀 + 우측 아이콘
                // ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: [
                      Text(
                        '친구',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      friendsAsync.maybeWhen(
                        data: (friends) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${friends.length}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSub,
                            ),
                          ),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      // 친구 추가 빠른 버튼
                      _CircleIconButton(
                        icon: Icons.person_add_outlined,
                        onTap: _showAddFriendDialog,
                      ),
                      const SizedBox(width: 8),
                      // 친구 요청 (배지 포함)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _CircleIconButton(
                            icon: Icons.mail_outline_rounded,
                            onTap: _showRequestsSheet,
                          ),
                          if (pendingCount > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                constraints: const BoxConstraints(
                                    minWidth: 16, minHeight: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppTheme.bg, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    pendingCount > 9 ? '9+' : '$pendingCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _CircleIconButton(
                        icon: Icons.more_horiz_rounded,
                        onTap: _openPanel,
                      ),
                    ],
                  ),
                ),

                // ─────────────────────────────────────────
                // ✨ 내 프로필 카드 — 그라데이션 강조
                // ─────────────────────────────────────────
                myProfileAsync.when(
                  loading: () => const SizedBox(height: 92),
                  error: (_, __) => const SizedBox(),
                  data: (prof) {
                    final nickname = prof?['nickname'] as String? ?? '';
                    final avatar = prof?['avatar_url'] as String?;
                    final statusMessage =
                        prof?['status_message'] as String?;
                    return Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openMyProfile,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(
                                14, 14, 18, 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primary.withOpacity(0.10),
                                  AppTheme.primary.withOpacity(0.03),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: AppTheme.primary.withOpacity(0.18),
                              ),
                            ),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    AvatarWidget(
                                      url: avatar,
                                      name: nickname,
                                      size: 52,
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF22C55E),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppTheme.bg,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              nickname,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color:
                                                    AppTheme.textMain,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      6),
                                            ),
                                            child: Text(
                                              '나',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color:
                                                    AppTheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        statusMessage?.isNotEmpty == true
                                            ? statusMessage!
                                            : '상태 메시지를 입력해보세요',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              statusMessage?.isNotEmpty ==
                                                      true
                                                  ? AppTheme.textSub
                                                  : AppTheme.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgCard,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: AppTheme.textSub,
                                    size: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // ─────────────────────────────────────────
                // ✨ 검색바 — 포커스 효과 + 더 부드러운 모양
                // ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _searchFocus.hasFocus
                            ? AppTheme.primary.withOpacity(0.5)
                            : AppTheme.border,
                        width: _searchFocus.hasFocus ? 1.5 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(
                          color: AppTheme.textMain, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '친구 이름으로 검색',
                        hintStyle: TextStyle(
                            color: AppTheme.textMuted, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _searchFocus.hasFocus
                              ? AppTheme.primary
                              : AppTheme.textSub,
                          size: 20,
                        ),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.cancel,
                                    color: AppTheme.textSub, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                  _searchFocus.unfocus();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),

                // ─────────────────────────────────────────
                // 친구 목록
                // ─────────────────────────────────────────
                Expanded(
                  child: friendsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    ),
                    error: (e, _) => Center(
                      child: Text('오류: $e',
                          style: TextStyle(color: AppTheme.textSub)),
                    ),
                    data: (friends) {
                      final filtered = _search.isEmpty
                          ? friends
                          : friends
                              .where((f) => f.nickname
                                  .toLowerCase()
                                  .contains(_search.toLowerCase()))
                              .toList();

                      // 즐겨찾기 / 일반 분리
                      final favorites =
                          filtered.where((f) => f.isFavorite).toList();
                      final others =
                          filtered.where((f) => !f.isFavorite).toList();

                      return CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          // 추천 친구
                          if (_search.isEmpty &&
                              suggestions.isNotEmpty)
                            SliverToBoxAdapter(
                              child: SuggestionsSection(
                                suggestions: suggestions,
                                onTap: _openSuggestedProfile,
                                onAdd: _sendSuggestionRequest,
                                onDismiss: _dismissSuggestion,
                              ),
                            ),

                          // 즐겨찾기 섹션
                          if (favorites.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: _SectionHeader(
                                icon: Icons.star_rounded,
                                iconColor: const Color(0xFFFBBF24),
                                title: '즐겨찾기',
                                count: favorites.length,
                              ),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) {
                                  final friend = favorites[i];
                                  return FriendTile(
                                    friend: friend,
                                    onTap: () => _openProfile(friend),
                                    onChat: () => _startChat(friend),
                                    onToggleFavorite: () =>
                                        _toggleFavorite(friend),
                                    onReport: () =>
                                        _showReportSheet(friend),
                                    onBlock: () => _showBlockConfirm(
                                        friend.friendId,
                                        friend.nickname),
                                    onRemove: () =>
                                        _confirmRemoveFriend(friend),
                                  );
                                },
                                childCount: favorites.length,
                              ),
                            ),
                          ],

                          // 친구 목록 헤더
                          if (others.isNotEmpty || filtered.isEmpty)
                            SliverToBoxAdapter(
                              child: _SectionHeader(
                                icon: Icons.people_rounded,
                                iconColor: AppTheme.textSub,
                                title: '친구',
                                count: filtered.isEmpty
                                    ? friends.length
                                    : others.length,
                              ),
                            ),

                          // 친구 타일들 / 빈 상태
                          if (filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(
                                        20, 24, 20, 60),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: AppTheme.bgCard,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          _search.isNotEmpty
                                              ? Icons.search_off_rounded
                                              : Icons.people_outline_rounded,
                                          color: AppTheme.textSub,
                                          size: 38,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        _search.isNotEmpty
                                            ? '검색 결과가 없어요'
                                            : '아직 친구가 없어요',
                                        style: TextStyle(
                                          color: AppTheme.textMain,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _search.isNotEmpty
                                            ? '"$_search"와 일치하는 친구를 찾지 못했어요'
                                            : '친구를 추가하고 대화를 시작해보세요',
                                        style: TextStyle(
                                          color: AppTheme.textSub,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (_search.isEmpty) ...[
                                        const SizedBox(height: 20),
                                        ElevatedButton.icon(
                                          onPressed:
                                              _showAddFriendDialog,
                                          icon: const Icon(
                                              Icons.person_add_rounded,
                                              size: 18),
                                          label: const Text('친구 추가하기'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppTheme.primary,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 20,
                                                vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      12),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) {
                                  final friend = others[i];
                                  return FriendTile(
                                    friend: friend,
                                    onTap: () => _openProfile(friend),
                                    onChat: () => _startChat(friend),
                                    onToggleFavorite: () =>
                                        _toggleFavorite(friend),
                                    onReport: () =>
                                        _showReportSheet(friend),
                                    onBlock: () => _showBlockConfirm(
                                        friend.friendId,
                                        friend.nickname),
                                    onRemove: () =>
                                        _confirmRemoveFriend(friend),
                                  );
                                },
                                childCount: others.length,
                              ),
                            ),

                          // 하단 여백
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 80)),
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
            child: Container(color: Colors.black.withOpacity(0.5)),
          ),

        // ── ✨ 사이드 패널 ──
        if (_isPanelOpen)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 280,
            child: SlideTransition(
              position: _panelAnimation,
              child: Material(
                color: AppTheme.bg,
                elevation: 20,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 헤더
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 20, 12, 8),
                        child: Row(
                          children: [
                            Text(
                              '메뉴',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textMain,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const Spacer(),
                            _CircleIconButton(
                              icon: Icons.close_rounded,
                              onTap: _closePanel,
                            ),
                          ],
                        ),
                      ),

                      // 미니 프로필 카드
                      myProfileAsync.maybeWhen(
                        data: (prof) {
                          if (prof == null) return const SizedBox();
                          final nickname =
                              prof['nickname'] as String? ?? '';
                          final avatar =
                              prof['avatar_url'] as String?;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  AvatarWidget(
                                      url: avatar,
                                      name: nickname,
                                      size: 40),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nickname,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textMain,
                                          ),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '내 프로필',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSub,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        orElse: () => const SizedBox(),
                      ),

                      Divider(
                          color: AppTheme.border,
                          height: 1,
                          indent: 16,
                          endIndent: 16),
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

// ═══════════════════════════════════════════════
// ✨ 보조 위젯들
// ═══════════════════════════════════════════════

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppTheme.textMain, size: 20),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSub,
            ),
          ),
        ],
      ),
    );
  }
}