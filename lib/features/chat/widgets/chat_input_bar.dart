import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// ⌨️ ChatInputBar — 리디자인 (모서리 버그 수정)
// ═══════════════════════════════════════════════════

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool sending;
  final VoidCallback onAttachment;
  final VoidCallback onSend;
  final VoidCallback? onToneCheck;
  final bool toneChecking;

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
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _focused != widget.focusNode.hasFocus) {
      setState(() => _focused = widget.focusNode.hasFocus);
    }
  }

  void _onTextChange() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (mounted && _hasText != has) {
      setState(() => _hasText = has);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.enabled && !widget.sending && _hasText;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: AppTheme.border.withOpacity(0.5),
              width: 0.8,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ─── + 버튼 ──────────────
            _AttachmentButton(
              enabled: widget.enabled && !widget.sending,
              onTap: widget.onAttachment,
            ),
            const SizedBox(width: 8),

            // ─── 텍스트 입력 + 매직 버튼 ──────
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _focused
                        ? AppTheme.primary.withOpacity(0.5)
                        : AppTheme.border,
                    width: _focused ? 1.5 : 1,
                  ),
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minHeight: 44),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          enabled: widget.enabled,
                          maxLines: 5,
                          minLines: 1,
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                            height: 1.35,
                          ),
                          cursorColor: AppTheme.primary,
                          decoration: InputDecoration(
                            hintText: widget.enabled
                                ? '메시지 보내기...'
                                : '입력 불가',
                            hintStyle: TextStyle(
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w400,
                            ),
                            // ⭐ 모든 보더 명시적으로 제거 (Theme 무시)
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) =>
                              canSend ? widget.onSend() : null,
                        ),
                      ),
                    ),
                    if (widget.onToneCheck != null)
                      Padding(
                        padding:
                            const EdgeInsets.only(right: 4, bottom: 4),
                        child: _MagicCheckButton(
                          enabled: widget.enabled &&
                              !widget.sending &&
                              _hasText,
                          loading: widget.toneChecking,
                          onTap: widget.onToneCheck!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // ─── 전송 버튼 ────────────────
            _SendButton(
              canSend: canSend,
              sending: widget.sending,
              onTap: widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 📎 첨부 버튼 — ClipOval로 ripple 잘라냄
// ═══════════════════════════════════════════════════
class _AttachmentButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _AttachmentButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: Material(
          color: AppTheme.bgCard,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(
                Icons.add_rounded,
                color:
                    enabled ? AppTheme.textMain : AppTheme.textMuted,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 📤 전송 버튼 — ClipOval로 ripple 잘라냄
// ═══════════════════════════════════════════════════
class _SendButton extends StatelessWidget {
  final bool canSend;
  final bool sending;
  final VoidCallback onTap;

  const _SendButton({
    required this.canSend,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: canSend
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: canSend
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primary,
                        AppTheme.primary.withOpacity(0.85),
                      ],
                    )
                  : null,
              color: canSend ? null : AppTheme.bgCard,
              shape: BoxShape.circle,
              border: canSend ? null : Border.all(color: AppTheme.border),
            ),
            child: InkWell(
              onTap: canSend ? onTap : null,
              child: Center(
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white),
                      )
                    : Icon(
                        Icons.arrow_upward_rounded,
                        color: canSend
                            ? Colors.white
                            : AppTheme.textMuted,
                        size: 22,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// ✨ 매직 톤 체크 버튼 — ClipOval로 ripple 잘라냄
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
    return SizedBox(
      width: 34,
      height: 34,
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: enabled
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primary.withOpacity(0.2),
                        AppTheme.primary.withOpacity(0.08),
                      ],
                    )
                  : null,
              color: enabled ? null : AppTheme.bgCard,
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled
                    ? AppTheme.primary.withOpacity(0.3)
                    : AppTheme.border,
                width: 0.8,
              ),
            ),
            child: InkWell(
              onTap: (!enabled || loading) ? null : onTap,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primary),
                        ),
                      )
                    : Icon(
                        Icons.auto_awesome_rounded,
                        color: enabled
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                        size: 17,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}