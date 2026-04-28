import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/skeleton_widget.dart';
import '../../friends/screens/friends_screen.dart';
import '../../group_chat/providers/group_chat_provider.dart';
import '../../group_chat/screens/group_chat_room_screen.dart';
import '../models/chat_room_model.dart';
import '../providers/chat_provider.dart' as provider;

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  OverlayEntry? _overlayEntry;
  
  // ✨ 시간 표시 자동 갱신용 타이머
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _listenForIncomingMessages();
    
    // ✨ 30초마다 UI 갱신 → "방금 → 1분 전 → 2분 전" 자동 업데이트
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listenForIncomingMessages() {
    Supabase.instance.client
        .channel('inbox_$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kyorangtalk_messages',
          callback: (payload) async {
            final row      = payload.newRecord;
            if (row.isEmpty) return;
            final senderId = row['sender_id'] as String?;
            final roomId   = row['room_id']   as String?;
            final content  = row['content']   as String? ?? '';

            if (senderId == null) return;
            if (senderId == _myId) return;
            if (provider.currentOpenRoomId == roomId) return;

            try {
              // ✨ 1. 전역 알림 설정 확인 (Supabase 직접 조회)
              final prefsData = await Supabase.instance.client
                  .from('kyorangtalk_notification_prefs')
                  .select(
                      'notifications_enabled, message_preview_enabled')
                  .eq('user_id', _myId)
                  .maybeSingle();

              final notificationsEnabled =
                  prefsData?['notifications_enabled'] as bool? ?? true;
              final messagePreviewEnabled =
                  prefsData?['message_preview_enabled'] as bool? ?? true;

              if (!notificationsEnabled) {
                print('🔕 전역 알림 꺼짐 - 앱 내 배너 차단');
                return;
              }

              // ✨ 2. 개별 방 음소거 확인
              final muted =
                  await NotificationService.isMuted(roomId: roomId);
              if (muted) {
                print('🔕 방 음소거 - 앱 내 배너 차단: $roomId');
                return;
              }

              if (!mounted) return;

              // ✨ 3. 차단 여부 확인
              final blockCheck = await Supabase.instance.client
                  .from('kyorangtalk_blocks')
                  .select('id')
                  .eq('blocker_id', _myId)
                  .eq('blocked_id', senderId)
                  .maybeSingle();

              if (blockCheck != null) {
                print('🚫 차단한 사용자 - 앱 내 배너 차단');
                return;
              }

              if (!mounted) return;

              // 프로필 조회 후 배너 표시
              final profile = await Supabase.instance.client
                  .from('kyorangtalk_profiles')
                  .select('nickname')
                  .eq('id', senderId)
                  .maybeSingle();

              if (!mounted) return;
              final nickname =
                  profile?['nickname'] as String? ?? '누군가';
              final rooms =
                  ref.read(provider.chatRoomsProvider).value ?? [];
              final room = rooms
                  .where((r) => r.roomId == roomId)
                  .firstOrNull;

              if (room != null) {
                // ✨ 4. 메시지 미리보기 설정 반영
                final displayContent = messagePreviewEnabled
                    ? content
                    : '새 메시지가 도착했어요';

                _showOverlayNotification(
                    nickname, displayContent, room);
              }
            } catch (e) {
              print('⚠️ 앱 내 알림 처리 실패: $e');
            }
          },
        )
        .subscribe();
  }

  void _showOverlayNotification(
      String senderName, String content, ChatRoomModel room) {
    _overlayEntry?.remove();
    _overlayEntry = null;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _TopNotificationBanner(
        senderName: senderName,
        content: content,
        room: room,
        onTap: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
          context.push('/main/chat/${room.roomId}', extra: room);
        },
        onDismiss: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    Future.delayed(const Duration(seconds: 4), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _searchController.dispose();
    _overlayEntry?.remove();
    Supabase.instance.client.channel('inbox_$_myId').unsubscribe();
    super.dispose();
  }

  // ✨ 시간 표시 함수 - UTC 기준 비교로 완전히 정확하게!
  String _timeAgo(DateTime dt) {
    // UTC 기준으로 통일해서 비교 (시간대 문제 완전 방지)
    final nowUtc = DateTime.now().toUtc();
    final dtUtc = dt.isUtc ? dt : dt.toUtc();
    var diff = nowUtc.difference(dtUtc);
    
    // 미래 시간 방어 (시계 차이/동기화 문제)
    if (diff.isNegative) {
      diff = Duration.zero;
    }
    
    // 60초 미만 → "방금"
    if (diff.inSeconds < 60) return '방금';
    // 1시간 미만 → "N분 전"
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    // 24시간 미만 → "N시간 전"
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    // 7일 미만 → "N일 전"
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    // 그 이상 → "M/D" 날짜 표시
    final local = dt.isUtc ? dt.toLocal() : dt;
    return DateFormat('M/d').format(local);
  }

  void _showNewChatSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewChatSheet(
        myId: _myId,
        onChatCreated: (room, isGroup) {
          Navigator.pop(context);
          if (isGroup) {
            ref.invalidate(groupRoomsProvider);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupChatRoomScreen(room: room),
              ),
            );
          } else {
            ref.invalidate(provider.chatRoomsProvider);
            context.push('/main/chat/${room.roomId}', extra: room);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync  = ref.watch(provider.chatRoomsProvider);
    final mutedAsync  = ref.watch(mutedRoomsProvider);
    final mutedRooms  = mutedAsync.value ?? {};

    final totalUnread = roomsAsync.value
            ?.where((r) => !mutedRooms.contains(r.roomId))
            .fold(0, (s, r) => s + r.unreadCount) ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('메시지',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain)),
                      if (totalUnread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Text('$totalUnread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                      const Spacer(),
                      GestureDetector(
                        onTap: _showNewChatSheet,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.edit_square,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
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
                        hintText: '대화 검색...',
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
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
                ],
              ),
            ),

            Expanded(
              child: roomsAsync.when(
                loading: () => const ChatListSkeleton(),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: AppTheme.textSub, size: 40),
                      const SizedBox(height: 12),
                      Text('불러오기 실패',
                          style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 14)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(provider.chatRoomsProvider),
                        child: const Text('다시 시도',
                            style: TextStyle(
                                color: AppTheme.primary)),
                      ),
                    ],
                  ),
                ),
                data: (rooms) {
                  final filtered = _search.isEmpty
                      ? rooms
                      : rooms
                          .where((r) =>
                              r.partnerName
                                  .toLowerCase()
                                  .contains(
                                      _search.toLowerCase()) ||
                              r.partnerUsername
                                  .toLowerCase()
                                  .contains(
                                      _search.toLowerCase()))
                          .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          const Text('💬',
                              style:
                                  TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          Text(
                            _search.isNotEmpty
                                ? '"$_search" 검색 결과가 없어요'
                                : '아직 대화가 없어요',
                            style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 14),
                          ),
                          if (_search.isEmpty) ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _showNewChatSheet,
                              icon: const Icon(
                                  Icons.edit_square,
                                  color: AppTheme.primary,
                                  size: 18),
                              label: const Text('새 채팅 시작하기',
                                  style: TextStyle(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final room = filtered[i];
                      final isMuted =
                          mutedRooms.contains(room.roomId);
                      final isUnread =
                          room.unreadCount > 0 && !isMuted;

                      return InkWell(
                        onTap: () {
                          provider.currentOpenRoomId = room.roomId;
                          context
                              .push(
                                '/main/chat/${room.roomId}',
                                extra: room,
                              )
                              .then((_) {
                                provider.currentOpenRoomId = null;
                                ref.invalidate(mutedRoomsProvider);
                              });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isUnread
                                ? AppTheme.primary.withOpacity(0.08)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                  color: AppTheme.border),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.center,
                            children: [
                              AvatarWidget(
                                url: room.partnerAvatar,
                                name: room.partnerName,
                                size: 50,
                              ),
                              const SizedBox(width: 14),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            room.partnerName,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isUnread
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: AppTheme
                                                  .textMain,
                                            ),
                                            overflow: TextOverflow
                                                .ellipsis,
                                          ),
                                        ),
                                        if (isMuted) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                              Icons
                                                  .notifications_off,
                                              color: AppTheme
                                                  .textSub,
                                              size: 13),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      room.lastMessage.isEmpty
                                          ? '대화를 시작해보세요'
                                          : room.lastMessage,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isUnread
                                            ? AppTheme.textMain
                                            : AppTheme.textSub,
                                        fontWeight: isUnread
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _timeAgo(room.lastTime),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isUnread
                                          ? const Color(
                                              0xFFEF4444)
                                          : AppTheme.textMuted,
                                      fontWeight: isUnread
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (room.unreadCount > 0)
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 6,
                                          vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isMuted
                                            ? AppTheme.textSub
                                            : const Color(
                                                0xFFEF4444),
                                        borderRadius:
                                            BorderRadius.circular(
                                                10),
                                      ),
                                      constraints:
                                          const BoxConstraints(
                                        minWidth: 20,
                                        minHeight: 18,
                                      ),
                                      child: Text(
                                        '${room.unreadCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight:
                                              FontWeight.w800,
                                        ),
                                        textAlign:
                                            TextAlign.center,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 18),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
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

