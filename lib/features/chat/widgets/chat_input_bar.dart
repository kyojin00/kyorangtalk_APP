import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// ⌨️ 입력 바 위젯
// ═══════════════════════════════════════════════════
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool sending;
  final VoidCallback onAttachment;
  final VoidCallback onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.sending,
    required this.onAttachment,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
          color: AppTheme.bg,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            // + 버튼 (첨부)
            GestureDetector(
              onTap: (!enabled || sending) ? null : onAttachment,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Icon(Icons.add,
                    color: AppTheme.textSub, size: 24),
              ),
            ),
            const SizedBox(width: 8),

            // 텍스트 입력
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(
                      color: AppTheme.textMain, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '메시지 보내기...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 전송 버튼
            GestureDetector(
              onTap: (!enabled || sending) ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (!enabled || sending)
                      ? AppTheme.border
                      : AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}