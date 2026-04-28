import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/message_model.dart';

// ═══════════════════════════════════════════════════
// 💬 메시지 옵션 시트
// ═══════════════════════════════════════════════════
Future<void> showMessageOptionsSheet(
  BuildContext context, {
  required MessageModel msg,
  required bool isMe,
  required bool isAnyBlocked,
  required VoidCallback onReply,
  required VoidCallback onCopy,
  required VoidCallback onPin,
  required VoidCallback onReport,
  required VoidCallback onDelete,
}) async {
  final isSpecial = msg.audioUrl != null ||
      msg.imageUrl != null ||
      msg.gameData != null ||
      msg.pollId != null ||
      msg.fileUrl != null;

  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
          if (!isAnyBlocked)
            _sheetItem(context, Icons.reply_rounded, '답장',
                AppTheme.textMain, onReply),
          if (!isSpecial && !msg.isDeleted)
            _sheetItem(context, Icons.copy_outlined, '복사',
                AppTheme.textMain, onCopy),
          if (!isSpecial && !msg.isDeleted)
            _sheetItem(context, Icons.push_pin_outlined, '고정',
                AppTheme.textMain, onPin),
          if (!isMe && !msg.isDeleted)
            _sheetItem(context, Icons.flag_outlined, '메시지 신고',
                const Color(0xFFEF4444), onReport, bold: true),
          if (isMe && !msg.isDeleted)
            _sheetItem(context, Icons.delete_outline, '삭제',
                const Color(0xFFEF4444), onDelete, bold: true),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 🔕 음소거 옵션 시트
// ═══════════════════════════════════════════════════
Future<String?> showMuteOptionsSheet(
  BuildContext context, {
  required bool isMuted,
}) async {
  return await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '알림 설정',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain),
              ),
            ),
          ),
          if (isMuted)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined,
                  color: AppTheme.primary),
              title: const Text('알림 켜기',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'unmute'),
            )
          else ...[
            ListTile(
              leading: Icon(Icons.notifications_off_outlined,
                  color: AppTheme.textMain),
              title: Text('1시간 동안 알림 끄기',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(ctx, '1h'),
            ),
            ListTile(
              leading: Icon(Icons.notifications_off_outlined,
                  color: AppTheme.textMain),
              title: Text('8시간 동안 알림 끄기',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(ctx, '8h'),
            ),
            ListTile(
              leading: Icon(Icons.notifications_off_outlined,
                  color: AppTheme.textMain),
              title: Text('24시간 동안 알림 끄기',
                  style: TextStyle(color: AppTheme.textMain)),
              onTap: () => Navigator.pop(ctx, '24h'),
            ),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_on,
                  color: Color(0xFFEF4444)),
              title: const Text('계속 끄기',
                  style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'forever'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 🚫 차단 확인 다이얼로그
// ═══════════════════════════════════════════════════
Future<bool> showBlockConfirmDialog(
  BuildContext context,
  String partnerName,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      title: Text(
        '$partnerName님 차단하기',
        style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16),
      ),
      content: Text(
        '차단하면 메시지를 주고받을 수 없어요.\n차단은 설정에서 해제할 수 있어요.',
        style:
            TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('차단',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}

// ═══════════════════════════════════════════════════
// ✅ 차단 해제 다이얼로그
// ═══════════════════════════════════════════════════
Future<bool> showUnblockConfirmDialog(
  BuildContext context,
  String partnerName,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      title: Text('차단 해제',
          style: TextStyle(
              color: AppTheme.textMain, fontWeight: FontWeight.w700)),
      content: Text(
        '$partnerName님의 차단을 해제하시겠어요?\n다시 메시지를 주고받을 수 있어요.',
        style: TextStyle(color: AppTheme.textSub, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('해제',
              style: TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}

// ═══════════════════════════════════════════════════
// 🚪 채팅방 나가기 다이얼로그
// ═══════════════════════════════════════════════════
Future<bool> showLeaveChatConfirmDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      title: Text('채팅방 나가기',
          style: TextStyle(
              color: AppTheme.textMain, fontWeight: FontWeight.w700)),
      content: Text(
        '채팅방을 나가면 채팅 목록에서 사라져요.\n다시 메시지를 받으면 복구돼요.',
        style: TextStyle(color: AppTheme.textSub, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('나가기',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return result == true;
}

// ═══════════════════════════════════════════════════
// 🔧 내부 헬퍼
// ═══════════════════════════════════════════════════
Widget _sheetItem(
  BuildContext context,
  IconData icon,
  String label,
  Color color,
  VoidCallback onTap, {
  bool bold = false,
}) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(
      label,
      style: TextStyle(
        color: color,
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
    onTap: () {
      Navigator.pop(context);
      onTap();
    },
  );
}