class _NewChatSheet extends ConsumerStatefulWidget {
  final String myId;
  final void Function(dynamic room, bool isGroup) onChatCreated;

  const _NewChatSheet({
    required this.myId,
    required this.onChatCreated,
  });

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _searchController = TextEditingController();
  final _groupNameController = TextEditingController();
  String _search = '';
  final Set<String> _selectedIds = {};
  bool _creating = false;
  bool _showGroupNameInput = false;

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  void _toggleSelect(String friendId) {
    setState(() {
      if (_selectedIds.contains(friendId)) {
        _selectedIds.remove(friendId);
      } else {
        _selectedIds.add(friendId);
      }
    });
  }

  Future<void> _createChat(List<FriendModel> allFriends) async {
    if (_selectedIds.isEmpty || _creating) return;

    if (_selectedIds.length == 1) {
      setState(() => _creating = true);
      await _create1on1(allFriends);
      return;
    }

    if (!_showGroupNameInput) {
      setState(() => _showGroupNameInput = true);
      return;
    }

    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      _showSnack('채팅방 이름을 입력해주세요');
      return;
    }

    setState(() => _creating = true);
    await _createGroup(name, allFriends);
  }

  Future<void> _create1on1(List<FriendModel> allFriends) async {
    try {
      final friendId = _selectedIds.first;
      final friend = allFriends.firstWhere((f) => f.friendId == friendId);
      final supabase = Supabase.instance.client;

      final existing = await supabase
          .from('kyorangtalk_rooms')
          .select('*')
          .or('and(user1_id.eq.${widget.myId},user2_id.eq.$friendId),'
              'and(user1_id.eq.$friendId,user2_id.eq.${widget.myId})')
          .maybeSingle();

      String roomId;
      if (existing != null) {
        roomId = existing['id'] as String;
        final hiddenBy = (existing['hidden_by'] as List?)?.cast<String>() ?? [];
        if (hiddenBy.contains(widget.myId)) {
          hiddenBy.remove(widget.myId);
          await supabase
              .from('kyorangtalk_rooms')
              .update({'hidden_by': hiddenBy})
              .eq('id', roomId);
        }
      } else {
        final newRoom = await supabase
            .from('kyorangtalk_rooms')
            .insert({
              'user1_id': widget.myId,
              'user2_id': friendId,
            })
            .select()
            .single();
        roomId = newRoom['id'] as String;
      }

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

      if (mounted) widget.onChatCreated(room, false);
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        _showSnack('채팅방 생성 실패: $e');
      }
    }
  }

  Future<void> _createGroup(String name, List<FriendModel> allFriends) async {
    try {
      final memberIds = _selectedIds.toList();

      final room = await createGroupRoom(
        name: name,
        roomType: 'group',
        memberIds: memberIds,
        category: '친구',
      );

      if (room != null && mounted) {
        widget.onChatCreated(room, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        _showSnack('그룹 채팅방 생성 실패: $e');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final isGroup = _selectedIds.length >= 2;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
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
            child: Row(
              children: [
                Text(
                  _showGroupNameInput ? '채팅방 이름' : '새 채팅',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
                const Spacer(),
                if (_selectedIds.isNotEmpty && !_showGroupNameInput)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIds.length}명 선택',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_showGroupNameInput) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedIds.length}명과의 그룹 채팅',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSub,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: TextField(
                      controller: _groupNameController,
                      autofocus: true,
                      maxLength: 30,
                      style: TextStyle(color: AppTheme.textMain),
                      decoration: InputDecoration(
                        hintText: '채팅방 이름 입력 (예: 우리 가족)',
                        hintStyle: TextStyle(color: AppTheme.textSub),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ] else ...[
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
                      final isSelected =
                          _selectedIds.contains(friend.friendId);

                      return InkWell(
                        onTap: () => _toggleSelect(friend.friendId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          color: isSelected
                              ? AppTheme.primary.withOpacity(0.08)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : AppTheme.border,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                        color: Colors.white,
                                        size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              AvatarWidget(
                                url: friend.avatarUrl,
                                name: friend.nickname,
                                size: 42,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(friend.nickname,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight.w600,
                                            color: AppTheme
                                                .textMain)),
                                    if (friend.statusMessage != null &&
                                        friend.statusMessage!
                                            .isNotEmpty)
                                      Text(friend.statusMessage!,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme
                                                  .textSub),
                                          maxLines: 1,
                                          overflow: TextOverflow
                                              .ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                border: Border(
                    top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  if (_showGroupNameInput) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _creating
                            ? null
                            : () => setState(
                                () => _showGroupNameInput = false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          side: BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text('뒤로',
                            style: TextStyle(
                                color: AppTheme.textMain,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: _showGroupNameInput ? 2 : 1,
                    child: ElevatedButton(
                      onPressed: (_selectedIds.isEmpty || _creating)
                          ? null
                          : () {
                              final friends = friendsAsync.value ?? [];
                              _createChat(friends);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedIds.isEmpty
                            ? AppTheme.border
                            : AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              _showGroupNameInput
                                  ? '채팅방 만들기'
                                  : isGroup
                                      ? '다음 (${_selectedIds.length}명)'
                                      : _selectedIds.isEmpty
                                          ? '친구를 선택해주세요'
                                          : '채팅 시작',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNotificationBanner extends StatefulWidget {
  final String senderName;
  final String content;
  final ChatRoomModel room;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _TopNotificationBanner({
    required this.senderName,
    required this.content,
    required this.room,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationBanner> createState() =>
      _TopNotificationBannerState();
}

class _TopNotificationBannerState
    extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnim,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  AvatarWidget(
                    url: widget.room.partnerAvatar,
                    name: widget.room.partnerName,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.senderName,
                            style: TextStyle(
                                color: AppTheme.textMain,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          widget.content.length > 40
                              ? '${widget.content.substring(0, 40)}...'
                              : widget.content,
                          style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close,
                        color: AppTheme.textSub, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}