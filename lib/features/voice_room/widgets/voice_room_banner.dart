import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../services/voice_room_service.dart';
import '../screens/voice_room_screen.dart';

// ═══════════════════════════════════════════════════════════════
// 🎙️ VoiceRoomBanner (v2)
//
// 위치: lib/features/voice_room/widgets/voice_room_banner.dart
//
// 그룹 채팅방 상단에 자동 표시되는 진행 중 룸 배너.
//
// 변경:
// - StreamProvider 대신 StatefulWidget 으로 변경 (더 안정적)
// - 화면 진입 시 즉시 초기 fetch
// - Realtime 구독 + 15초 폴링 폴백 동시
// - Realtime 못 받아도 폴백으로 표시 보장
// ═══════════════════════════════════════════════════════════════

class VoiceRoomBanner extends ConsumerStatefulWidget {
  final String groupRoomId;

  const VoiceRoomBanner({super.key, required this.groupRoomId});

  @override
  ConsumerState<VoiceRoomBanner> createState() =>
      _VoiceRoomBannerState();
}

class _VoiceRoomBannerState extends ConsumerState<VoiceRoomBanner> {
  VoiceRoom? _activeRoom;
  List<_ParticipantPreview> _previews = const [];
  RealtimeChannel? _roomChannel;
  RealtimeChannel? _participantsChannel;
  Timer? _pollTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _subscribeRoomChanges();
    // 폴백: 15초마다 한 번씩 강제 새로고침
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_disposed) _refreshAll();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _roomChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    try {
      final roomRow = await Supabase.instance.client
          .from('kyorangtalk_voice_rooms')
          .select()
          .eq('room_id', widget.groupRoomId)
          .eq('status', 'active')
          .maybeSingle();

      final room =
          roomRow == null ? null : VoiceRoom.fromMap(roomRow);

      if (_disposed) return;

      // 룸이 바뀌면 참가자 채널도 재구독
      if (room?.id != _activeRoom?.id) {
        _participantsChannel?.unsubscribe();
        _participantsChannel = null;
        if (room != null) {
          _subscribeParticipants(room.id);
        }
      }

      List<_ParticipantPreview> previews = const [];
      if (room != null) {
        try {
          final rows = await Supabase.instance.client
              .from('kyorangtalk_voice_room_participants')
              .select(
                  'user_id, profile:kyorangtalk_profiles!user_id(nickname, avatar_url)')
              .eq('voice_room_id', room.id)
              .eq('is_active', true)
              .limit(5);

          previews = (rows as List).map((r) {
            final m = r as Map<String, dynamic>;
            final profile = m['profile'] as Map<String, dynamic>?;
            return _ParticipantPreview(
              userId: m['user_id'] as String,
              nickname: profile?['nickname'] as String? ?? '',
              avatarUrl: profile?['avatar_url'] as String?,
            );
          }).toList();
        } catch (e) {
          try {
            final rows = await Supabase.instance.client
                .from('kyorangtalk_voice_room_participants')
                .select('user_id')
                .eq('voice_room_id', room.id)
                .eq('is_active', true)
                .limit(5);
            previews = (rows as List)
                .map((r) => _ParticipantPreview(
                      userId: (r as Map)['user_id'] as String,
                      nickname: '',
                      avatarUrl: null,
                    ))
                .toList();
          } catch (_) {}
        }
      }

      if (_disposed) return;
      setState(() {
        _activeRoom = room;
        _previews = previews;
      });
    } catch (e) {
      debugPrint('🎙️ VoiceRoomBanner refresh 실패: $e');
    }
  }

  void _subscribeRoomChanges() {
    _roomChannel = Supabase.instance.client
        .channel(
            'banner_voice_rooms:${widget.groupRoomId}:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kyorangtalk_voice_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.groupRoomId,
          ),
          callback: (_) => _refreshAll(),
        )
        .subscribe();
  }

  void _subscribeParticipants(String voiceRoomId) {
    _participantsChannel = Supabase.instance.client
        .channel(
            'banner_participants:$voiceRoomId:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kyorangtalk_voice_room_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'voice_room_id',
            value: voiceRoomId,
          ),
          callback: (_) => _refreshAll(),
        )
        .subscribe();
  }

  Future<void> _joinRoom() async {
    final room = _activeRoom;
    if (room == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceRoomScreen(
          voiceRoomId: room.id,
          title: room.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _activeRoom;
    if (room == null) return const SizedBox.shrink();

    final count = _previews.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _joinRoom,
        child: Container(
          margin:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary,
                AppTheme.primary.withOpacity(0.75),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const _PulsingMicIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '보이스 룸 진행 중',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count > 0
                          ? '$count명 참여 중 · 탭해서 참여'
                          : '탭해서 참여',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (_previews.isNotEmpty)
                _AvatarStack(previews: _previews),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '참여',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantPreview {
  final String userId;
  final String nickname;
  final String? avatarUrl;

  _ParticipantPreview({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
  });
}

// ───────────────────────────────────────────────
// 펄스 마이크 아이콘
// ───────────────────────────────────────────────
class _PulsingMicIcon extends StatefulWidget {
  const _PulsingMicIcon();

  @override
  State<_PulsingMicIcon> createState() => _PulsingMicIconState();
}

class _PulsingMicIconState extends State<_PulsingMicIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final scale = 1.0 + (_ctrl.value * 0.15);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────────────────────────
// 아바타 스택
// ───────────────────────────────────────────────
class _AvatarStack extends StatelessWidget {
  final List<_ParticipantPreview> previews;

  const _AvatarStack({required this.previews});

  @override
  Widget build(BuildContext context) {
    final shown = previews.take(3).toList();
    final extra = previews.length - shown.length;

    final stackWidth = (shown.length * 18.0) + 10 + (extra > 0 ? 22 : 0);

    return SizedBox(
      width: stackWidth,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 18.0,
              child: _MiniAvatar(preview: shown[i]),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 18.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final _ParticipantPreview preview;

  const _MiniAvatar({required this.preview});

  @override
  Widget build(BuildContext context) {
    final initial = preview.nickname.isNotEmpty
        ? preview.nickname.substring(0, 1)
        : '?';
    final hasImage =
        preview.avatarUrl != null && preview.avatarUrl!.isNotEmpty;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(preview.avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}