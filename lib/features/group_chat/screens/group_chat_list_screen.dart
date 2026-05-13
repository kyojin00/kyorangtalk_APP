import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../enums/group_chat_enums.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import '../sheets/sort_sheet.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/group_notification_banner.dart';
import '../widgets/group_room_tile.dart';
import '../widgets/my_room_segment.dart';
import '../widgets/open_room_tile.dart';
import '../widgets/password_dialog.dart';
import 'group_chat_room_screen.dart';
import 'open_room_preview_screen.dart';

// ═══════════════════════════════════════════════════
// 💬 GroupChatListScreen — 리디자인 (간소화)
//
// 위치: lib/features/group_chat/screens/group_chat_list_screen.dart
// ═══════════════════════════════════════════════════

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
  final _openSearchFocus = FocusNode();
  String _openSearch = '';
  String _selectedCategory = '전체';
  OpenRoomSort _sortBy = OpenRoomSort.popular;
  MyRoomFilter _myRoomFilter = MyRoomFilter.all;

  Timer? _uiRefreshTimer;

  final Map<String, int> _previousUnreadCounts = {};
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
    _openSearchFocus.addListener(() => setState(() {}));

    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tabController.dispose();
    _openSearchController.dispose();
    _openSearchFocus.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  Future<void> _checkNewMessages(List<GroupRoomModel> rooms) async {
    if (!_isInitialized) {
      for (final room in rooms) {
        _previousUnreadCounts[room.id] = room.unreadCount;
      }
      _isInitialized = true;
      return;
    }

    for (final room in rooms) {
      final prevUnread = _previousUnreadCounts[room.id] ?? 0;

      if (room.unreadCount > prevUnread) {
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

          final muted =
              await NotificationService.isMuted(groupRoomId: room.id);
          if (muted) continue;

          if (!mounted) return;

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
      builder: (ctx) => GroupTopNotificationBanner(
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    if (diff.inDays < 7) return '${diff.inDays}일';
    final local = dt.isUtc ? dt.toLocal() : dt;
    return DateFormat('M/d').format(local);
  }

  // ─── 선택 모드 ─────────────────────────────────
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
        if (_selectedRoomIds.isEmpty) _selectionMode = false;
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
        title: Text(
          '$count개 채팅방 나가기',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '선택한 $count개 채팅방에서 나가시겠어요?\n'
          '나가면 대화 내용을 볼 수 없어요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
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

  // ─── 생성 시트 ─────────────────────────────────
  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CreateGroupSheet(myId: _myId),
    );
  }

  // ─── 초대코드 입력 ─────────────────────────────
  void _showJoinByCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '초대코드 입력',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
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
            child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              await _joinByCodeFlow(code);
            },
            child: const Text(
              '입장',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinByCodeFlow(String code) async {
    final needsPw = await codeRequiresPassword(code);

    String? password;
    if (needsPw) {
      if (!mounted) return;
      String? errorMsg;
      while (true) {
        password = await showRoomPasswordDialog(
          context,
          roomName: '초대받은 채팅방',
          errorMessage: errorMsg,
        );
        if (password == null) return;

        final result = await joinByCodeWithPassword(
          inviteCode: code,
          password: password,
        );

        if (result == JoinResult.ok) break;
        if (result == JoinResult.notFound) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('유효하지 않은 초대코드예요')),
            );
          }
          return;
        }
        if (result == JoinResult.wrongPassword) {
          errorMsg = '비밀번호가 틀렸어요';
          continue;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('입장에 실패했어요')),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방에 입장했어요!')),
        );
        ref.invalidate(groupRoomsProvider);
      }
    } else {
      final result = await joinByCodeWithPassword(
        inviteCode: code,
        password: null,
      );
      if (mounted) {
        if (result == JoinResult.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('채팅방에 입장했어요!')),
          );
          ref.invalidate(groupRoomsProvider);
        } else if (result == JoinResult.notFound) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('유효하지 않은 초대코드예요')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('입장에 실패했어요')),
          );
        }
      }
    }
  }

  // ─── 필터/정렬 ─────────────────────────────────
  List<GroupRoomModel> _filterAndSortOpenRooms(
      List<GroupRoomModel> rooms) {
    var filtered = rooms;
    if (_selectedCategory != '전체') {
      filtered = filtered
          .where((r) => r.category == _selectedCategory)
          .toList();
    }

    if (_openSearch.isNotEmpty) {
      final query = _openSearch.toLowerCase();
      filtered = filtered.where((r) {
        if (r.name.toLowerCase().contains(query)) return true;
        if ((r.description ?? '').toLowerCase().contains(query)) {
          return true;
        }
        if (r.tags.any((t) => t.toLowerCase().contains(query))) {
          return true;
        }
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

  List<GroupRoomModel> _filterMyRooms(List<GroupRoomModel> rooms) {
    switch (_myRoomFilter) {
      case MyRoomFilter.all:
        return rooms;
      case MyRoomFilter.group:
        return rooms.where((r) => !r.isOpen).toList();
      case MyRoomFilter.open:
        return rooms.where((r) => r.isOpen).toList();
    }
  }

  // ═════════════════════════════════════════════════
  // build
  // ═════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
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
            .fold(0, (s, r) => s + r.unreadCount) ??
        0;

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
              // ─── 헤더 ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    if (_selectionMode) ...[
                      _CircleIconButton(
                        icon: Icons.close_rounded,
                        onTap: _exitSelectionMode,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_selectedRoomIds.length}개 선택',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ] else ...[
                      Text(
                        '그룹채팅',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (totalUnread > 0) ...[
                        const SizedBox(width: 8),
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
                      ],
                    ],
                    const Spacer(),
                    if (_selectionMode) ...[
                      if (_tabController.index == 0)
                        _CircleIconButton(
                          icon: (myRoomsAsync.value != null &&
                                  _selectedRoomIds.length ==
                                      myRoomsAsync.value!.length)
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          onTap: () {
                            final rooms = myRoomsAsync.value ?? [];
                            _selectAll(rooms);
                          },
                        ),
                      const SizedBox(width: 8),
                      _CircleIconButton(
                        icon: Icons.exit_to_app_rounded,
                        iconColor: const Color(0xFFEF4444),
                        onTap: _selectedRoomIds.isEmpty
                            ? null
                            : _bulkLeave,
                      ),
                    ] else ...[
                      _CircleIconButton(
                        icon: Icons.link_rounded,
                        onTap: _showJoinByCodeDialog,
                      ),
                      const SizedBox(width: 8),
                      // 새 채팅방 — primary 그라데이션
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _showCreateDialog,
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
                                  color: AppTheme.primary
                                      .withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '만들기',
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
                  ],
                ),
              ),

              // ─── 탭바 ──────────────────────────────
              if (!_selectionMode)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.primary,
                          width: 2.5,
                        ),
                      ),
                    ),
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: AppTheme.border,
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: AppTheme.textSub,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: '내 채팅방'),
                      Tab(text: '오픈채팅'),
                    ],
                  ),
                )
              else
                Divider(color: AppTheme.border, height: 1),

              // ─── 본문 ──────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: _selectionMode
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    _buildMyRoomsTab(myRoomsAsync, mutedRooms),
                    _buildOpenRoomsTab(openRoomsAsync),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 내 채팅방 탭 ──────────────────────────────
  Widget _buildMyRoomsTab(
      AsyncValue<List<GroupRoomModel>> myRoomsAsync,
      Set<String> mutedRooms) {
    return myRoomsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (e, _) => Center(
        child: Text('오류: $e',
            style: TextStyle(color: AppTheme.textSub)),
      ),
      data: (rooms) {
        if (rooms.isEmpty) {
          return _MyRoomsEmptyState(onCreate: _showCreateDialog);
        }

        final groupCount = rooms.where((r) => !r.isOpen).length;
        final openCount = rooms.where((r) => r.isOpen).length;
        final filtered = _filterMyRooms(rooms);

        return Column(
          children: [
            if (!_selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: MyRoomSegment(
                  selected: _myRoomFilter,
                  totalCount: rooms.length,
                  groupCount: groupCount,
                  openCount: openCount,
                  onChanged: (f) =>
                      setState(() => _myRoomFilter = f),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _myRoomFilter == MyRoomFilter.group
                            ? '참여 중인 그룹채팅이 없어요'
                            : '참여 중인 오픈채팅이 없어요',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () async {
                        ref.invalidate(groupRoomsProvider);
                        await Future.delayed(
                            const Duration(milliseconds: 500));
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                            top: 4, bottom: 80),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => GroupRoomTile(
                          room: filtered[i],
                          timeAgo:
                              _timeAgo(filtered[i].lastMessageAt),
                          selectionMode: _selectionMode,
                          isSelected:
                              _selectedRoomIds.contains(filtered[i].id),
                          isMuted: mutedRooms.contains(filtered[i].id),
                          onTap: () {
                            if (_selectionMode) {
                              _toggleSelection(filtered[i].id);
                            } else {
                              currentOpenGroupRoomId = filtered[i].id;
                              context
                                  .push(
                                    '/main/group/${filtered[i].id}',
                                    extra: filtered[i],
                                  )
                                  .then((_) {
                                currentOpenGroupRoomId = null;
                                ref.invalidate(mutedRoomsProvider);
                              });
                            }
                          },
                          onLongPress: () {
                            if (!_selectionMode) {
                              _enterSelectionMode(filtered[i].id);
                            }
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ─── 오픈채팅 탭 ──────────────────────────────
  Widget _buildOpenRoomsTab(
      AsyncValue<List<GroupRoomModel>> openRoomsAsync) {
    return openRoomsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (e, _) => Center(
        child: Text('오류: $e',
            style: TextStyle(color: AppTheme.textSub)),
      ),
      data: (rooms) {
        if (rooms.isEmpty) {
          return Center(
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
                    Icons.public_rounded,
                    color: AppTheme.textSub,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '오픈채팅방이 없어요',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }

        final filtered = _filterAndSortOpenRooms(rooms);

        return Column(
          children: [
            // 검색바
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _openSearchFocus.hasFocus
                        ? AppTheme.primary.withOpacity(0.5)
                        : AppTheme.border,
                    width: _openSearchFocus.hasFocus ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _openSearchController,
                  focusNode: _openSearchFocus,
                  onChanged: (v) => setState(() => _openSearch = v),
                  style: TextStyle(
                      color: AppTheme.textMain, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '오픈채팅 검색',
                    hintStyle: TextStyle(
                        color: AppTheme.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: _openSearchFocus.hasFocus
                          ? AppTheme.primary
                          : AppTheme.textSub,
                      size: 20,
                    ),
                    suffixIcon: _openSearch.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.cancel,
                                color: AppTheme.textSub, size: 18),
                            onPressed: () {
                              _openSearchController.clear();
                              setState(() => _openSearch = '');
                              _openSearchFocus.unfocus();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),

            // 카테고리 칩
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                itemCount: openCategories.length,
                itemBuilder: (_, i) {
                  final cat = openCategories[i];
                  final selected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? LinearGradient(
                                  colors: [
                                    AppTheme.primary,
                                    AppTheme.primary.withOpacity(0.85),
                                  ],
                                )
                              : null,
                          color: selected ? null : AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.border,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? Colors.white
                                : AppTheme.textSub,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 정렬 + 카운트
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showSortSheet(
                        context: context,
                        current: _sortBy,
                      );
                      if (picked != null) {
                        setState(() => _sortBy = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_sortBy.icon,
                              color: AppTheme.primary, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            _sortBy.label,
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.textSub,
                            size: 16,
                          ),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
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
                                Icons.search_off_rounded,
                                color: AppTheme.textSub,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _openSearch.isNotEmpty
                                  ? '검색 결과가 없어요'
                                  : '$_selectedCategory 카테고리에\n오픈채팅이 없어요',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textMain,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () async {
                        ref.invalidate(openRoomsProvider);
                        await Future.delayed(
                            const Duration(milliseconds: 500));
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                            top: 4, bottom: 80),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => OpenRoomTile(
                          room: filtered[i],
                          myId: _myId,
                          rank: _sortBy == OpenRoomSort.popular
                              ? i + 1
                              : null,
                          onPreview: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OpenRoomPreviewScreen(
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
    );
  }
}

// ═══════════════════════════════════════════════════
// 보조 위젯들
// ═══════════════════════════════════════════════════

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _CircleIconButton({
    required this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppTheme.bgCard,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: enabled
                ? (iconColor ?? AppTheme.textMain)
                : AppTheme.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _MyRoomsEmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _MyRoomsEmptyState({required this.onCreate});

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
                Icons.groups_rounded,
                color: AppTheme.textSub,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '참여 중인 채팅방이 없어요',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '새 채팅방을 만들거나 오픈채팅에 참여해보세요',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('채팅방 만들기'),
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
        ),
      ),
    );
  }
}