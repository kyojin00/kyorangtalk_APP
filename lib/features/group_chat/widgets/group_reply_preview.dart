import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_message_model.dart';

// ═══════════════════════════════════════════════════
// 💬 GroupReplyPreview — 답장 미리보기 (그룹용)
//
// - 그라데이션 컬러 바
// - 발신자 아바타 (그룹에서 누가 보냈는지 명확)
// - 닫기 버튼 원형
// - 상하 보더 + bgCard 배경
// ═══════════════════════════════════════════════════

class GroupReplyPreview extends StatelessWidget {
  final GroupMessageModel replyTo;
  final VoidCallback onCancel;

  const GroupReplyPreview({
    super.key,
    required this.replyTo,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final senderName = replyTo.senderNickname ?? '알 수 없음';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(
              color: AppTheme.border.withOpacity(0.6), width: 0.8),
          bottom: BorderSide(
              color: AppTheme.border.withOpacity(0.6), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // 그라데이션 컬러 바
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primaryLight,
                  AppTheme.primary,
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // 발신자 아바타
          AvatarWidget(
            url: replyTo.senderAvatar,
            name: senderName,
            size: 28,
          ),
          const SizedBox(width: 10),

          // 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.reply_rounded,
                        size: 11, color: AppTheme.primary),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '$senderName에게 답장',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSub,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // 닫기 버튼 — 원형
          SizedBox(
            width: 30,
            height: 30,
            child: ClipOval(
              child: Material(
                color: AppTheme.bg,
                child: InkWell(
                  onTap: onCancel,
                  child: Center(
                    child: Icon(
                      Icons.close_rounded,
                      color: AppTheme.textSub,
                      size: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}