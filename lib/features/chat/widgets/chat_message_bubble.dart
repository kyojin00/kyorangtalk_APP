import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../polls/widgets/poll_bubble.dart';
import '../models/message_model.dart';
import '../services/link_preview_service.dart';                 // ⭐ NEW
import 'file_bubble.dart';
import 'game_bubble.dart';
import 'link_preview_card.dart';                                // ⭐ NEW
import 'linkified_text.dart';                                   // ⭐ NEW
import 'multi_image_grid.dart';
import 'reaction_chips.dart';
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
  final String roomId;
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
    required this.roomId,
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

  // ⭐ 텍스트 메시지 렌더 (URL 자동 감지 + 검색 하이라이트)
  Widget _buildText(String text) {
    if (msg.isDeleted) {
      return Text(
        '삭제된 메시지예요',
        style: TextStyle(
          color: isMe
              ? Colors.white.withOpacity(0.7)
              : AppTheme.textSub,
          fontSize: 14,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return LinkifiedText(
      text: text,
      baseStyle: TextStyle(
        // ⭐ 보낸 메시지는 보라색 배경이라 흰색 텍스트로 가독성 확보
        color: isMe ? Colors.white : AppTheme.textMain,
        fontSize: 14,
        height: 1.5,
      ),
      searchQuery: searchQuery,
      // 보낸 사람 색상에 맞춰 링크 색
      linkColor: isMe
          ? const Color(0xFFE0F2FE) // 보낸 메시지 (purple bubble): 밝은 하늘색
          : const Color(0xFF60A5FA), // 받은 메시지: 표준 파랑
    );
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
        child: _buildText(msg.content),
      );
    }

    // ⭐ 이미지 메시지 (단일 + 다중)
    if (msg.allImageUrls.isNotEmpty) {
      return MultiImageGrid(
        imageUrls: msg.allImageUrls,
        isMe: isMe,
        timeStr: timeStr,
        senderName: partnerName,
      );
    }

    // ⭐⭐⭐ 텍스트 메시지 - 버블 + URL 있으면 미리보기 카드 같이
    final firstUrl = extractFirstUrl(msg.content);
    print('🔗 [Bubble] msgId=${msg.id} content="${msg.content}" '
        'firstUrl=$firstUrl');

    final bubble = Container(
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
      child: _buildText(msg.content),
    );

    if (firstUrl == null) {
      print('🔗 [Bubble] firstUrl null → bubble만 반환');
      return bubble;
    }

    print('🔗 [Bubble] firstUrl 있음 → Column(bubble + LinkPreviewCard) 반환');
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        LinkPreviewCard(url: firstUrl, isMe: isMe),
      ],
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

              // 메시지 반응 칩
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 0 : 34,
                  right: isMe ? 4 : 0,
                ),
                child: ReactionChips(
                  messageId: msg.id,
                  roomId: roomId,
                  isGroup: false,
                  isMe: isMe,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}