import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../chat/services/link_preview_service.dart';
import '../../chat/widgets/file_bubble.dart';
import '../../chat/widgets/game_bubble.dart';
import '../../chat/widgets/link_preview_card.dart';
import '../../chat/widgets/linkified_text.dart';
import '../../chat/widgets/multi_image_grid.dart';
import '../../chat/widgets/reaction_chips.dart';
import '../../chat/widgets/voice_message_bubble.dart';
import '../../polls/widgets/poll_bubble.dart';
import '../models/group_message_model.dart';

// ═══════════════════════════════════════════════════
// 💬 그룹 메시지 버블
// ═══════════════════════════════════════════════════
class GroupMessageBubble extends StatelessWidget {
  final GroupMessageModel msg;
  final String roomId;
  final bool isMe;
  final bool showSenderInfo;
  final String timeStr;
  final VoidCallback? onAvatarTap;

  const GroupMessageBubble({
    super.key,
    required this.msg,
    required this.roomId,
    required this.isMe,
    required this.showSenderInfo,
    required this.timeStr,
    this.onAvatarTap,
  });

  // ⭐ 텍스트 렌더 - URL 자동 감지 + isMe면 흰색
  Widget _buildText(String text, {bool deleted = false}) {
    if (deleted) {
      return Text(
        '삭제된 메시지예요',
        style: TextStyle(
          color: isMe ? Colors.white.withOpacity(0.7) : AppTheme.textSub,
          fontSize: 14,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return LinkifiedText(
      text: text,
      baseStyle: TextStyle(
        color: isMe ? Colors.white : AppTheme.textMain,
        fontSize: 14,
        height: 1.5,
      ),
      linkColor: isMe
          ? const Color(0xFFE0F2FE)
          : const Color(0xFF60A5FA),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (msg.pollId != null && !msg.isDeleted) {
      return PollBubble(pollId: msg.pollId!, isMe: isMe);
    }
    if (msg.fileUrl != null && !msg.isDeleted) {
      return FileBubble(
        fileUrl: msg.fileUrl!,
        fileName: msg.fileName ?? '파일',
        fileSize: msg.fileSize,
        fileType: msg.fileType,
        isMe: isMe,
      );
    }
    if (msg.gameData != null && !msg.isDeleted) {
      return GameBubble(
        gameData: msg.gameData!,
        isMe: isMe,
        content: msg.content,
      );
    }
    if (msg.audioUrl != null && !msg.isDeleted) {
      return VoiceMessageBubble(
        messageId: msg.id,
        audioUrl: msg.audioUrl!,
        duration: msg.audioDuration ?? 0,
        isMe: isMe,
        isGroup: true,
        initialTranscript: msg.audioTranscript,
        initialStatus: msg.audioTranscriptStatus,
      );
    }
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
        child: _buildText('', deleted: true),
      );
    }

    // 이미지 메시지
    if (msg.allImageUrls.isNotEmpty) {
      return MultiImageGrid(
        imageUrls: msg.allImageUrls,
        isMe: isMe,
        timeStr: timeStr,
        senderName: msg.senderNickname ?? '알 수 없음',
      );
    }

    // ⭐ 텍스트 메시지 - 버블 + URL 있으면 미리보기 카드
    final firstUrl = extractFirstUrl(msg.content);
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

    if (firstUrl == null) return bubble;

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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe && showSenderInfo)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 2),
                child: Text(
                  msg.senderNickname ?? '알 수 없음',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w600),
                ),
              ),

            if (msg.replyToContent != null)
              Padding(
                padding:
                    EdgeInsets.only(left: isMe ? 0 : 36, bottom: 2),
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
                        width: 2, height: 28,
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

            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  SizedBox(
                    width: 30,
                    child: showSenderInfo
                        ? GestureDetector(
                            onTap: onAvatarTap,
                            child: AvatarWidget(
                                url:  msg.senderAvatar,
                                name: msg.senderNickname,
                                size: 28),
                          )
                        : null,
                  ),
                if (!isMe) const SizedBox(width: 6),
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

            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 36,
                right: isMe ? 4 : 0,
              ),
              child: ReactionChips(
                messageId: msg.id,
                roomId: roomId,
                isGroup: true,
                isMe: isMe,
              ),
            ),
          ],
        ),
      ),
    );
  }
}