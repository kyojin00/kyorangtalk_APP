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
// 💬 GroupMessageBubble — 리디자인
//
// 변경 (DM과 통일):
// - 내 메시지: primary 그라데이션 + 그림자
// - 상대 메시지: bgCard 카드 + 미세 보더 + 그림자
// - 답장 미리보기: 컬러 바 + 미세 배경
// - 모서리: 18px (꼬리 4px)
// - 발신자 닉네임: 더 큰 폰트 + 보더
// - 시간: w500
// - 삭제된 메시지: 흐릿한 이탤릭
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

  Widget _buildText(String text, {bool deleted = false}) {
    if (deleted) {
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
      linkColor: isMe
          ? const Color(0xFFE0F2FE)
          : const Color(0xFF60A5FA),
    );
  }

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
        isGroup: true,
        initialTranscript: msg.audioTranscript,
        initialStatus: msg.audioTranscriptStatus,
      );
    }
    if (msg.isDeleted) {
      return Container(
        decoration: _bubbleDecoration(),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _buildText('', deleted: true),
      );
    }

    if (msg.allImageUrls.isNotEmpty) {
      return MultiImageGrid(
        imageUrls: msg.allImageUrls,
        isMe: isMe,
        timeStr: timeStr,
        senderName: msg.senderNickname ?? '알 수 없음',
      );
    }

    final firstUrl = extractFirstUrl(msg.content);
    final bubble = Container(
      decoration: _bubbleDecoration(),
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
        const SizedBox(height: 4),
        LinkPreviewCard(url: firstUrl, isMe: isMe),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // ─── 발신자 닉네임 ──────────
            if (!isMe && showSenderInfo)
              Padding(
                padding: const EdgeInsets.only(left: 38, bottom: 4),
                child: Text(
                  msg.senderNickname ?? '알 수 없음',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),

            // ─── 답장 미리보기 ──────────
            if (msg.replyToContent != null)
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 0 : 38,
                  right: isMe ? 4 : 0,
                  bottom: 3,
                ),
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
                            borderRadius: BorderRadius.circular(2),
                          ),
                          margin: const EdgeInsets.only(right: 8),
                        ),
                        Flexible(
                          child: Text(
                            msg.replyToContent!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSub,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ─── 메시지 본문 ──────────
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  SizedBox(
                    width: 32,
                    child: showSenderInfo
                        ? GestureDetector(
                            onTap: onAvatarTap,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withOpacity(0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: AvatarWidget(
                                url: msg.senderAvatar,
                                name: msg.senderNickname,
                                size: 30,
                              ),
                            ),
                          )
                        : null,
                  ),
                if (!isMe) const SizedBox(width: 6),
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

            // ─── 리액션 ──────────
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 38,
                right: isMe ? 4 : 0,
                top: 2,
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