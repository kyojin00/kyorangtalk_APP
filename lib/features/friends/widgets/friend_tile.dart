import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 친구/요청 타일 위젯
//
// 위치: lib/features/friends/widgets/friend_tile.dart
//
// - FriendTile : 친구 목록의 한 줄 (탭하면 프로필, 채팅 버튼)
// - RequestTile: 받은 친구 요청의 한 줄 (수락/거절 버튼)
// ═══════════════════════════════════════════════

class FriendTile extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onTap;
  final VoidCallback onChat;

  const FriendTile({
    super.key,
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
              size: 46,
            ),
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

class RequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const RequestTile({
    super.key,
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
                  color: AppTheme.textMain),
            ),
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