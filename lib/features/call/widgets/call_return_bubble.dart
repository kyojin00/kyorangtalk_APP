// ════════════════════════════════════════════════════════════════
// 📞 CallReturnBubble — 채팅방 안 통화 복귀 버블
//
// 해당 방에 진행 중인 통화가 있으면 메시지 버블 스타일로 표시.
// 누르면 ActiveCallScreen으로 복귀.
//
// 사용: 채팅방 화면에서 메시지 리스트와 입력창 사이에 배치
//
//   Expanded(child: messageList),
//   CallReturnBubble(roomId: roomId),  // ⭐
//   if (replyPreview) ReplyPreview(...),
//   ChatInputBar(...),
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show navigatorKey;
import '../models/call_model.dart';
import '../providers/ongoing_call_provider.dart';
import '../screens/active_call_screen.dart';

class CallReturnBubble extends ConsumerWidget {
  final String roomId;
  const CallReturnBubble({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callAsync = ref.watch(roomActiveCallProvider(roomId));
    final call = callAsync.valueOrNull;

    // 진행 중 통화가 없거나 ringing 상태(아직 통화 받기 전)면 표시 안 함
    if (call == null || call.status != CallStatus.active) {
      return const SizedBox.shrink();
    }

    final isVideo = call.callType.isVideo;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final isInitiator = call.initiatorId == myId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTap(call, isVideo, isInitiator),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withOpacity(0.82),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isVideo ? '영상 통화 진행 중' : '음성 통화 진행 중',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '눌러서 통화 화면으로 돌아가기',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(CallModel call, bool isVideo, bool isInitiator) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ActiveCallScreen(
          callId: call.id,
          isVideo: isVideo,
          isInitiator: isInitiator,
        ),
      ),
    );
  }
}