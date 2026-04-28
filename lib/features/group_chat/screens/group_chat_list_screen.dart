import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import '../../../features/friends/screens/friends_screen.dart';
import 'open_room_preview_screen.dart';
import 'group_chat_room_screen.dart';

const _openCategories = [
  '전체', '일반', '게임', '공부', '취미', '운동', '음악', '여행', '기타'
];

enum OpenRoomSort {
  popular, members, recent,
}

extension on OpenRoomSort {
  String get label {
    switch (this) {
      case OpenRoomSort.popular: return '인기순';
      case OpenRoomSort.members: return '사람수';
      case OpenRoomSort.recent:  return '최신순';
    }
  }
  
  IconData get icon {
    switch (this) {
      case OpenRoomSort.popular: return Icons.favorite_rounded;
      case OpenRoomSort.members: return Icons.people_rounded;
      case OpenRoomSort.recent:  return Icons.access_time_rounded;
    }
  }
}

class GroupChatListScreen extends ConsumerStatefulWidget {
  const GroupChatListScreen({super.key});

  @override
  ConsumerState<GroupChatListScreen> createState() =>
      _GroupChatListScreenState();
}

class _GroupChatListScreenState extends ConsumerState<GroupChatListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  bool _selectionMode = false;
  final Set<String> _selectedRoomIds = {};
  OverlayEntry? _overlayEntry;

  final _openSearchController = TextEditingController();
  String _openSearch = '';
  String _selectedCategory = '전체';
  OpenRoomSort _sortBy = OpenRoomSort.popular;

  Timer? _uiRefreshTimer;

  // ✨ 이전 상태 추적 (새 메시지 감지)
  final Map<String, int> _previousUnreadCounts = {};
  // ✨ 초기 로드 끝났는지 플래그 (첫 로드에선 배너 안 띄움)
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_selectionMode) {
        setState(() {
          _selectionMode = false;
          _selectedRoomIds.clear();
        });
      }
    });

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tabController.dispose();
    _openSearchController.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  // ✨ 새 메시지 감지 → 배너 표시
  Future<void> _checkNewMessages(List<GroupRoomModel> rooms) async {
    // 첫 로드는 스킵
    if (!_isInitialized) {
      for (final room in rooms) {
        _previousUnreadCounts[room.id] = room.unreadCount;
      }
      _isInitialized = true;
      return;
    }

    // 새 메시지 감지
    for (final room in rooms) {
      final prevUnread = _previousUnreadCounts[room.id] ?? 0;

      if (room.unreadCount > prevUnread) {
        // 현재 보고 있는 방이면 스킵
        if (currentOpenGroupRoomId == room.id) continue;

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

          if (!notificationsEnabled) continue;

          final muted = await NotificationService.isMuted(
              groupRoomId: room.id);
          if (muted) continue;

          if (!mounted) return;

          // ✨ RangeError 방어: lastMessage가 비어있을 수 있음
          final msgText = room.lastMessage ?? '';
          final displayContent = messagePreviewEnabled
              ? (msgText.isEmpty ? '새 메시지가 도착했어요' : msgText)
              : '새 메시지가 도착했어요';

          _showGroupOverlayNotification(
            groupName: room.name,
            groupAvatar: room.avatarUrl,
            content: displayContent,
            room: room,
          );
          break;
        } catch (e) {
          print('⚠️ 배너 표시 실패: $e');
        }
      }
    }

    // 이전 상태 업데이트
    _previousUnreadCounts.clear();
    for (final room in rooms) {
      _previousUnreadCounts[room.id] = room.unreadCount;
    }
  }

  void _showGroupOverlayNotification({
    required String groupName,
    required String? groupAvatar,
    required String content,
    required GroupRoomModel room,
  }) {
    _overlayEntry?.remove();
    _overlayEntry = null;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _GroupTopNotificationBanner(
        groupName: groupName,
        groupAvatar: groupAvatar,
        content: content,
        room: room,
        onTap: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupChatRoomScreen(room: room),
            ),
          );
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

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final nowUtc = DateTime.now().toUtc();
    final dtUtc = dt.isUtc ? dt : dt.toUtc();
    var diff = nowUtc.difference(dtUtc);

    if (diff.isNegative) diff = Duration.zero;

    if (diff.inSeconds < 60) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    final local = dt.isUtc ? dt.toLocal() : dt;
    return DateFormat('M/d').format(local);
  }

  void _enterSelectionMode(String roomId) {
    setState(() {
      _selectionMode = true;
      _selectedRoomIds.add(roomId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedRoomIds.clear();
    });
  }

  void _toggleSelection(String roomId) {
    setState(() {
      if (_selectedRoomIds.contains(roomId)) {
        _selectedRoomIds.remove(roomId);
        if (_selectedRoomIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedRoomIds.add(roomId);
      }
    });
  }

  void _selectAll(List<GroupRoomModel> rooms) {
    setState(() {
      if (_selectedRoomIds.length == rooms.length) {
        _selectedRoomIds.clear();
        _selectionMode = false;
      } else {
        _selectedRoomIds.clear();
        _selectedRoomIds.addAll(rooms.map((r) => r.id));
      }
    });
  }

  Future<void> _bulkLeave() async {
    final count = _selectedRoomIds.length;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('$count개 채팅방 나가기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '선택한 $count개 채팅방에서 나가시겠어요?\n'
          '나가면 대화 내용을 볼 수 없어요.',
          style: TextStyle(
              color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    int successCount = 0;
    int failCount = 0;

    for (final roomId in _selectedRoomIds.toList()) {
      try {
        await leaveGroupRoom(roomId);
        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    if (mounted) {
      Navigator.pop(context);
      _exitSelectionMode();
      ref.invalidate(groupRoomsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failCount > 0
              ? '$successCount개 나가기 완료, $failCount개 실패'
              : '$successCount개 채팅방에서 나갔어요'),
        ),
      );
    }
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateGroupSheet(myId: _myId),
    );
  }

  void _showJoinByCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('초대코드 입력',
            style: TextStyle(
                color: AppTheme.textMain, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.textMain),
          decoration: InputDecoration(
            hintText: '8자리 초대코드',
            hintStyle: TextStyle(color: AppTheme.textSub),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.none,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);

              final joined = await joinGroupByCode(code);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(joined
                        ? '채팅방에 입장했어요!'
                        : '유효하지 않은 초대코드예요'),
                  ),
                );
                if (joined) ref.invalidate(groupRoomsProvider);
              }
            },
            child: const Text('입장',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('정렬 방식',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
            ),
            ...OpenRoomSort.values.map((sort) {
              final selected = _sortBy == sort;
              return ListTile(
                leading: Icon(sort.icon,
                    color: selected ? AppTheme.primary : AppTheme.textSub),
                title: Text(sort.label,
                    style: TextStyle(
                        color: selected ? AppTheme.primary : AppTheme.textMain,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal)),
                trailing: selected
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _sortBy = sort);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<GroupRoomModel> _filterAndSortOpenRooms(List<GroupRoomModel> rooms) {
    var filtered = rooms;
    if (_selectedCategory != '전체') {
      filtered = filtered.where((r) => r.category == _selectedCategory).toList();
    }

    if (_openSearch.isNotEmpty) {
      final query = _openSearch.toLowerCase();
      filtered = filtered.where((r) {
        if (r.name.toLowerCase().contains(query)) return true;
        if ((r.description ?? '').toLowerCase().contains(query)) return true;
        if (r.tags.any((t) => t.toLowerCase().contains(query))) return true;
        return false;
      }).toList();
    }

    final sorted = [...filtered];
    switch (_sortBy) {
      case OpenRoomSort.popular:
        sorted.sort((a, b) => b.likeCount.compareTo(a.likeCount));
        break;
      case OpenRoomSort.members:
        sorted.sort((a, b) => b.memberCount.compareTo(a.memberCount));
        break;
      case OpenRoomSort.recent:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    // ✨ Provider 변화 감지 → 새 메시지 배너
    ref.listen<AsyncValue<List<GroupRoomModel>>>(
      groupRoomsProvider,
      (previous, next) {
        next.whenData((rooms) {
          _checkNewMessages(rooms);
        });
      },
    );

    final myRoomsAsync = ref.watch(groupRoomsProvider);
    final openRoomsAsync = ref.watch(openRoomsProvider);
    final mutedAsync = ref.watch(mutedRoomsProvider);
    final mutedRooms = mutedAsync.value ?? {};

    final totalUnread = myRoomsAsync.value
            ?.where((r) => !mutedRooms.contains(r.id))
            .fold(0, (s, r) => s + r.unreadCount) ?? 0;

    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          _exitSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_selectionMode) ...[
                          IconButton(
                            icon: Icon(Icons.close,
                                color: AppTheme.textMain),
                            onPressed: _exitSelectionMode,
                          ),
                          Text('${_selectedRoomIds.length}개 선택',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textMain)),
                        ] else ...[
                          Text('그룹채팅',
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
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('$totalUnread',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ],
                        const Spacer(),
                        if (_selectionMode) ...[
                          if (_tabController.index == 0)
                            IconButton(
                              icon: Icon(
                                (myRoomsAsync.value != null &&
                                        _selectedRoomIds.length ==
                                            myRoomsAsync.value!.length)
                                    ? Icons.deselect
                                    : Icons.select_all,
                                color: AppTheme.textSub,
                              ),
                              tooltip: '전체 선택',
                              onPressed: () {
                                final rooms = myRoomsAsync.value ?? [];
                                _selectAll(rooms);
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.exit_to_app,
                                color: Color(0xFFEF4444)),
                            tooltip: '선택한 방 나가기',
                            onPressed: _selectedRoomIds.isEmpty
                                ? null
                                : _bulkLeave,
                          ),
                        ] else ...[
                          IconButton(
                            icon: Icon(Icons.link,
                                color: AppTheme.textSub),
                            tooltip: '초대코드로 입장',
                            onPressed: _showJoinByCodeDialog,
                          ),
                          IconButton(
                            icon: Icon(Icons.add,
                                color: AppTheme.textSub),
                            tooltip: '새 채팅방',
                            onPressed: _showCreateDialog,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!_selectionMode)
                      TabBar(
                        controller: _tabController,
                        indicator: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: AppTheme.primary, width: 2),
                          ),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: AppTheme.primaryLight,
                        unselectedLabelColor: AppTheme.textSub,
                        labelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        tabs: const [
                          Tab(text: '내 채팅방'),
                          Tab(text: '오픈채팅'),
                        ],
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: _selectionMode
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    myRoomsAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary),
                      ),
                      error: (e, _) => Center(
                        child: Text('오류: $e',
                            style: TextStyle(
                                color: AppTheme.textSub)),
                      ),
                      data: (rooms) {
                        if (rooms.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Text('💬',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text('참여 중인 채팅방이 없어요',
                                    style: TextStyle(
                                        color: AppTheme.textSub,
                                        fontSize: 14)),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _showCreateDialog,
                                  icon: const Icon(Icons.add,
                                      color: AppTheme.primary,
                                      size: 18),
                                  label: const Text('채팅방 만들기',
                                      style: TextStyle(
                                          color: AppTheme.primary)),
                                ),
                              ],
                            ),
                          );
                        }
                        return RefreshIndicator(
                          color: AppTheme.primary,
                          onRefresh: () async {
                            ref.invalidate(groupRoomsProvider);
                            await Future.delayed(
                                const Duration(milliseconds: 500));
                          },
                          child: ListView.builder(
                            itemCount: rooms.length,
                            itemBuilder: (_, i) => _GroupRoomTile(
                              room: rooms[i],
                              timeAgo: _timeAgo(rooms[i].lastMessageAt),
                              selectionMode: _selectionMode,
                              isSelected: _selectedRoomIds
                                  .contains(rooms[i].id),
                              isMuted: mutedRooms.contains(rooms[i].id),
                              onTap: () {
                                if (_selectionMode) {
                                  _toggleSelection(rooms[i].id);
                                } else {
                                  currentOpenGroupRoomId = rooms[i].id;
                                  context.push(
                                    '/main/group/${rooms[i].id}',
                                    extra: rooms[i],
                                  ).then((_) {
                                    currentOpenGroupRoomId = null;
                                    ref.invalidate(mutedRoomsProvider);
                                  });
                                }
                              },
                              onLongPress: () {
                                if (!_selectionMode) {
                                  _enterSelectionMode(rooms[i].id);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),

                    openRoomsAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary),
                      ),
                      error: (e, _) => Center(
                        child: Text('오류: $e',
                            style: TextStyle(
                                color: AppTheme.textSub)),
                      ),
                      data: (rooms) {
                        if (rooms.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Text('🌐',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text('오픈채팅방이 없어요',
                                    style: TextStyle(
                                        color: AppTheme.textSub,
                                        fontSize: 14)),
                              ],
                            ),
                          );
                        }

                        final filtered = _filterAndSortOpenRooms(rooms);

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: TextField(
                                  controller: _openSearchController,
                                  onChanged: (v) =>
                                      setState(() => _openSearch = v),
                                  style: TextStyle(
                                      color: AppTheme.textMain, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '오픈채팅 검색...',
                                    border: InputBorder.none,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 10),
                                    prefixIcon: Icon(Icons.search,
                                        color: AppTheme.textSub, size: 18),
                                    suffixIcon: _openSearch.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(Icons.close,
                                                color: AppTheme.textSub,
                                                size: 16),
                                            onPressed: () {
                                              _openSearchController.clear();
                                              setState(() => _openSearch = '');
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(
                              height: 38,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                itemCount: _openCategories.length,
                                itemBuilder: (_, i) {
                                  final cat = _openCategories[i];
                                  final selected = _selectedCategory == cat;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _selectedCategory = cat),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppTheme.primary
                                              : AppTheme.bgCard,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: selected
                                                ? AppTheme.primary
                                                : AppTheme.border,
                                          ),
                                        ),
                                        child: Text(cat,
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: selected
                                                    ? Colors.white
                                                    : AppTheme.textSub,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 10, 20, 8),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: _showSortSheet,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.bgCard,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: AppTheme.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_sortBy.icon,
                                              color: AppTheme.primary,
                                              size: 14),
                                          const SizedBox(width: 4),
                                          Text(_sortBy.label,
                                              style: TextStyle(
                                                  color: AppTheme.textMain,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                          const SizedBox(width: 2),
                                          Icon(
                                              Icons
                                                  .keyboard_arrow_down_rounded,
                                              color: AppTheme.textSub,
                                              size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${filtered.length}개 채팅방',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSub,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                            Divider(height: 1, color: AppTheme.border),

                            Expanded(
                              child: filtered.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('🔍',
                                              style: TextStyle(
                                                  fontSize: 40)),
                                          const SizedBox(height: 12),
                                          Text(
                                            _openSearch.isNotEmpty
                                                ? '"$_openSearch" 검색 결과가 없어요'
                                                : '$_selectedCategory 카테고리에\n오픈채팅이 없어요',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: AppTheme.textSub,
                                                fontSize: 14,
                                                height: 1.5),
                                          ),
                                        ],
                                      ),
                                    )
                                  : RefreshIndicator(
                                      color: AppTheme.primary,
                                      onRefresh: () async {
                                        ref.invalidate(openRoomsProvider);
                                        await Future.delayed(
                                            const Duration(
                                                milliseconds: 500));
                                      },
                                      child: ListView.builder(
                                        itemCount: filtered.length,
                                        itemBuilder: (_, i) => _OpenRoomTile(
                                          room: filtered[i],
                                          myId: _myId,
                                          rank: _sortBy == OpenRoomSort.popular
                                              ? i + 1
                                              : null,
                                          onPreview: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    OpenRoomPreviewScreen(
                                                        room: filtered[i]),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupRoomTile extends StatelessWidget {
  final GroupRoomModel room;
  final String timeAgo;
  final bool selectionMode;
  final bool isSelected;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GroupRoomTile({
    required this.room,
    required this.timeAgo,
    required this.selectionMode,
    required this.isSelected,
    required this.isMuted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = room.unreadCount > 0 && !isMuted;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.15)
              : (isUnread
                  ? AppTheme.primary.withOpacity(0.08)
                  : Colors.transparent),
          border: Border(
              bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selectionMode) ...[
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
            ],

            Stack(
              children: [
                AvatarWidget(
                    url: room.avatarUrl,
                    name: room.name,
                    size: 50),
                if (room.isOpen)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTheme.bg, width: 1.5),
                      ),
                      child: const Icon(Icons.public,
                          color: Colors.white, size: 10),
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
                        child: Text(room.name,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: AppTheme.textMain),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Text('${room.memberCount}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub)),
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.notifications_off,
                            color: AppTheme.textSub, size: 13),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    room.lastMessage ?? '대화를 시작해보세요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isUnread
                          ? AppTheme.textMain
                          : (room.lastMessage != null
                              ? AppTheme.textSub
                              : AppTheme.textMuted),
                      fontWeight: isUnread
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            if (!selectionMode) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (timeAgo.isNotEmpty)
                    Text(timeAgo,
                        style: TextStyle(
                            fontSize: 11,
                            color: isUnread
                                ? const Color(0xFFEF4444)
                                : AppTheme.textMuted,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.normal)),
                  const SizedBox(height: 6),
                  if (room.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMuted
                            ? AppTheme.textSub
                            : const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 18,
                      ),
                      child: Text(
                        '${room.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OpenRoomTile extends StatelessWidget {
  final GroupRoomModel room;
  final String myId;
  final int? rank;
  final VoidCallback onPreview;

  const _OpenRoomTile({
    required this.room,
    required this.myId,
    required this.onPreview,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPreview,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            if (rank != null) ...[
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: rank! <= 3
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.bgCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: rank! <= 3
                        ? AppTheme.primary
                        : AppTheme.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: rank! <= 3
                          ? AppTheme.primary
                          : AppTheme.textSub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            AvatarWidget(
                url: room.avatarUrl, name: room.name, size: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(room.name,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMain),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(room.category,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF06B6D4),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (room.description != null)
                        Expanded(
                          child: Text(room.description!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSub),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        )
                      else
                        const Spacer(),
                      Icon(Icons.people_outline,
                          size: 11, color: AppTheme.textSub),
                      const SizedBox(width: 2),
                      Text('${room.memberCount}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub)),
                      const SizedBox(width: 8),
                      const Icon(Icons.favorite,
                          size: 11, color: Color(0xFFEF4444)),
                      const SizedBox(width: 2),
                      Text('${room.likeCount}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF06B6D4).withOpacity(0.3)),
              ),
              child: const Icon(Icons.chevron_right,
                  color: Color(0xFF06B6D4), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTopNotificationBanner extends StatefulWidget {
  final String groupName;
  final String? groupAvatar;
  final String content;
  final GroupRoomModel room;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _GroupTopNotificationBanner({
    required this.groupName,
    required this.groupAvatar,
    required this.content,
    required this.room,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_GroupTopNotificationBanner> createState() =>
      _GroupTopNotificationBannerState();
}

class _GroupTopNotificationBannerState
    extends State<_GroupTopNotificationBanner>
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
    // ✨ RangeError 방어: 문자열 길이 체크
    final displayText = widget.content.length > 40
        ? '${widget.content.substring(0, 40)}...'
        : widget.content;

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
                  Stack(
                    children: [
                      AvatarWidget(
                        url: widget.groupAvatar,
                        name: widget.groupName,
                        size: 40,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.bgCard, width: 1.5),
                          ),
                          child: const Icon(Icons.group,
                              color: Colors.white, size: 9),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(widget.groupName,
                                  style: TextStyle(
                                      color: AppTheme.textMain,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14),
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary
                                    .withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                              child: Text(
                                '그룹',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayText,
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

class _CreateGroupSheet extends ConsumerStatefulWidget {
  final String myId;
  const _CreateGroupSheet({required this.myId});

  @override
  ConsumerState<_CreateGroupSheet> createState() =>
      _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _tagController = TextEditingController();
  String _roomType = 'group';
  String _category = '일반';
  bool _loading = false;
  List<String> _selectedFriendIds = [];
  List<String> _tags = [];
  
  File? _imageFile;

  final _categories = ['일반', '게임', '공부', '취미', '운동', '음악', '여행', '기타'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _roomType =
          _tabController.index == 0 ? 'group' : 'open');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim().replaceAll('#', '');
    if (tag.isEmpty) return;
    if (_tags.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('태그는 최대 5개까지 추가할 수 있어요')),
      );
      return;
    }
    if (_tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined,
                  color: AppTheme.textMain),
              title: Text('카메라로 촬영',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppTheme.textMain),
              title: Text('갤러리에서 선택',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_imageFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF4444)),
                title: const Text('이미지 삭제',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _imageFile = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (picked == null) return;

    setState(() => _imageFile = File(picked.path));
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    String? avatarUrl;
    if (_imageFile != null) {
      avatarUrl = await uploadRoomImage(_imageFile!);
    }

    final room = await createGroupRoom(
      name:      _nameController.text.trim(),
      roomType:  _roomType,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      category:  _category,
      memberIds: _selectedFriendIds,
      avatarUrl: avatarUrl,
      tags:      _roomType == 'open' ? _tags : [],
    );

    if (mounted) {
      Navigator.pop(context);
      ref.invalidate(groupRoomsProvider);
      ref.invalidate(openRoomsProvider);
      if (room != null) {
        context.push('/main/group/${room.id}', extra: room);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Text('채팅방 만들기',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain)),
                  const Spacer(),
                  TextButton(
                    onPressed: _loading ||
                            _nameController.text.trim().isEmpty
                        ? null
                        : _create,
                    child: _loading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary))
                        : const Text('만들기',
                            style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
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
                  tabs: const [Tab(text: '그룹채팅'), Tab(text: '오픈채팅')],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.bgCard,
                              border: Border.all(
                                  color: AppTheme.border, width: 2),
                              image: _imageFile != null
                                  ? DecorationImage(
                                      image: FileImage(_imageFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _imageFile == null
                                ? Icon(Icons.camera_alt_outlined,
                                    color: AppTheme.textSub, size: 28)
                                : null,
                          ),
                          if (_imageFile != null)
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppTheme.bg, width: 2),
                                ),
                                child: const Icon(Icons.edit,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _imageFile == null
                          ? '대표 이미지 추가 (선택)'
                          : '이미지 변경',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text('채팅방 이름',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: AppTheme.textMain),
                    maxLength: 30,
                    decoration: InputDecoration(
                      hintText: '채팅방 이름을 입력해요',
                      counterStyle: TextStyle(
                          color: AppTheme.textSub, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_roomType == 'open') ...[
                    Text('설명 (선택)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descController,
                      style: TextStyle(color: AppTheme.textMain),
                      maxLength: 200,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '채팅방 소개를 입력해요',
                        counterStyle: TextStyle(
                            color: AppTheme.textSub, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text('카테고리',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _categories.map((cat) {
                        final selected = _category == cat;
                        return GestureDetector(
                          onTap: () => setState(() => _category = cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Text(cat,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.textSub,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.normal)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Text('태그 (선택)',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSub)),
                        const SizedBox(width: 4),
                        Text('${_tags.length}/5',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            style: TextStyle(
                                color: AppTheme.textMain),
                            maxLength: 10,
                            onSubmitted: (_) => _addTag(),
                            decoration: InputDecoration(
                              hintText: '예) 소통, 친목, 게임',
                              prefixText: '#',
                              prefixStyle: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700),
                              counterStyle: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _addTag,
                          style: TextButton.styleFrom(
                            backgroundColor:
                                AppTheme.primary.withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          child: const Text('추가',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: _tags.map((tag) {
                          return GestureDetector(
                            onTap: () => _removeTag(tag),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                  10, 5, 6, 5),
                              decoration: BoxDecoration(
                                color: AppTheme.primary
                                    .withOpacity(0.12),
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('#$tag',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppTheme.primaryLight,
                                          fontWeight:
                                              FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.close,
                                      size: 14,
                                      color:
                                          AppTheme.primaryLight),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  if (_roomType == 'group') ...[
                    Text('친구 초대',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub)),
                    const SizedBox(height: 8),
                    friendsAsync.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.primary)),
                      error: (_, __) => const SizedBox(),
                      data: (friends) => friends.isEmpty
                          ? Text('초대할 친구가 없어요',
                              style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 13))
                          : Column(
                              children: friends.map((f) {
                                final selected = _selectedFriendIds
                                    .contains(f.friendId);
                                return InkWell(
                                  onTap: () => setState(() {
                                    if (selected) {
                                      _selectedFriendIds.remove(f.friendId);
                                    } else {
                                      _selectedFriendIds.add(f.friendId);
                                    }
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 10),
                                    child: Row(
                                      children: [
                                        AvatarWidget(
                                            url: f.avatarUrl,
                                            name: f.nickname,
                                            size: 38),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(f.nickname,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color:
                                                      AppTheme.textMain)),
                                        ),
                                        Container(
                                          width: 22, height: 22,
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppTheme.primary
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: selected
                                                  ? AppTheme.primary
                                                  : AppTheme.border,
                                              width: 2,
                                            ),
                                          ),
                                          child: selected
                                              ? const Icon(Icons.check,
                                                  color: Colors.white,
                                                  size: 14)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}