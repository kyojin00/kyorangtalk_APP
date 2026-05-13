import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../call/models/call_model.dart';
import '../../call/widgets/call_button.dart';
import '../models/group_room_model.dart';

// ═══════════════════════════════════════════════════
// 👥 그룹 채팅 AppBar
// ═══════════════════════════════════════════════════
AppBar buildGroupChatAppBar({
  required BuildContext context,
  required GroupRoomModel room,
  required bool isMuted,
  required VoidCallback onTitleTap,
  required VoidCallback onMenuTap,
}) {
  return AppBar(
    backgroundColor: AppTheme.bg,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios,
          color: AppTheme.primaryLight, size: 20),
      onPressed: () => Navigator.pop(context),
    ),
    titleSpacing: 0,
    title: GestureDetector(
      onTap: onTitleTap,
      child: Row(
        children: [
          AvatarWidget(
              url: room.avatarUrl, name: room.name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        room.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMuted) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.notifications_off,
                          color: AppTheme.textSub, size: 14),
                    ],
                  ],
                ),
                Text(
                  '${room.memberCount}명',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      // ⭐ 통화 버튼 (그룹)
      CallButton(
        roomType: CallRoomType.group,
        sourceRoomId: room.id,
      ),
      IconButton(
        icon: Icon(Icons.menu, color: AppTheme.textSub),
        onPressed: onMenuTap,
      ),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: AppTheme.border),
    ),
  );
}