import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 친구/요청 타일 위젯
//
// 위치: lib/features/friends/widgets/friend_tile.dart
//
// - FriendTile : 친구 목록 한 줄
//   - 탭: 프로필 열기
//   - 채팅 버튼: 채팅 시작
//   - 길게 누르기: 액션 시트 (즐겨찾기/차단/신고/삭제) ⭐ NEW
//   - 즐겨찾기는 좌측 별표 표시
// - RequestTile: 친구 요청 한 줄
// ═══════════════════════════════════════════════

class FriendTile extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onTap;
  final VoidCallback onChat;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;
  final VoidCallback? onRemove;

  const FriendTile({
    super.key,
    required this.friend,
    required this.onTap,
    required this.onChat,
    this.onToggleFavorite,
    this.onBlock,
    this.onReport,
    this.onRemove,
  });

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FriendActionSheet(
        friend: friend,
        onToggleFavorite: () {
          Navigator.pop(context);
          onToggleFavorite?.call();
        },
        onBlock: () {
          Navigator.pop(context);
          onBlock?.call();
        },
        onReport: () {
          Navigator.pop(context);
          onReport?.call();
        },
        onRemove: () {
          Navigator.pop(context);
          onRemove?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showActionSheet(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(
                  url: friend.avatarUrl,
                  name: friend.nickname,
                  size: 46,
                ),
                if (friend.isFavorite)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTheme.bg, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.star_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
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

// ═══════════════════════════════════════════════
// 친구 액션 시트 (길게 누르기 → 표시)
// ═══════════════════════════════════════════════
class _FriendActionSheet extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onRemove;

  const _FriendActionSheet({
    required this.friend,
    required this.onToggleFavorite,
    required this.onBlock,
    required this.onReport,
    required this.onRemove,
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

            // 헤더 — 프로필 요약
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  AvatarWidget(
                    url: friend.avatarUrl,
                    name: friend.nickname,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          friend.nickname,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (friend.statusMessage != null &&
                            friend.statusMessage!.isNotEmpty)
                          Text(
                            friend.statusMessage!,
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

            // 액션 1: 즐겨찾기 토글
            _ActionRow(
              icon: friend.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              iconColor: friend.isFavorite
                  ? const Color(0xFFFFB800)
                  : AppTheme.textSub,
              label: friend.isFavorite
                  ? '즐겨찾기 해제'
                  : '즐겨찾기 추가',
              onTap: onToggleFavorite,
            ),

            // 액션 2: 신고
            _ActionRow(
              icon: Icons.flag_outlined,
              iconColor: AppTheme.textSub,
              label: '신고하기',
              onTap: onReport,
            ),

            // 액션 3: 차단
            _ActionRow(
              icon: Icons.block,
              iconColor: const Color(0xFFEF4444),
              label: '차단하기',
              labelColor: const Color(0xFFEF4444),
              onTap: onBlock,
            ),

            // 액션 4: 삭제
            _ActionRow(
              icon: Icons.person_remove_outlined,
              iconColor: const Color(0xFFEF4444),
              label: '친구 삭제',
              labelColor: const Color(0xFFEF4444),
              onTap: onRemove,
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
  final Color? labelColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
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
                fontWeight: FontWeight.w500,
                color: labelColor ?? AppTheme.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 요청 타일 (변경 없음)
// ═══════════════════════════════════════════════
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