import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../call/models/call_model.dart';
import '../../call/widgets/call_button.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

// ═══════════════════════════════════════════════════
// 📱 일반 AppBar
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

  // ⭐ 통화 가능 조건: 차단 안 됐고 상태 로드 완료
  final canCall = isStatusLoaded &&
      isBlocked != true &&
      isBlockedByPartner != true;

  return AppBar(
    backgroundColor: AppTheme.bg,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios,
          color: AppTheme.primaryLight, size: 20),
      onPressed: () => Navigator.pop(context),
    ),
    titleSpacing: 0,
    title: GestureDetector(
      onTap: onProfileTap,
      child: Row(
        children: [
          AvatarWidget(
              url: room.partnerAvatar, name: room.partnerName, size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              room.partnerName,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showNotFriendBadge) ...[
            const SizedBox(width: 6),
            _NotFriendBadge(
              friendStatus: friendStatus ?? 'none',
              onTap: onNotFriendTap,
            ),
          ],
          if (isMuted) ...[
            const SizedBox(width: 6),
            Icon(Icons.notifications_off,
                color: AppTheme.textSub, size: 14),
          ],
          if (isStatusLoaded && isBlocked == true) ...[
            const SizedBox(width: 6),
            const Icon(Icons.block, color: Color(0xFFEF4444), size: 14),
          ],
        ],
      ),
    ),
    actions: [
      // ⭐ 통화 버튼 (차단 상태가 아닐 때만)
      if (canCall)
        CallButton(
          roomType: CallRoomType.dm,
          sourceRoomId: room.roomId,
        ),
      IconButton(
        icon: Icon(Icons.search, color: AppTheme.textSub),
        onPressed: onSearchTap,
      ),
      PopupMenuButton<String>(
        color: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        icon: Icon(Icons.more_vert, color: AppTheme.textSub),
        onSelected: (value) {
          switch (value) {
            case 'leave':      onLeave();      break;
            case 'profile':    onProfileTap(); break;
            case 'mute':       onMute();       break;
            case 'unblock':    onUnblock();    break;
            case 'add_friend': onAddFriend();  break;
            case 'block':      onBlock();      break;
            case 'report':     onReport();     break;
            case 'gallery':    onGallery();    break;
            case 'memory':     onMemory();     break;
          }
        },
        itemBuilder: (_) => _buildMenuItems(
          isStatusLoaded: isStatusLoaded,
          isBlocked: isBlocked,
          isBlockedByPartner: isBlockedByPartner,
          friendStatus: friendStatus,
          isMuted: isMuted,
        ),
      ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: AppTheme.border),
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
    leading: IconButton(
      icon: Icon(Icons.close, color: AppTheme.textSub, size: 20),
      onPressed: onClose,
    ),
    title: TextField(
      controller: searchController,
      autofocus: true,
      style: TextStyle(color: AppTheme.textMain, fontSize: 15),
      decoration: InputDecoration(
        hintText: '메시지 검색...',
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppTheme.textSub),
      ),
      onChanged: onSearch,
    ),
    actions: [
      if (searchResults.isNotEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '${searchResults.length - searchIndex}/${searchResults.length}',
              style: TextStyle(color: AppTheme.textSub, fontSize: 13),
            ),
          ),
        ),
      IconButton(
        icon: Icon(Icons.keyboard_arrow_up, color: AppTheme.textSub),
        onPressed: searchResults.isEmpty ? null : onPrev,
      ),
      IconButton(
        icon: Icon(Icons.keyboard_arrow_down, color: AppTheme.textSub),
        onPressed: searchResults.isEmpty ? null : onNext,
      ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: AppTheme.border),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 📋 메뉴 아이템
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
      _menuItem('profile', Icons.person_outline, '프로필 보기',
          AppTheme.textSub, AppTheme.textMain),
      _menuItem('leave', Icons.exit_to_app, '채팅방 나가기',
          const Color(0xFFEF4444), const Color(0xFFEF4444), bold: true),
    ];
  }

  return [
    _menuItem('profile', Icons.person_outline, '프로필 보기',
        AppTheme.textSub, AppTheme.textMain),

    // ⭐ NEW: 갤러리/추억 (대화 관련 묶음)
    const PopupMenuDivider(height: 1),
    _menuItem('gallery', Icons.photo_library_outlined, '갤러리',
        AppTheme.textSub, AppTheme.textMain),
    _menuItem('memory', Icons.favorite_outline, '추억',
        AppTheme.textSub, AppTheme.textMain),
    const PopupMenuDivider(height: 1),

    if (friendStatus == 'none' &&
        isBlocked == false &&
        isBlockedByPartner == false)
      _menuItem('add_friend', Icons.person_add_alt_1_rounded, '친구 추가',
          AppTheme.primary, AppTheme.primary, bold: true),
    if (isBlocked == false && isBlockedByPartner == false)
      _menuItem(
        'mute',
        isMuted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        isMuted ? '알림 켜기' : '알림 끄기',
        isMuted ? AppTheme.primary : AppTheme.textSub,
        isMuted ? AppTheme.primary : AppTheme.textMain,
        bold: isMuted,
      ),
    _menuItem('report', Icons.flag_outlined, '신고하기',
        const Color(0xFFEF4444), const Color(0xFFEF4444), bold: true),
    if (isBlocked == true)
      _menuItem('unblock', Icons.check_circle_outline, '차단 해제',
          AppTheme.primary, AppTheme.primary, bold: true),
    if (isBlocked == false)
      _menuItem('block', Icons.block, '차단하기',
          const Color(0xFFEF4444), const Color(0xFFEF4444), bold: true),
    _menuItem('leave', Icons.exit_to_app, '채팅방 나가기',
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
    child: Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════
// 🏷️ 친구 아님 뱃지
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isPending
              ? AppTheme.primary.withOpacity(0.15)
              : const Color(0xFFFBBF24).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPending
                ? AppTheme.primary.withOpacity(0.3)
                : const Color(0xFFFBBF24).withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPending ? Icons.schedule : Icons.person_outline,
              color: isPending ? AppTheme.primary : const Color(0xFFFBBF24),
              size: 11,
            ),
            const SizedBox(width: 3),
            Text(
              isPending ? '요청 중' : '친구 아님',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color:
                    isPending ? AppTheme.primary : const Color(0xFFFBBF24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}