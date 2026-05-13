// ════════════════════════════════════════════════════════════════
// 📞 IncomingCallScreen
//
// 전화 받는 풀스크린.
// CallRouter가 ringing 통화 감지 시 자동으로 띄움.
// 받기 → ActiveCallScreen으로 이동
// 거절 → 화면 닫힘
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/call_model.dart';
import '../providers/call_provider.dart';
import '../services/call_service.dart';
import 'active_call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final CallModel call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState
    extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  String? _callerNickname;
  String? _callerAvatar;
  String? _roomName;

  bool _processing = false;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _loadCallerInfo();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadCallerInfo() async {
    final sb = Supabase.instance.client;
    try {
      // 발신자 프로필
      final profile = await sb
          .from('kyorangtalk_profiles')
          .select('nickname, avatar_url')
          .eq('id', widget.call.initiatorId)
          .maybeSingle();

      // 그룹이면 방 이름도
      String? roomName;
      if (widget.call.roomType == CallRoomType.group) {
        final room = await sb
            .from('kyorangtalk_group_rooms')
            .select('name')
            .eq('id', widget.call.sourceRoomId)
            .maybeSingle();
        roomName = room?['name'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _callerNickname = profile?['nickname'] as String? ?? '알 수 없음';
        _callerAvatar = profile?['avatar_url'] as String?;
        _roomName = roomName;
      });
    } catch (e) {
      print('🔴 _loadCallerInfo 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 통화 상태 listen — 발신자가 취소하거나 통화가 끝나면 자동으로 닫음
    ref.listen<AsyncValue<CallModel?>>(
      activeCallProvider(widget.call.id),
      (prev, next) {
        next.whenData((call) {
          if (!mounted) return;
          if (call == null) {
            Navigator.of(context).pop();
            return;
          }
          if (call.status.isFinished) {
            Navigator.of(context).pop();
          }
        });
      },
    );

    final isVideo = widget.call.callType.isVideo;

    return PopScope(
      canPop: false, // 뒤로가기로 닫히지 않게 (반드시 받기/거절 중 하나)
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primary.withOpacity(0.9),
                AppTheme.bg,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // 통화 유형 표시
                Text(
                  isVideo ? '영상 통화 수신 중' : '음성 통화 수신 중',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (_roomName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _roomName!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],

                const Spacer(),

                // 아바타 + pulse
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) {
                    final scale = 1.0 + (_pulseCtrl.value * 0.08);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 160 * scale,
                          height: 160 * scale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(
                              0.15 - (_pulseCtrl.value * 0.10),
                            ),
                          ),
                        ),
                        Container(
                          width: 140 * scale,
                          height: 140 * scale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(
                              0.20 - (_pulseCtrl.value * 0.10),
                            ),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: AvatarWidget(
                    url: _callerAvatar,
                    name: _callerNickname,
                    size: 120,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  _callerNickname ?? '...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const Spacer(flex: 2),

                // 버튼들
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _CallActionButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFEF4444),
                        label: '거절',
                        onTap: _processing ? null : _decline,
                      ),
                      _CallActionButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        color: const Color(0xFF22C55E),
                        label: '받기',
                        onTap: _processing ? null : _accept,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _accept() async {
    if (_processing) return;
    setState(() => _processing = true);

    final service = CallService.instance;
    final isVideo = widget.call.callType.isVideo;

    try {
      // 권한
      final ok = await service.requestPermissions(video: isVideo);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('마이크${isVideo ? "/카메라" : ""} 권한이 필요해요'),
          ),
        );
        setState(() => _processing = false);
        return;
      }

      // 받기 화면을 ActiveCallScreen으로 교체
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ActiveCallScreen(
            callId: widget.call.id,
            isVideo: isVideo,
            isInitiator: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('통화 받기 실패: $e')),
        );
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _decline() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await CallService.instance.declineCall(widget.call.id);
    } catch (e) {
      print('🔴 decline 오류: $e');
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}