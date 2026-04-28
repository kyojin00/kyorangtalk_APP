import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/notifications/notification_service.dart';
import '../../features/chat/providers/chat_provider.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/friends/screens/friends_screen.dart';
import '../../features/group_chat/providers/group_chat_provider.dart';
import '../../features/group_chat/screens/group_chat_list_screen.dart';
import '../../features/profile/screens/settings_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _currentIndex;

  final _screens = const [
    FriendsScreen(),
    ChatListScreen(),
    GroupChatListScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    // ✨ 채팅 + 그룹 + 음소거 상태 모두 watch
    final roomsAsync     = ref.watch(chatRoomsProvider);
    final groupRoomsAsync = ref.watch(groupRoomsProvider);
    final mutedAsync     = ref.watch(mutedRoomsProvider);
    final mutedRooms     = mutedAsync.value ?? {};

    // ✨ 채팅 (DM) 안 읽음 - 음소거 방 제외
    final chatUnread = roomsAsync.value
            ?.where((r) => !mutedRooms.contains(r.roomId))
            .fold(0, (s, r) => s + r.unreadCount) ?? 0;

    // ✨ 그룹 안 읽음 - 음소거 방 제외
    final groupUnread = groupRoomsAsync.value
            ?.where((r) => !mutedRooms.contains(r.id))
            .fold(0, (s, r) => s + r.unreadCount) ?? 0;

    // ✨ 친구 요청 (대기 중) 카운트
    final pendingAsync = ref.watch(pendingRequestsProvider);
    final friendBadge = pendingAsync.value?.length ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
          color: AppTheme.bg,
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _TabItem(
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label: '친구',
                  isActive: _currentIndex == 0,
                  badge: friendBadge, // ✨ 친구 요청 배지
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _TabItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: '채팅',
                  isActive: _currentIndex == 1,
                  badge: chatUnread,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _TabItem(
                  icon: Icons.group_outlined,
                  activeIcon: Icons.group_rounded,
                  label: '그룹',
                  isActive: _currentIndex == 2,
                  badge: groupUnread, // ✨ 그룹 배지 추가!
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _TabItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '설정',
                  isActive: _currentIndex == 3,
                  badge: 0,
                  onTap: () => setState(() => _currentIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final int badge;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? AppTheme.primary : AppTheme.textSub,
                  size: 24,
                ),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.bg, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                          minWidth: 16, minHeight: 16),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? AppTheme.primary : AppTheme.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}