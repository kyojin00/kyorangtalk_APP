import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/message_model.dart';

// ═══════════════════════════════════════════════════
// 📌 고정 메시지 배너
// ═══════════════════════════════════════════════════
class PinnedMessageBanner extends StatelessWidget {
  final String pinnedMessage;
  final VoidCallback onUnpin;

  const PinnedMessageBanner({
    super.key,
    required this.pinnedMessage,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin, color: AppTheme.primary, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pinnedMessage,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onUnpin,
            child: Icon(Icons.close, color: AppTheme.textSub, size: 16),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 💬 답장 미리보기
// ═══════════════════════════════════════════════════
class ReplyPreview extends StatelessWidget {
  final MessageModel replyTo;
  final bool isMyReply;
  final String partnerName;
  final VoidCallback onCancel;

  const ReplyPreview({
    super.key,
    required this.replyTo,
    required this.isMyReply,
    required this.partnerName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
            top: BorderSide(color: AppTheme.border),
            bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMyReply ? '나' : partnerName,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  replyTo.content,
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSub),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.textSub, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 📅 날짜 구분선
// ═══════════════════════════════════════════════════
class DateDivider extends StatelessWidget {
  final String label;

  const DateDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppTheme.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label,
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 11)),
          ),
          Expanded(child: Divider(color: AppTheme.border)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 💭 빈 상태
// ═══════════════════════════════════════════════════
class EmptyChatState extends StatelessWidget {
  final String partnerName;

  const EmptyChatState({super.key, required this.partnerName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💬', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            '$partnerName님과 대화를 시작해보세요!',
            style: TextStyle(color: AppTheme.textSub, fontSize: 13),
          ),
        ],
      ),
    );
  }
}