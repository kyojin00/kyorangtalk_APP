import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════════
// 🚫 차단 배너
// ═══════════════════════════════════════════════════
class BlockedBanner extends StatelessWidget {
  final bool isBlockedByMe;
  final String partnerName;
  final VoidCallback? onUnblock;

  const BlockedBanner({
    super.key,
    required this.isBlockedByMe,
    required this.partnerName,
    this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
          color: AppTheme.bgCard,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.block,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isBlockedByMe
                        ? '차단된 사용자입니다'
                        : '메시지를 보낼 수 없어요',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBlockedByMe
                        ? '$partnerName님을 차단했어요'
                        : '상대방이 메시지 수신을 거부했어요',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            if (isBlockedByMe && onUnblock != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onUnblock,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '차단 해제',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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


// ═══════════════════════════════════════════════════
// 👤 친구 아님 액션 시트
// ═══════════════════════════════════════════════════
Future<void> showNotFriendActions(
  BuildContext context, {
  required String partnerName,
  required String? partnerAvatar,
  required String friendStatus,
  required VoidCallback onAddFriend,
  required VoidCallback onBlock,
}) async {
  await showModalBottomSheet(
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
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                AvatarWidget(
                  url: partnerAvatar,
                  name: partnerName,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partnerName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        friendStatus == 'pending'
                            ? '친구 요청 대기 중'
                            : '아직 친구가 아닙니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: friendStatus == 'pending'
                              ? AppTheme.primary
                              : AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: AppTheme.border, height: 1),
          if (friendStatus == 'none')
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded,
                  color: AppTheme.primary),
              title: const Text(
                '친구 추가',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                onAddFriend();
              },
            ),
          if (friendStatus == 'pending')
            ListTile(
              leading: Icon(Icons.schedule, color: AppTheme.textSub),
              title: Text('친구 요청 대기 중',
                  style: TextStyle(color: AppTheme.textSub)),
              enabled: false,
            ),
          ListTile(
            leading: const Icon(Icons.block, color: Color(0xFFEF4444)),
            title: const Text(
              '차단하기',
              style: TextStyle(
                  color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              onBlock();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}