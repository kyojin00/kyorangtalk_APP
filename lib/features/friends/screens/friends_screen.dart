import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/chat/models/chat_room_model.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/profile/screens/user_profile_screen.dart';
import '../../../features/profile/screens/my_profile_screen.dart';

class FriendModel {
  final String id;
  final String requesterId;
  final String receiverId;
  final String status;
  final String friendId;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;

  FriendModel({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.friendId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
  });
}

class SuggestedFriend {
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;
  final int mutualCount;
  final List<String> mutualNicknames;

  SuggestedFriend({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
    required this.mutualCount,
    required this.mutualNicknames,
  });
}

final myProfileProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;
  return await supabase
      .from('kyorangtalk_profiles')
      .select('nickname, avatar_url, status_message')
      .eq('id', myId)
      .maybeSingle();
});

final friendsProvider = FutureProvider<List<FriendModel>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .or('requester_id.eq.$myId,receiver_id.eq.$myId')
      .eq('status', 'accepted')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final friendIds = data.map((f) {
    return f['requester_id'] == myId
        ? f['receiver_id'] as String
        : f['requester_id'] as String;
  }).toList();

  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .inFilter('id', friendIds);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  final subProfiles = await supabase
      .from('kyorangtalk_sub_profiles')
      .select('''
        user_id, nickname, avatar_url, status_message,
        kyorangtalk_sub_profile_viewers!inner(viewer_id)
      ''')
      .inFilter('user_id', friendIds)
      .eq('kyorangtalk_sub_profile_viewers.viewer_id', myId);

  final subProfileMap = <String, Map<String, dynamic>>{};
  for (final sp in subProfiles) {
    subProfileMap[sp['user_id'] as String] = sp;
  }

  return data.map((f) {
    final friendId = f['requester_id'] == myId
        ? f['receiver_id'] as String
        : f['requester_id'] as String;
    final mainProf = profileMap[friendId];
    final subProf = subProfileMap[friendId];

    final nickname = subProf != null
        ? (subProf['nickname'] as String? ?? mainProf?['nickname'] as String? ?? '알 수 없음')
        : (mainProf?['nickname'] as String? ?? '알 수 없음');
    
    final avatarUrl = subProf != null
        ? subProf['avatar_url'] as String?
        : mainProf?['avatar_url'] as String?;

    final statusMessage = subProf != null
        ? subProf['status_message'] as String?
        : mainProf?['status_message'] as String?;

    return FriendModel(
      id:            f['id'] as String,
      requesterId:   f['requester_id'] as String,
      receiverId:    f['receiver_id'] as String,
      status:        f['status'] as String,
      friendId:      friendId,
      nickname:      nickname,
      avatarUrl:     avatarUrl,
      statusMessage: statusMessage,
    );
  }).toList();
});

