import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../call/models/call_model.dart';
import '../../call/widgets/call_button.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

// ═══════════════════════════════════════════════════
// 📱 ChatAppBar — 리디자인 (원형 버튼 정렬 수정)
// ═══════════════════════════════════════════════════

AppBar buildChatAppBar({
  required BuildContext context,
  required ChatRoomModel room,
  required bool isStatusLoaded,
  required bool? isBlocked,
  required bool? isBlockedByPartner,
  required String? friendStatus,
  required bool isMuted,
  required VoidCallback onProfileTap,
  required VoidCallback onSearchTap,
  required VoidCallback onLeave,
  required VoidCallback onMute,
  required VoidCallback onUnblock,
  required VoidCallback onAddFriend,
  required VoidCallback onBlock,
  required VoidCallback onReport,
  required VoidCallback onNotFriendTap,
  required VoidCallback onGallery,
  required VoidCallback onMemory,
}) {
  final showNotFriendBadge = isStatusLoaded &&
      isBlocked == false &&
      isBlockedByPartner == false &&
      friendStatus != 'accepted';

  final canCall = isStatusLoaded &&
      isBlocked != true &&
      isBlockedByPartner != true;

  return AppBar(
    backgroundColor: AppTheme.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    leadingWidth: 56,
    leading: Center(
      child: _CircleIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () => Navigator.pop(context),
        iconColor: AppTheme.primaryLight,
      ),
    ),
    titleSpacing: 4,
    title: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onProfileTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 6),
          child: Row(
            children: [
              // 아바타 + 글로우 + 친구 상태 점
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: friendStatus == 'accepted'
                          ? [
                              BoxShadow(
                                color:
                                    AppTheme.primary.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: AvatarWidget(
                      url: room.partnerAvatar,
                      name: room.partnerName,
                      size: 36,
                    ),
                  ),
                  if (isStatusLoaded &&
                      isBlocked == false &&
                      isBlockedByPartner == false &&
                      friendStatus == 'accepted')
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
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
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            room.partnerName,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notifications_off_rounded,
                            color: AppTheme.textSub,
                            size: 14,
                          ),
                        ],
                        if (isStatusLoaded && isBlocked == true) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.block_rounded,
                              color: Color(0xFFEF4444), size: 14),
                        ],
                      ],
                    ),
                    if (showNotFriendBadge) ...[
                      const SizedBox(height: 3),
                      _NotFriendBadge(
                        friendStatus: friendStatus ?? 'none',
                        onTap: onNotFriendTap,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (canCall)
        CallButton(
          roomType: CallRoomType.dm,
          sourceRoomId: room.roomId,
        ),
      const SizedBox(width: 4),
      _CircleIconButton(
        icon: Icons.search_rounded,
        onTap: onSearchTap,
        iconColor: AppTheme.textMain,
      ),
      const SizedBox(width: 4),
      _MenuButton(
        isStatusLoaded: isStatusLoaded,
        isBlocked: isBlocked,
        isBlockedByPartner: isBlockedByPartner,
        friendStatus: friendStatus,
        isMuted: isMuted,
        onLeave: onLeave,
        onProfile: onProfileTap,
        onMute: onMute,
        onUnblock: onUnblock,
        onAddFriend: onAddFriend,
        onBlock: onBlock,
        onReport: onReport,
        onGallery: onGallery,
        onMemory: onMemory,
      ),
      const SizedBox(width: 10),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(0.5),
      child: Container(
        height: 0.5,
        color: AppTheme.border.withOpacity(0.5),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 🔍 검색 AppBar
// ═══════════════════════════════════════════════════
PreferredSizeWidget buildChatSearchAppBar({
  required BuildContext context,
  required TextEditingController searchController,
  required List<MessageModel> messages,
  required int searchIndex,
  required List<int> searchResults,
  required VoidCallback onClose,
  required void Function(String) onSearch,
  required VoidCallback onPrev,
  required VoidCallback onNext,
}) {
  return AppBar(
    backgroundColor: AppTheme.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    leadingWidth: 56,
    leading: Center(
      child: _CircleIconButton(
        icon: Icons.close_rounded,
        onTap: onClose,
        iconColor: AppTheme.textMain,
      ),
    ),
    titleSpacing: 4,
    title: Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded,
              size: 17, color: AppTheme.textSub),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: searchController,
              autofocus: true,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
              cursorColor: AppTheme.primary,
              decoration: InputDecoration(
                hintText: '메시지 검색',
                hintStyle: TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w400,
                ),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: onSearch,
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (searchResults.isNotEmpty)
        Center(
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${searchResults.length - searchIndex}/${searchResults.length}',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      _CircleIconButton(
        icon: Icons.keyboard_arrow_up_rounded,
        onTap: searchResults.isEmpty ? () {} : onPrev,
        iconColor: searchResults.isEmpty
            ? AppTheme.textMuted
            : AppTheme.textMain,
      ),
      const SizedBox(width: 4),
      _CircleIconButton(
        icon: Icons.keyboard_arrow_down_rounded,
        onTap: searchResults.isEmpty ? () {} : onNext,
        iconColor: searchResults.isEmpty
            ? AppTheme.textMuted
            : AppTheme.textMain,
      ),
      const SizedBox(width: 10),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(0.5),
      child: Container(
        height: 0.5,
        color: AppTheme.border.withOpacity(0.5),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 원형 아이콘 버튼 — Container가 보더/배경, ClipOval은 ripple만
// ═══════════════════════════════════════════════════
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(icon, color: iconColor, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 메뉴 버튼
// ═══════════════════════════════════════════════════
class _MenuButton extends StatelessWidget {
  final bool isStatusLoaded;
  final bool? isBlocked;
  final bool? isBlockedByPartner;
  final String? friendStatus;
  final bool isMuted;
  final VoidCallback onLeave;
  final VoidCallback onProfile;
  final VoidCallback onMute;
  final VoidCallback onUnblock;
  final VoidCallback onAddFriend;
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onGallery;
  final VoidCallback onMemory;

  const _MenuButton({
    required this.isStatusLoaded,
    required this.isBlocked,
    required this.isBlockedByPartner,
    required this.friendStatus,
    required this.isMuted,
    required this.onLeave,
    required this.onProfile,
    required this.onMute,
    required this.onUnblock,
    required this.onAddFriend,
    required this.onBlock,
    required this.onReport,
    required this.onGallery,
    required this.onMemory,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppTheme.bgCard,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.border),
      ),
      offset: const Offset(0, 44),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.more_horiz_rounded,
            color: AppTheme.textMain, size: 18),
      ),
      onSelected: (value) {
        switch (value) {
          case 'leave': onLeave(); break;
          case 'profile': onProfile(); break;
          case 'mute': onMute(); break;
          case 'unblock': onUnblock(); break;
          case 'add_friend': onAddFriend(); break;
          case 'block': onBlock(); break;
          case 'report': onReport(); break;
          case 'gallery': onGallery(); break;
          case 'memory': onMemory(); break;
        }
      },
      itemBuilder: (_) => _buildMenuItems(
        isStatusLoaded: isStatusLoaded,
        isBlocked: isBlocked,
        isBlockedByPartner: isBlockedByPartner,
        friendStatus: friendStatus,
        isMuted: isMuted,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 메뉴 아이템 빌더
// ═══════════════════════════════════════════════════
List<PopupMenuEntry<String>> _buildMenuItems({
  required bool isStatusLoaded,
  required bool? isBlocked,
  required bool? isBlockedByPartner,
  required String? friendStatus,
  required bool isMuted,
}) {
  if (!isStatusLoaded) {
    return [
      _menuItem('profile', Icons.person_outline_rounded, '프로필 보기',
          AppTheme.textSub, AppTheme.textMain),
      _menuItem('leave', Icons.exit_to_app_rounded, '채팅방 나가기',
          const Color(0xFFEF4444), const Color(0xFFEF4444),
          bold: true),
    ];
  }

  return [
    _menuItem('profile', Icons.person_outline_rounded, '프로필 보기',
        AppTheme.textSub, AppTheme.textMain),

    const PopupMenuDivider(height: 8),
    _menuItem('gallery', Icons.photo_library_rounded, '갤러리',
        AppTheme.textSub, AppTheme.textMain),
    _menuItem('memory', Icons.favorite_rounded, '추억',
        AppTheme.textSub, AppTheme.textMain),
    const PopupMenuDivider(height: 8),

    if (friendStatus == 'none' &&
        isBlocked == false &&
        isBlockedByPartner == false)
      _menuItem('add_friend', Icons.person_add_alt_1_rounded, '친구 추가',
          AppTheme.primary, AppTheme.primary, bold: true),
    if (isBlocked == false && isBlockedByPartner == false)
      _menuItem(
        'mute',
        isMuted
            ? Icons.notifications_active_rounded
            : Icons.notifications_off_rounded,
        isMuted ? '알림 켜기' : '알림 끄기',
        isMuted ? AppTheme.primary : AppTheme.textSub,
        isMuted ? AppTheme.primary : AppTheme.textMain,
        bold: isMuted,
      ),
    _menuItem('report', Icons.flag_outlined, '신고하기',
        const Color(0xFFFBBF24), const Color(0xFFFBBF24), bold: true),
    if (isBlocked == true)
      _menuItem('unblock', Icons.check_circle_outline_rounded, '차단 해제',
          AppTheme.primary, AppTheme.primary, bold: true),
    if (isBlocked == false)
      _menuItem('block', Icons.block_rounded, '차단하기',
          const Color(0xFFEF4444), const Color(0xFFEF4444),
          bold: true),
    const PopupMenuDivider(height: 8),
    _menuItem('leave', Icons.exit_to_app_rounded, '채팅방 나가기',
        const Color(0xFFEF4444), const Color(0xFFEF4444), bold: true),
  ];
}

PopupMenuItem<String> _menuItem(
  String value,
  IconData icon,
  String label,
  Color iconColor,
  Color textColor, {
  bool bold = false,
}) {
  return PopupMenuItem(
    value: value,
    height: 44,
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════
// 친구 아님 뱃지
// ═══════════════════════════════════════════════════
class _NotFriendBadge extends StatelessWidget {
  final String friendStatus;
  final VoidCallback onTap;

  const _NotFriendBadge({
    required this.friendStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = friendStatus == 'pending';
    final Color color =
        isPending ? AppTheme.primary : const Color(0xFFFBBF24);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.22),
              color.withOpacity(0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(0.35),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPending
                  ? Icons.schedule_rounded
                  : Icons.person_outline_rounded,
              color: color,
              size: 11,
            ),
            const SizedBox(width: 3),
            Text(
              isPending ? '요청 중' : '친구 아님',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}