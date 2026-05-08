import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pending_message_store.dart';

/// ═══════════════════════════════════════════════════
/// FailedMessageBubble
///
/// 채팅 흐름 안에 실패한 메시지를 보여주는 말풍선
/// - 카카오톡처럼 메시지 옆에 ↻ (재전송) 와 ✕ (삭제) 버튼
/// - 회색 + 빨간 테두리로 실패 상태 표시
/// ═══════════════════════════════════════════════════
class FailedMessageBubble extends StatelessWidget {
  final PendingMessage message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final bool isRetrying;
  final String timeStr;

  const FailedMessageBubble({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.timeStr,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 좌측: 액션 버튼 (재전송 / 삭제)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 삭제 버튼 (왼쪽)
                  _ActionIconButton(
                    icon: Icons.close,
                    color: AppTheme.textSub,
                    onTap: isRetrying ? null : onCancel,
                  ),
                  const SizedBox(width: 4),
                  // 재전송 버튼 (왼쪽)
                  _ActionIconButton(
                    icon: Icons.refresh,
                    color: const Color(0xFFEF4444),
                    onTap: isRetrying ? null : onRetry,
                    isLoading: isRetrying,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // "전송 실패" 라벨
              Text(
                '전송 실패',
                style: TextStyle(
                  fontSize: 10,
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(width: 6),

          // 우측: 메시지 말풍선 (실패 스타일)
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(
                  color: const Color(0xFFEF4444).withOpacity(0.4),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Text(
                message.content,
                style: TextStyle(
                  color: AppTheme.textMain.withOpacity(0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: isLoading
              ? Padding(
                  padding: const EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Icon(icon, color: color, size: 15),
        ),
      ),
    );
  }
}