final friendSuggestionsProvider =
    FutureProvider<List<SuggestedFriend>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final myRelations = await supabase
      .from('kyorangtalk_friends')
      .select('requester_id, receiver_id, status')
      .or('requester_id.eq.$myId,receiver_id.eq.$myId');

  final myFriendIds = <String>{};
  final excludeIds = <String>{myId};

  for (final r in myRelations) {
    final reqId = r['requester_id'] as String;
    final recId = r['receiver_id'] as String;
    final status = r['status'] as String;
    final otherId = reqId == myId ? recId : reqId;

    excludeIds.add(otherId);
    if (status == 'accepted') {
      myFriendIds.add(otherId);
    }
  }

  if (myFriendIds.isEmpty) return [];

  final friendsOfFriends = await supabase
      .from('kyorangtalk_friends')
      .select('requester_id, receiver_id')
      .or(myFriendIds
          .map((fid) =>
              'requester_id.eq.$fid,receiver_id.eq.$fid')
          .join(','))
      .eq('status', 'accepted');

  final candidateMap = <String, Set<String>>{};

  for (final fof in friendsOfFriends) {
    final reqId = fof['requester_id'] as String;
    final recId = fof['receiver_id'] as String;

    String? mutualFriendId;
    String? candidateId;

    if (myFriendIds.contains(reqId) && !excludeIds.contains(recId)) {
      mutualFriendId = reqId;
      candidateId = recId;
    } else if (myFriendIds.contains(recId) && !excludeIds.contains(reqId)) {
      mutualFriendId = recId;
      candidateId = reqId;
    }

    if (candidateId != null && mutualFriendId != null) {
      candidateMap
          .putIfAbsent(candidateId, () => <String>{})
          .add(mutualFriendId);
    }
  }

  if (candidateMap.isEmpty) return [];

  final candidateIds = candidateMap.keys.toList();
  final mutualFriendIds = <String>{};
  for (final mutuals in candidateMap.values) {
    mutualFriendIds.addAll(mutuals);
  }

  final allIds = [...candidateIds, ...mutualFriendIds];

  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .inFilter('id', allIds);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  final suggestions = candidateMap.entries.map((entry) {
    final candidateId = entry.key;
    final mutuals = entry.value;
    final prof = profileMap[candidateId];

    final mutualNicknames = mutuals
        .map((id) => profileMap[id]?['nickname'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return SuggestedFriend(
      userId:          candidateId,
      nickname:        prof?['nickname'] as String? ?? '알 수 없음',
      avatarUrl:       prof?['avatar_url'] as String?,
      statusMessage:   prof?['status_message'] as String?,
      mutualCount:     mutuals.length,
      mutualNicknames: mutualNicknames,
    );
  }).toList();

  suggestions.sort((a, b) => b.mutualCount.compareTo(a.mutualCount));

  return suggestions.take(10).toList();
});

final pendingRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .eq('receiver_id', myId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final ids = data.map((r) => r['requester_id'] as String).toList();
  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url')
      .inFilter('id', ids);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  return data.map((r) {
    final prof = profileMap[r['requester_id']];
    return {
      ...r,
      'nickname':   prof?['nickname'] ?? '알 수 없음',
      'avatar_url': prof?['avatar_url'],
    };
  }).toList();
});

final sentRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .eq('requester_id', myId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final ids = data.map((r) => r['receiver_id'] as String).toList();
  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url')
      .inFilter('id', ids);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  return data.map((r) {
    final prof = profileMap[r['receiver_id']];
    return {
      ...r,
      'nickname':   prof?['nickname'] ?? '알 수 없음',
      'avatar_url': prof?['avatar_url'],
    };
  }).toList();
});

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

  void _openPanel() {
    setState(() => _isPanelOpen = true);
    _panelController.forward();
  }

  void _closePanel() {
    _panelController.reverse().then((_) {
      if (mounted) setState(() => _isPanelOpen = false);
    });
  }

  void _invalidateAll() {
    ref.invalidate(friendsProvider);
    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(sentRequestsProvider);
    ref.invalidate(myProfileProvider);
    ref.invalidate(friendSuggestionsProvider);
  }

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

    // 친구 관계 삭제
    await supabase
        .from('kyorangtalk_friends')
        .delete()
        .or('and(requester_id.eq.$_myId,receiver_id.eq.$friendId),'
            'and(requester_id.eq.$friendId,receiver_id.eq.$_myId)');

    // 차단 테이블에 추가
    await supabase.from('kyorangtalk_blocks').insert({
      'blocker_id': _myId,
      'blocked_id': friendId,
    });

    _invalidateAll();
    // ✨ 채팅 목록도 새로고침
    ref.invalidate(chatRoomsProvider);

    if (mounted) _showSnack('$nickname님을 차단했어요');
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

  void _showAddFriendDialog() {
    _closePanel();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddFriendSheet(
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
      builder: (ctx) => Consumer(
        builder: (_, ref, __) {
          final pendingAsync = ref.watch(pendingRequestsProvider);
          final sentAsync    = ref.watch(sentRequestsProvider);
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                _sheetHandle(),
                Expanded(
                  child: ListView(
                    controller: sc,
                    children: [
                      _sectionTitle('받은 요청',
                          badge: pendingAsync.value?.length ?? 0),
                      pendingAsync.when(
                        loading: () => _loadingWidget(),
                        error: (_, __) => const SizedBox(),
                        data: (requests) => requests.isEmpty
                            ? _emptyText('받은 요청이 없어요')
                            : Column(
                                children: requests.map((req) {
                                  return _RequestTile(
                                    request: req,
                                    onAccept: () {
                                      _acceptRequest(req['id'] as String);
                                      Navigator.pop(ctx);
                                    },
                                    onReject: () =>
                                        _rejectRequest(req['id'] as String),
                                  );
                                }).toList(),
                              ),
                      ),
                      Divider(color: AppTheme.border),
                      _sectionTitle('보낸 요청'),
                      sentAsync.when(
                        loading: () => _loadingWidget(),
                        error: (_, __) => const SizedBox(),
                        data: (sent) => sent.isEmpty
                            ? _emptyText('보낸 요청이 없어요')
                            : Column(
                                children: sent.map((req) {
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
                                          url: req['avatar_url'] as String?,
                                          name: req['nickname'] as String?,
                                          size: 42,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                req['nickname'] as String? ??
                                                    '알 수 없음',
                                                style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.textMain),
                                              ),
                                              Text('대기 중',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppTheme.textSub)),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => _cancelRequest(
                                              req['id'] as String),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFEF4444),
                                          ),
                                          child: const Text('취소',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
      builder: (ctx) => _FriendManageSheet(
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

  Widget _sheetHandle() => Container(
        width: 36, height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _sectionTitle(String title, {int badge = 0}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain)),
            if (badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      );

  Widget _loadingWidget() => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );

  Widget _emptyText(String msg) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text(msg,
            style: TextStyle(
                color: AppTheme.textSub, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final pendingAsync = ref.watch(pendingRequestsProvider);
    final myProfileAsync = ref.watch(myProfileProvider);
    final suggestionsAsync = ref.watch(friendSuggestionsProvider);
    final pendingCount = pendingAsync.value?.length ?? 0;

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
                                url: avatar,
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
                                          color: AppTheme
                                              .textMain)),
                                  if (statusMessage != null &&
                                      statusMessage.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(statusMessage,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme
                                                .textSub),
                                        maxLines: 1,
                                        overflow: TextOverflow
                                            .ellipsis),
                                  ],
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: AppTheme.textSub,
                                size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
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

                Expanded(
                  child: friendsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    ),
                    error: (e, _) => Center(
                      child: Text('오류: $e',
                          style: TextStyle(
                              color: AppTheme.textSub)),
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
                          if (_search.isEmpty && suggestions.isNotEmpty)
                            SliverToBoxAdapter(
                              child: _SuggestionsSection(
                                suggestions: suggestions,
                                onTap: _openSuggestedProfile,
                                onAdd: _sendSuggestionRequest,
                                onDismiss: _dismissSuggestion,
                              ),
                            ),

                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 12, 20, 4),
                              child: Row(
                                children: [
                                  Text('친구 목록',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSub,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  Text('${friends.length}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSub,
                                          fontWeight: FontWeight.w700)),
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
                                        style: TextStyle(fontSize: 48)),
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
                                        onPressed: _showAddFriendDialog,
                                        icon: const Icon(
                                            Icons.person_add_outlined,
                                            color: AppTheme.primary,
                                            size: 18),
                                        label: const Text('친구 추가',
                                            style: TextStyle(
                                                color: AppTheme.primary)),
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
                                  return _FriendTile(
                                    friend: friend,
                                    onTap:  () => _openProfile(friend),
                                    onChat: () => _startChat(friend),
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

        if (_isPanelOpen)
          GestureDetector(
            onTap: _closePanel,
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),

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
                        padding:
                            const EdgeInsets.fromLTRB(20, 20, 16, 16),
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
                                  color: AppTheme.textSub, size: 20),
                              onPressed: _closePanel,
                            ),
                          ],
                        ),
                      ),
                      Divider(color: AppTheme.border, height: 1),
                      const SizedBox(height: 8),
                      _PanelMenuItem(
                        icon: Icons.person_add_outlined,
                        label: '친구 추가',
                        onTap: _showAddFriendDialog,
                      ),
                      _PanelMenuItem(
                        icon: Icons.mark_email_unread_outlined,
                        label: '친구 요청함',
                        badge: pendingCount,
                        onTap: _showRequestsSheet,
                      ),
                      _PanelMenuItem(
                        icon: Icons.people_outlined,
                        label: '친구 관리',
                        onTap: () {
                          _closePanel();
                          _showFriendManageSheet();
                        },
                      ),
                      _PanelMenuItem(
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

class _SuggestionsSection extends StatelessWidget {
  final List<SuggestedFriend> suggestions;
  final void Function(SuggestedFriend) onTap;
  final void Function(SuggestedFriend) onAdd;
  final void Function(String) onDismiss;

  const _SuggestionsSection({
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
                onTap:      () => onTap(s),
                onAdd:      () => onAdd(s),
                onDismiss:  () => onDismiss(s.userId),
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
        ? '${suggestion.mutualNicknames.first}${suggestion.mutualCount > 1 ? ' 외 ${suggestion.mutualCount - 1}명' : ''}과 친구'
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
                      fontSize: 10.5,
                      color: AppTheme.textSub),
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
                    border: Border.all(
                        color: AppTheme.border),
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

class _AddFriendSheet extends ConsumerStatefulWidget {
  final String myId;
  final VoidCallback onSent;

  const _AddFriendSheet({
    required this.myId,
    required this.onSent,
  });

  @override
  ConsumerState<_AddFriendSheet> createState() =>
      _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _searching = false;
  bool _sending = false;
  Map<String, dynamic>? _foundUser;
  String? _friendStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _foundUser = null;
          _friendStatus = null;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _toE164(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      return '+82${digits.substring(1)}';
    }
    return '+82$digits';
  }

  bool _isValidKoreanPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^010\d{8}$').hasMatch(digits);
  }

  Future<void> _searchByNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() {
      _searching = true;
      _foundUser = null;
      _friendStatus = null;
      _error = null;
    });

    final supabase = Supabase.instance.client;

    final profile = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url, status_message')
        .eq('nickname', nickname)
        .neq('id', widget.myId)
        .maybeSingle();

    if (profile == null) {
      setState(() {
        _searching = false;
        _error = '해당 닉네임의 유저를 찾을 수 없어요';
      });
      return;
    }

    await _loadFriendStatus(profile);
  }

  Future<void> _searchByPhone() async {
    final phoneText = _phoneController.text.trim();
    if (!_isValidKoreanPhone(phoneText)) {
      setState(() {
        _error = '올바른 전화번호를 입력해주세요 (010으로 시작)';
      });
      return;
    }

    setState(() {
      _searching = true;
      _foundUser = null;
      _friendStatus = null;
      _error = null;
    });

    final phoneE164 = _toE164(phoneText);
    final supabase = Supabase.instance.client;

    final profile = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url, status_message, phone_number')
        .eq('phone_number', phoneE164)
        .neq('id', widget.myId)
        .maybeSingle();

    if (profile == null) {
      setState(() {
        _searching = false;
        _error = '해당 전화번호로 가입한 유저가 없어요';
      });
      return;
    }

    await _loadFriendStatus(profile);
  }

  Future<void> _loadFriendStatus(Map<String, dynamic> profile) async {
    final supabase = Supabase.instance.client;

    final existing = await supabase
        .from('kyorangtalk_friends')
        .select('status, requester_id')
        .or('and(requester_id.eq.${widget.myId},receiver_id.eq.${profile['id']}),'
            'and(requester_id.eq.${profile['id']},receiver_id.eq.${widget.myId})')
        .maybeSingle();

    setState(() {
      _searching = false;
      _foundUser = profile;
      _friendStatus = existing?['status'] as String? ?? 'none';
    });
  }

  Future<void> _sendRequest() async {
    if (_foundUser == null || _sending) return;

    setState(() => _sending = true);

    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .insert({
      'requester_id': widget.myId,
      'receiver_id': _foundUser!['id'],
      'status': 'pending',
    });

    setState(() {
      _friendStatus = 'pending';
      _sending = false;
    });

    widget.onSent();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_foundUser!['nickname']}님에게 친구 요청을 보냈어요!'),
          backgroundColor: AppTheme.bgCard,
        ),
      );
    }
  }

  Widget _buildActionButton() {
    switch (_friendStatus) {
      case 'accepted':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, color: AppTheme.primary, size: 16),
              SizedBox(width: 6),
              Text('이미 친구예요',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
      case 'pending':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text('요청 중',
              style: TextStyle(
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600)),
        );
      case 'blocked':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('차단된 유저',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700)),
        );
      default:
        return GestureDetector(
          onTap: _sending ? null : _sendRequest,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_outlined,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('친구 요청 보내기',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('친구 추가',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSub,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.alternate_email, size: 14),
                          SizedBox(width: 4),
                          Text('닉네임'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('전화번호'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 68,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNicknameInput(),
                    _buildPhoneInput(),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFEF4444), fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              if (_foundUser != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      AvatarWidget(
                        url: _foundUser!['avatar_url'] as String?,
                        name: _foundUser!['nickname'] as String?,
                        size: 72,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _foundUser!['nickname'] as String? ?? '알 수 없음',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain),
                      ),
                      if (_foundUser!['status_message'] != null &&
                          (_foundUser!['status_message'] as String)
                              .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _foundUser!['status_message'] as String,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSub),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildActionButton(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNicknameInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: TextField(
              controller: _nicknameController,
              autofocus: true,
              style: TextStyle(color: AppTheme.textMain),
              decoration: InputDecoration(
                hintText: '닉네임 입력',
                hintStyle: TextStyle(color: AppTheme.textSub),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
              onSubmitted: (_) => _searchByNickname(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _searching ? null : _searchByNickname,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _searching
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('검색',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Text('🇰🇷', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text('+82',
                    style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                    width: 1, height: 16, color: AppTheme.border),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w600),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                      _PhoneFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: '010-0000-0000',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _searchByPhone(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _searching ? null : _searchByPhone,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _searching
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('검색',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    String formatted = digits;

    if (digits.length > 3 && digits.length <= 7) {
      formatted = '${digits.substring(0, 3)}-${digits.substring(3)}';
    } else if (digits.length > 7 && digits.length <= 11) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length > 11) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, 11)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _FriendManageSheet extends ConsumerStatefulWidget {
  final String myId;
  final void Function(String friendId) onRemove;
  final void Function(String friendId, String nickname) onBlock;

  const _FriendManageSheet({
    required this.myId,
    required this.onRemove,
    required this.onBlock,
  });

  @override
  ConsumerState<_FriendManageSheet> createState() =>
      _FriendManageSheetState();
}

class _FriendManageSheetState extends ConsumerState<_FriendManageSheet> {
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
                      style: TextStyle(
                          color: AppTheme.textSub))),
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
                                      overflow: TextOverflow.ellipsis),
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
                                            color: Color(0xFFEF4444),
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

class _PanelMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _PanelMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSub, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w500)),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onTap;
  final VoidCallback onChat;

  const _FriendTile({
    required this.friend,
    required this.onTap,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            AvatarWidget(
                url: friend.avatarUrl,
                name: friend.nickname,
                size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                            fontSize: 12, color: AppTheme.textSub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            GestureDetector(
              onTap: onChat,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppTheme.primary, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          AvatarWidget(
            url: request['avatar_url'] as String?,
            name: request['nickname'] as String?,
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                request['nickname'] as String? ?? '알 수 없음',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain)),
          ),
          GestureDetector(
            onTap: onReject,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close,
                  color: AppTheme.textSub, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAccept,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('수락',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}