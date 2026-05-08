import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// ⌨️ 입력 바 위젯 (✨ 매직 톤 체크 버튼 내장)
// ═══════════════════════════════════════════════════
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool sending;
  final VoidCallback onAttachment;
  final VoidCallback onSend;
  final VoidCallback? onToneCheck;       // 수동 톤 체크
  final bool toneChecking;               // 톤 체크 중 표시

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.sending,
    required this.onAttachment,
    required this.onSend,
    this.onToneCheck,
    this.toneChecking = false,
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

            // 텍스트 입력 (✨ 매직 버튼 내장)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
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
                    if (onToneCheck != null)
                      _MagicCheckButton(
                        enabled: enabled && !sending,
                        loading: toneChecking,
                        onTap: onToneCheck!,
                      ),
                  ],
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

// ═══════════════════════════════════════════════════
// 매직 톤 체크 버튼 (입력창 안의 작은 ✨)
// ═══════════════════════════════════════════════════
class _MagicCheckButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _MagicCheckButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (!enabled || loading) ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                )
              : Icon(
                  Icons.auto_awesome,
                  color: AppTheme.primary,
                  size: 16,
                ),
        ),
      ),
    );
  }
}