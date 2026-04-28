import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../polls/widgets/poll_bubble.dart';
import '../models/message_model.dart';
import 'file_bubble.dart';
import 'game_bubble.dart';
import 'voice_message_bubble.dart';

// ═══════════════════════════════════════════════════
// 📬 메시지 그룹 (날짜별)
// ═══════════════════════════════════════════════════
class MessageGroup {
  final String label;
  final List<MessageModel> items;
  MessageGroup(this.label, this.items);
}

// ═══════════════════════════════════════════════════
// 📋 리스트 아이템 (날짜 구분선 or 메시지)
// ═══════════════════════════════════════════════════
class MessageListItem {
  final String? dateLabel;
  final MessageModel? message;
  
  MessageListItem.dateDivider(this.dateLabel) : message = null;
  MessageListItem.message(this.message) : dateLabel = null;
  
  bool get isDivider => dateLabel != null;
}

// ═══════════════════════════════════════════════════
// 💬 메시지 버블 (DM)
// ═══════════════════════════════════════════════════
class MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final String timeStr;
  final bool isHighlighted;
  final String searchQuery;
  final String partnerName;
  final String? partnerAvatar;
  final void Function(String url) onImageTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onImageLoad;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.timeStr,
    required this.isHighlighted,
    required this.searchQuery,
    required this.partnerName,
    required this.partnerAvatar,
    required this.onImageTap,
    this.onAvatarTap,
    this.onImageLoad,
  });

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty || msg.isDeleted) {
      return Text(
        msg.isDeleted ? '삭제된 메시지예요' : text,
        style: TextStyle(
          color: msg.isDeleted ? AppTheme.textSub : AppTheme.textMain,
          fontSize: 14,
          height: 1.5,
          fontStyle: msg.isDeleted ? FontStyle.italic : FontStyle.normal,
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(
          text: text.substring(start),
          style: TextStyle(
              color: AppTheme.textMain, fontSize: 14, height: 1.5),
        ));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: TextStyle(
              color: AppTheme.textMain, fontSize: 14, height: 1.5),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w800,
          backgroundColor: Color(0xFFFBBF24),
        ),
      ));
      start = idx + query.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildContent(BuildContext context) {
    // ⭐ 투표 메시지
    if (msg.pollId != null && !msg.isDeleted) {
      return PollBubble(pollId: msg.pollId!, isMe: isMe);
    }

    // ⭐ 파일 메시지
    if (msg.fileUrl != null && !msg.isDeleted) {
      return FileBubble(
        fileUrl: msg.fileUrl!,
        fileName: msg.fileName ?? '파일',
        fileSize: msg.fileSize,
        fileType: msg.fileType,
        isMe: isMe,
      );
    }

    // ⭐ 게임 메시지
    if (msg.gameData != null && !msg.isDeleted) {
      return GameBubble(
        gameData: msg.gameData!,
        isMe: isMe,
        content: msg.content,
      );
    }

    // ⭐ 음성 메시지
    if (msg.audioUrl != null && !msg.isDeleted) {
      return VoiceMessageBubble(
        messageId: msg.id,
        audioUrl: msg.audioUrl!,
        duration: msg.audioDuration ?? 0,
        isMe: isMe,
      );
    }

    // 삭제된 메시지
    if (msg.isDeleted) {
      return Container(
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _buildHighlightedText(msg.content, searchQuery),
      );
    }

    // 이미지 메시지
    if (msg.imageUrl != null) {
      return Container(
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary : AppTheme.border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: GestureDetector(
          onTap: () => onImageTap(msg.imageUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            child: Stack(
              children: [
                Image.network(
                  msg.imageUrl!,
                  width: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => onImageLoad?.call());
                      return child;
                    }
                    return Container(
                      width: 200,
                      height: 150,
                      color: AppTheme.border,
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.zoom_in,
                        color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 텍스트 메시지
    return Container(
      decoration: BoxDecoration(
        color: isMe ? AppTheme.primary : AppTheme.border,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: _buildHighlightedText(msg.content, searchQuery),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: isHighlighted
            ? BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Padding(
          padding: isHighlighted
              ? const EdgeInsets.symmetric(vertical: 2)
              : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // 답장 미리보기
              if (msg.replyToContent != null)
                Padding(
                  padding: EdgeInsets.only(left: isMe ? 0 : 36, bottom: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 2,
                          height: 28,
                          color: AppTheme.primary,
                          margin: const EdgeInsets.only(right: 8),
                        ),
                        Flexible(
                          child: Text(
                            msg.replyToContent!,
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textSub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 버블 + 시간 + 아바타
              Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe) ...[
                    GestureDetector(
                      onTap: onAvatarTap,
                      child: AvatarWidget(
                          url: partnerAvatar, name: partnerName, size: 28),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (isMe) ...[
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 10, color: AppTheme.textMuted)),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      child: _buildContent(context),
                    ),
                  ),
                  if (!isMe) ...[
                    const SizedBox(width: 4),
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 10, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}