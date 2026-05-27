import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../reports/widgets/report_dialog.dart';

// ═══════════════════════════════════════════════════
// 🔓 DeletedMessageDialog
//
// 위치: lib/features/chat/widgets/deleted_message_dialog.dart
//
// 삭제된 메시지를 길게 눌렀을 때 원본을 보여주는 바텀시트.
// - 수신자만 호출 (서버 RPC가 한 번 더 검증)
// - 24시간 이내 메시지만 복원
// - 신고 버튼 함께 제공
// ═══════════════════════════════════════════════════

/// DM 삭제 메시지 복원 시도
Future<void> showRestoreDeletedDmDialog({
  required BuildContext context,
  required String messageId,
  required String senderId,
  required String roomId,
  required String senderNickname,
}) async {
  await _showRestore(
    context: context,
    rpcName: 'get_deleted_dm_content',
    messageId: messageId,
    senderId: senderId,
    roomId: roomId,
    senderNickname: senderNickname,
  );
}

/// 그룹 삭제 메시지 복원 시도
Future<void> showRestoreDeletedGroupDialog({
  required BuildContext context,
  required String messageId,
  required String senderId,
  required String roomId,
  required String senderNickname,
}) async {
  await _showRestore(
    context: context,
    rpcName: 'get_deleted_group_content',
    messageId: messageId,
    senderId: senderId,
    roomId: roomId,
    senderNickname: senderNickname,
  );
}

Future<void> _showRestore({
  required BuildContext context,
  required String rpcName,
  required String messageId,
  required String senderId,
  required String roomId,
  required String senderNickname,
}) async {
  // 로딩
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: CircularProgressIndicator(color: AppTheme.primary),
    ),
  );

  String? rawContent;
  String? errorCode;
  try {
    final result = await Supabase.instance.client.rpc(
      rpcName,
      params: {'p_message_id': messageId},
    );
    rawContent = result as String?;
  } on PostgrestException catch (e) {
    errorCode = e.message;
  } catch (e) {
    errorCode = e.toString();
  }

  if (!context.mounted) return;
  Navigator.pop(context); // 로딩 닫기

  if (rawContent == null || rawContent.isEmpty) {
    _showErrorSnack(context, errorCode);
    return;
  }

  // ⭐ promotion이 클로저에 전파되도록 로컬 final 변수로 받음
  final String originalContent = rawContent;

  // 원본 표시 바텀시트
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 헤더
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lock_open_rounded,
                      color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '삭제된 메시지',
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$senderNickname님이 지운 메시지예요',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 원본 내용
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: SelectableText(
                originalContent,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 안내
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.textSub, size: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '삭제 후 24시간 안에만 볼 수 있어요',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      showReportMessageDialog(
                        context: context,
                        messageId: messageId,
                        senderId: senderId,
                        roomId: roomId,
                        messageContent: originalContent,
                        senderNickname: senderNickname,
                      );
                    },
                    icon: const Icon(
                      Icons.flag_outlined,
                      color: Color(0xFFEF4444),
                      size: 16,
                    ),
                    label: const Text(
                      '신고하기',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _showErrorSnack(BuildContext context, String? errorCode) {
  String message;
  final code = errorCode ?? '';
  if (code.contains('restore_window_expired')) {
    message = '삭제된 지 24시간이 지나 볼 수 없어요';
  } else if (code.contains('legacy_deleted')) {
    message = '옛 버전에서 삭제돼 복원할 수 없어요';
  } else if (code.contains('sender_cannot_restore')) {
    message = '내가 지운 메시지는 볼 수 없어요';
  } else if (code.contains('message_not_deleted')) {
    message = '삭제된 메시지가 아니에요';
  } else if (code.contains('not_room_member')) {
    message = '권한이 없어요';
  } else {
    message = '원본을 불러올 수 없어요';
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}