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

// ═══════════════════════════════════════════════════
// 💬 ChatListScreen
//
// ⭐ 실시간 동기화:
//   - 새 메시지 INSERT → provider invalidate + 배너
//   - 메시지 UPDATE (is_read 등) → provider invalidate
//   - 방 정보 변경 → provider invalidate
//   - 디바운스로 과도한 invalidate 방지
// ═══════════════════════════════════════════════════

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _search = '';
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  OverlayEntry? _overlayEntry;

  Timer? _uiRefreshTimer;
  Timer? _invalidateDebouncer;

  // ⭐ 실시간 채널들
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _roomsChannel;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
    _searchFocus.addListener(() => setState(() {}));

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  // ════════════════════════════════════════════════
  // ⭐ 실시간 구독 통합
  // ════════════════════════════════════════════════
  void _subscribeRealtime() {
    // 메시지 INSERT / UPDATE 통합
    _messagesChannel = Supabase.instance.client
        .channel('chat_list_messages_$_myId')
        // INSERT: 새 메시지 도착
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kyorangtalk_messages',
          callback: _onMessageInsert,
        )
        // UPDATE: is_read 변경, content 수정, is_deleted 등
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'kyorangtalk_messages',
          callback: (_) {
            print('🔵 [ChatList] 메시지 UPDATE → 리스트 갱신');
            _scheduleInvalidate();
          },
        )
        .subscribe();

    // 방 자체 변경 (pin, hidden_by, last_message 등)
    _roomsChannel = Supabase.instance.client
        .channel('chat_list_rooms_$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kyorangtalk_rooms',
          callback: (_) {
            print('🔵 [ChatList] 방 변경 → 리스트 갱신');
            _scheduleInvalidate();
          },
        )
        .subscribe();
  }

  // ⭐ 디바운스 invalidate (연속 이벤트 합치기)
  void _scheduleInvalidate() {
    _invalidateDebouncer?.cancel();
    _invalidateDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.invalidate(provider.chatRoomsProvider);
    });
  }

  // ⭐ 새 메시지 INSERT 핸들러 — 리스트 갱신 + 배너
  Future<void> _onMessageInsert(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row.isEmpty) return;

    final senderId = row['sender_id'] as String?;
    final roomId = row['room_id'] as String?;
    final content = row['content'] as String? ?? '';

    if (senderId == null) return;

    // ⭐ 무조건 리스트 갱신 (내 메시지든 상대 메시지든)
    _scheduleInvalidate();

    if (senderId == _myId) return;
    if (provider.currentOpenRoomId == roomId) return;

    // 배너 표시 로직
    try {
      final prefsData = await Supabase.instance.client
          .from('kyorangtalk_notification_prefs')
          .select('notifications_enabled, message_preview_enabled')
          .eq('user_id', _myId)
          .maybeSingle();

      final notificationsEnabled =
          prefsData?['notifications_enabled'] as bool? ?? true;
      final messagePreviewEnabled =
          prefsData?['message_preview_enabled'] as bool? ?? true;

      if (!notificationsEnabled) return;

      final muted = await NotificationService.isMuted(roomId: roomId);
      if (muted) return;

      if (!mounted) return;

      final blockCheck = await Supabase.instance.client
          .from('kyorangtalk_blocks')
          .select('id')
          .eq('blocker_id', _myId)
          .eq('blocked_id', senderId)
          .maybeSingle();

      if (blockCheck != null) return;
      if (!mounted) return;

      final profile = await Supabase.instance.client
          .from('kyorangtalk_profiles')
          .select('nickname')
          .eq('id', senderId)
          .maybeSingle();

      if (!mounted) return;
      final nickname = profile?['nickname'] as String? ?? '누군가';
      final rooms = ref.read(provider.chatRoomsProvider).value ?? [];
      final room = rooms.where((r) => r.roomId == roomId).firstOrNull;

      if (room != null) {
        final displayContent =
            messagePreviewEnabled ? content : '새 메시지가 도착했어요';
        _showOverlayNotification(nickname, displayContent, room);
      }
    } catch (e) {
      print('⚠️ 앱 내 알림 처리 실패: $e');
    }
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
    _invalidateDebouncer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _overlayEntry?.remove();

    if (_messagesChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_messagesChannel!);
      } catch (_) {}
    }
    if (_roomsChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_roomsChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
    final nowUtc = DateTime.now().toUtc();
    final dtUtc = dt.isUtc ? dt : dt.toUtc();
    var diff = nowUtc.difference(dtUtc);

    if (diff.isNegative) {
      diff = Duration.zero;
    }

    if (diff.inSeconds < 60) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    if (diff.inDays < 7) return '${diff.inDays}일';
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

  void _showRoomActionSheet(ChatRoomModel room) {
    final mutedRooms = ref.read(mutedRoomsProvider).value ?? {};
    final isMuted = mutedRooms.contains(room.roomId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoomActionSheet(
        room: room,
        isMuted: isMuted,
        onToggleMute: () {
          Navigator.pop(context);
          _toggleMute(room, isMuted);
        },
        onTogglePin: () {
          Navigator.pop(context);
          _togglePin(room);
        },
        onLeave: () {
          Navigator.pop(context);
          _confirmLeaveRoom(room);
        },
      ),
    );
  }

  Future<void> _toggleMute(ChatRoomModel room, bool currentlyMuted) async {
    try {
      if (currentlyMuted) {
        await NotificationService.unmute(roomId: room.roomId);
      } else {
        await NotificationService.mute(roomId: room.roomId);
      }
      ref.invalidate(mutedRoomsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyMuted
                ? '${room.partnerName}님 알림을 켰어요'
                : '${room.partnerName}님 알림을 껐어요'),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알림 설정 실패: $e')),
        );
      }
    }
  }

  Future<void> _togglePin(ChatRoomModel room) async {
    try {
      final isNowPinned = await provider.togglePinRoom(room.roomId);
      ref.invalidate(provider.chatRoomsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNowPinned
                ? '${room.partnerName}님 채팅방을 상단 고정했어요'
                : '${room.partnerName}님 채팅방 고정을 해제했어요'),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('고정 실패: $e')),
        );
      }
    }
  }

  void _confirmLeaveRoom(ChatRoomModel room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '채팅방 나가기',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '${room.partnerName}님과의 채팅방에서 나갈까요?\n'
          '내 채팅 목록에서만 사라지고, 상대방은 그대로예요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _leaveRoom(room);
            },
            child: const Text(
              '나가기',
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

  Future<void> _leaveRoom(ChatRoomModel room) async {
    try {
      await provider.hideChatRoom(room.roomId);
      ref.invalidate(provider.chatRoomsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('채팅방을 나갔어요'),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('나가기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(provider.chatRoomsProvider);
    final mutedAsync = ref.watch(mutedRoomsProvider);
    final mutedRooms = mutedAsync.value ?? {};

    final totalUnread = roomsAsync.value
            ?.where((r) => !mutedRooms.contains(r.roomId))
            .fold(0, (s, r) => s + r.unreadCount) ??
        0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Text(
                    '메시지',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (totalUnread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFEF4444),
                            Color(0xFFDC2626),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444)
                                .withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        totalUnread > 99 ? '99+' : '$totalUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showNewChatSheet,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary,
                              AppTheme.primary.withOpacity(0.85),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primary.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_square,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '새 채팅',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
                    hintText: '대화 검색',
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

            Expanded(
              child: roomsAsync.when(
                loading: () => const ChatListSkeleton(),
                error: (e, _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(provider.chatRoomsProvider),
                ),
                data: (rooms) {
                  final filtered = _search.isEmpty
                      ? rooms
                      : rooms
                          .where((r) =>
                              r.partnerName.toLowerCase().contains(
                                  _search.toLowerCase()) ||
                              r.partnerUsername.toLowerCase().contains(
                                  _search.toLowerCase()))
                          .toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      isSearching: _search.isNotEmpty,
                      searchQuery: _search,
                      onNewChat: _showNewChatSheet,
                    );
                  }

                  return RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () async {
                      ref.invalidate(provider.chatRoomsProvider);
                      await Future.delayed(
                          const Duration(milliseconds: 500));
                    },
                    child: ListView.builder(
                      padding:
                          const EdgeInsets.only(top: 4, bottom: 80),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final room = filtered[i];
                        final isMuted =
                            mutedRooms.contains(room.roomId);
                        final isUnread =
                            room.unreadCount > 0 && !isMuted;

                        return _ChatRoomTile(
                          room: room,
                          isMuted: isMuted,
                          isUnread: isUnread,
                          timeLabel: _timeAgo(room.lastTime),
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
                                  // ⭐ 채팅방 나올 때 리스트도 갱신
                                  ref.invalidate(
                                      provider.chatRoomsProvider);
                                });
                          },
                          onLongPress: () =>
                              _showRoomActionSheet(room),
                        );
                      },
                    ),
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

// ═══════════════════════════════════════════════════
// 채팅방 타일
// ═══════════════════════════════════════════════════
class _ChatRoomTile extends StatelessWidget {
  final ChatRoomModel room;
  final bool isMuted;
  final bool isUnread;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatRoomTile({
    required this.room,
    required this.isMuted,
    required this.isUnread,
    required this.timeLabel,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isUnread
                ? AppTheme.primary.withOpacity(0.08)
                : room.isPinned
                    ? AppTheme.bgCard.withOpacity(0.4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isUnread
                ? Border.all(
                    color: AppTheme.primary.withOpacity(0.2),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: isUnread
                          ? [
                              BoxShadow(
                                color: AppTheme.primary
                                    .withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: AvatarWidget(
                      url: room.partnerAvatar,
                      name: room.partnerName,
                      size: 52,
                    ),
                  ),
                  if (room.isPinned)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.bg, width: 2),
                        ),
                        child: const Icon(
                          Icons.push_pin_rounded,
                          color: Colors.white,
                          size: 9,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  : FontWeight.w700,
                              color: AppTheme.textMain,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.notifications_off_rounded,
                            color: AppTheme.textMuted,
                            size: 13,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.lastMessage.isEmpty
                          ? '대화를 시작해보세요'
                          : room.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isUnread
                            ? AppTheme.textMain
                            : room.lastMessage.isEmpty
                                ? AppTheme.textMuted
                                : AppTheme.textSub,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.normal,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: isUnread
                          ? AppTheme.primary
                          : AppTheme.textMuted,
                      fontWeight: isUnread
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (room.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: isMuted
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFFEF4444),
                                  Color(0xFFDC2626),
                                ],
                              ),
                        color: isMuted ? AppTheme.textSub : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isMuted
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFFEF4444)
                                      .withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 20,
                      ),
                      child: Text(
                        room.unreadCount > 99
                            ? '99+'
                            : '${room.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    const SizedBox(height: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  final String searchQuery;
  final VoidCallback onNewChat;

  const _EmptyState({
    required this.isSearching,
    required this.searchQuery,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearching
                    ? Icons.search_off_rounded
                    : Icons.chat_bubble_outline_rounded,
                color: AppTheme.textSub,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isSearching ? '검색 결과가 없어요' : '아직 대화가 없어요',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching
                  ? '"$searchQuery"와 일치하는 대화를 찾지 못했어요'
                  : '친구와 대화를 시작해보세요',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isSearching) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onNewChat,
                icon: const Icon(Icons.edit_square, size: 18),
                label: const Text('새 채팅 시작하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: AppTheme.textSub,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '불러오기 실패',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class _RoomActionSheet extends StatelessWidget {
  final ChatRoomModel room;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePin;
  final VoidCallback onLeave;

  const _RoomActionSheet({
    required this.room,
    required this.isMuted,
    required this.onToggleMute,
    required this.onTogglePin,
    required this.onLeave,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  AvatarWidget(
                    url: room.partnerAvatar,
                    name: room.partnerName,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          room.partnerName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (room.lastMessage.isNotEmpty)
                          Text(
                            room.lastMessage,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSub,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: AppTheme.border, height: 1),

            _ActionRow(
              icon: isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              iconColor: AppTheme.textMain,
              label: isMuted ? '알림 켜기' : '알림 끄기',
              labelColor: AppTheme.textMain,
              onTap: onToggleMute,
            ),

            _ActionRow(
              icon: room.isPinned
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              iconColor:
                  room.isPinned ? AppTheme.primary : AppTheme.textMain,
              label: room.isPinned ? '상단 고정 해제' : '상단 고정',
              labelColor: AppTheme.textMain,
              onTap: onTogglePin,
            ),

            Divider(
                color: AppTheme.border,
                height: 1,
                indent: 20,
                endIndent: 20),

            _ActionRow(
              icon: Icons.exit_to_app_rounded,
              iconColor: const Color(0xFFEF4444),
              label: '채팅방 나가기',
              labelColor: const Color(0xFFEF4444),
              onTap: onLeave,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
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
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: labelColor,
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
        final hiddenBy =
            (existing['hidden_by'] as List?)?.cast<String>() ?? [];
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
        partnerId: friend.friendId,
        partnerUsername: friend.nickname,
        partnerName: friend.nickname,
        partnerAvatar: friend.avatarUrl,
        lastMessage: '',
        lastTime: DateTime.now(),
        unreadCount: 0,
        isSent: false,
        roomId: roomId,
      );

      if (mounted) widget.onChatCreated(room, false);
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        _showSnack('채팅방 생성 실패: $e');
      }
    }
  }

  Future<void> _createGroup(
      String name, List<FriendModel> allFriends) async {
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
            width: 36,
            height: 4,
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
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMain,
                    letterSpacing: -0.3,
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
                        hintStyle:
                            TextStyle(color: AppTheme.textSub),
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(
                      color: AppTheme.textMain, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '친구 검색',
                    hintStyle: TextStyle(
                        color: AppTheme.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: AppTheme.textSub, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.cancel,
                                color: AppTheme.textSub, size: 18),
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
                                                FontWeight.w700,
                                            color:
                                                AppTheme.textMain)),
                                    if (friend.statusMessage !=
                                            null &&
                                        friend.statusMessage!
                                            .isNotEmpty)
                                      Text(friend.statusMessage!,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  AppTheme.textSub),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis),
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
                border:
                    Border(top: BorderSide(color: AppTheme.border)),
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
                                  fontWeight: FontWeight.w800),
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
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: AvatarWidget(
                      url: widget.room.partnerAvatar,
                      name: widget.room.partnerName,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded,
                          color: AppTheme.textSub, size: 14),
                    ),
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