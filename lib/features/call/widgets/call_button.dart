// ════════════════════════════════════════════════════════════════
// 📞 CallButton
//
// 채팅방 헤더에 추가할 통화 시작 버튼.
// 음성/영상 통화 둘 다 지원.
//
// 사용법:
//
//   // DM 채팅방 헤더
//   CallButton(
//     roomType: CallRoomType.dm,
//     sourceRoomId: room.roomId,
//   ),
//
//   // 그룹 채팅방 헤더
//   CallButton(
//     roomType: CallRoomType.group,
//     sourceRoomId: room.id,
//   ),
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';
import '../screens/active_call_screen.dart';

class CallButton extends ConsumerStatefulWidget {
  final CallRoomType roomType;
  final String sourceRoomId;
  final Color? color;

  const CallButton({
    super.key,
    required this.roomType,
    required this.sourceRoomId,
    this.color,
  });

  @override
  ConsumerState<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends ConsumerState<CallButton> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.textSub;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.call_outlined, color: color, size: 22),
          onPressed: _starting ? null : () => _startCall(CallType.voice),
          tooltip: '음성 통화',
        ),
        IconButton(
          icon: Icon(Icons.videocam_outlined, color: color, size: 22),
          onPressed: _starting ? null : () => _startCall(CallType.video),
          tooltip: '영상 통화',
        ),
      ],
    );
  }

  Future<void> _startCall(CallType type) async {
    if (_starting) return;
    setState(() => _starting = true);

    final service = CallService.instance;

    try {
      // 권한 먼저 체크
      final ok = await service.requestPermissions(video: type.isVideo);
      if (!ok) {
        if (!mounted) return;
        _showSnack('마이크${type.isVideo ? "/카메라" : ""} 권한이 필요해요');
        return;
      }

      // 통화 세션 생성
      final callId = await service.startCall(
        roomType: widget.roomType,
        sourceRoomId: widget.sourceRoomId,
        callType: type,
      );

      if (!mounted) return;

      // 통화 중 화면으로 이동 (Agora 채널 입장은 화면에서 처리)
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ActiveCallScreen(
            callId: callId,
            isVideo: type.isVideo,
            isInitiator: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('통화 시작 실패: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}