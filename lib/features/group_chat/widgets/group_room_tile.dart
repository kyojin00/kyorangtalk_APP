import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';

// ═══════════════════════════════════════════════════
// 내 채팅방 타일 (그룹/오픈 공통)
//
// 위치: lib/features/group_chat/widgets/group_room_tile.dart
// ═══════════════════════════════════════════════════

class GroupRoomTile extends StatelessWidget {
  final GroupRoomModel room;
  final String timeAgo;
  final bool selectionMode;
  final bool isSelected;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const GroupRoomTile({
    super.key,
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
            color: isSelected
                ? AppTheme.primary.withOpacity(0.15)
                : (isUnread
                    ? AppTheme.primary.withOpacity(0.08)
                    : Colors.transparent),
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
              // ─── 체크박스 (선택 모드)
              if (selectionMode) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
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

              // ─── 아바타 + 뱃지
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
                      url: room.avatarUrl,
                      name: room.name,
                      size: 52,
                    ),
                  ),
                  // 오픈채팅 뱃지
                  if (room.isOpen)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.bg, width: 2),
                        ),
                        child: const Icon(Icons.public,
                            color: Colors.white, size: 9),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),

              // ─── 이름 + 메시지
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (room.hasPassword) ...[
                          Icon(Icons.lock,
                              size: 12, color: AppTheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            room.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: AppTheme.textMain,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${room.memberCount}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSub,
                            ),
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 4),
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
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              // ─── 시간 + 안 읽음
              if (!selectionMode) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timeAgo.isNotEmpty)
                      Text(
                        timeAgo,
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
            ],
          ),
        ),
      ),
    );
  }
}