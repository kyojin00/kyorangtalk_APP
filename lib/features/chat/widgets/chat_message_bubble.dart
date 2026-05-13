import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../polls/widgets/poll_bubble.dart';
import '../models/message_model.dart';
import '../services/link_preview_service.dart';
import 'file_bubble.dart';
import 'game_bubble.dart';
import 'link_preview_card.dart';
import 'linkified_text.dart';
import 'multi_image_grid.dart';
import 'reaction_chips.dart';
import 'voice_message_bubble.dart';

// ═══════════════════════════════════════════════════
// 💬 MessageBubble — 리디자인
//
// 변경:
// - 내 메시지: primary 그라데이션 + 그림자
// - 상대 메시지: bgCard 카드 + 미세 보더 + 그림자
// - 답장 미리보기: 컬러 바 + 미세 배경 (전송자 색에 맞춤)
// - 모서리: 18px (꼬리 4px) → 더 부드럽게
// - 시간: 더 작고 미세하게
// - 검색 하이라이트: primary 글로우
// - 삭제된 메시지: 흐릿한 이탤릭 + 미세 배경
// ═══════════════════════════════════════════════════

class MessageGroup {
  final String label;
  final List<MessageModel> items;
  MessageGroup(this.label, this.items);
}

class MessageListItem {
  final String? dateLabel;
  final MessageModel? message;

  MessageListItem.dateDivider(this.dateLabel) : message = null;
  MessageListItem.message(this.message) : dateLabel = null;

  bool get isDivider => dateLabel != null;
}

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

  // ═══════════════════════════════════════════════════
  // 텍스트 렌더 (URL 자동 감지 + 검색 하이라이트)
  // ═══════════════════════════════════════════════════
  Widget _buildText(String text) {
    if (msg.isDeleted) {
      return Text(
        '삭제된 메시지예요',
        style: TextStyle(
          color: isMe
              ? Colors.white.withOpacity(0.75)
              : AppTheme.textSub,
          fontSize: 14,
          height: 1.5,
          fontStyle: FontStyle.italic,
          letterSpacing: -0.2,
        ),
      );
    }
    return LinkifiedText(
      text: text,
      baseStyle: TextStyle(
        color: isMe ? Colors.white : AppTheme.textMain,
        fontSize: 14.5,
        height: 1.45,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w500,
      ),
      searchQuery: searchQuery,
      linkColor: isMe
          ? const Color(0xFFE0F2FE)
          : const Color(0xFF60A5FA),
    );
  }

  // ═══════════════════════════════════════════════════
  // 버블 데코레이션 (내/상대 구분)
  // ═══════════════════════════════════════════════════
  BoxDecoration _bubbleDecoration() {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    if (msg.isDeleted) {
      return BoxDecoration(
        color: isMe
            ? AppTheme.primary.withOpacity(0.4)
            : AppTheme.bgCard.withOpacity(0.6),
        borderRadius: radius,
        border: Border.all(
          color: isMe
              ? AppTheme.primary.withOpacity(0.3)
              : AppTheme.border,
        ),
      );
    }

    if (isMe) {
      // 내 메시지: primary 그라데이션 + 그림자
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.88),
          ],
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      );
    }

    // 상대 메시지: 카드 + 미세 보더 + 그림자
    return BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: radius,
      border: Border.all(color: AppTheme.border, width: 0.8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
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
      );
    }

    if (msg.isDeleted) {
      return Container(
        decoration: _bubbleDecoration(),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _buildText(msg.content),
      );
    }

    if (msg.allImageUrls.isNotEmpty) {
      return MultiImageGrid(
        imageUrls: msg.allImageUrls,
        isMe: isMe,
        timeStr: timeStr,
        senderName: partnerName,
      );
    }

    final firstUrl = extractFirstUrl(msg.content);

    final bubble = Container(
      decoration: _bubbleDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: _buildText(msg.content),
    );

    if (firstUrl == null) {
      return bubble;
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        const SizedBox(height: 4),
        LinkPreviewCard(url: firstUrl, isMe: isMe),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: isHighlighted
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.15),
                    AppTheme.primary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.3),
                ),
              )
            : null,
        padding: isHighlighted
            ? const EdgeInsets.symmetric(vertical: 4, horizontal: 4)
            : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // ═══════════════════════════════════════
            // 답장 미리보기 — 더 세련되게
            // ═══════════════════════════════════════
            if (msg.replyToContent != null)
              Padding(
                padding: EdgeInsets.only(
                    left: isMe ? 0 : 36,
                    right: isMe ? 4 : 0,
                    bottom: 3),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.65,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppTheme.primary.withOpacity(0.12)
                          : AppTheme.bgCard.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isMe
                            ? AppTheme.primary.withOpacity(0.25)
                            : AppTheme.border,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 3,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppTheme.primaryLight,
                                AppTheme.primary,
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(2),
                          ),
                          margin: const EdgeInsets.only(right: 8),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isMe ? '내 메시지에 답장' : partnerName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                msg.replyToContent!,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSub,
                                    height: 1.3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ═══════════════════════════════════════
            // 버블 + 시간 + 아바타
            // ═══════════════════════════════════════
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) ...[
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: AvatarWidget(
                          url: partnerAvatar,
                          name: partnerName,
                          size: 30),
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                // 내 메시지: 시간을 왼쪽에
                if (isMe) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(context).size.width * 0.7,
                    ),
                    child: _buildContent(context),
                  ),
                ),
                // 상대 메시지: 시간을 오른쪽에
                if (!isMe) ...[
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // ═══════════════════════════════════════
            // 리액션 칩
            // ═══════════════════════════════════════
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 37,
                right: isMe ? 4 : 0,
                top: 2,
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
    );
  }
}