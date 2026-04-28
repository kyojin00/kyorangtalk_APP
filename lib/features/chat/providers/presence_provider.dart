// features/chat/providers/presence_provider.dart
// 웹의 Supabase Presence와 동일 채널 → PC/앱 간 읽음 실시간 동기화

class PresenceService {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  Future<void> joinRoom(String roomId) async {
    final userId = _supabase.auth.currentUser!.id;
    
    _channel = _supabase.channel('presence:$roomId')
      ..onPresenceSync(callback: (_) {})
      ..subscribe(
        (status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({'user_id': userId, 'online_at': DateTime.now().toIso8601String()});
            // 입장 시 읽음 처리
            await _markAsRead(roomId, userId);
          }
        },
      );
  }

  Future<void> _markAsRead(String roomId, String userId) async {
    await _supabase.from('room_members')
      .update({'last_read_at': DateTime.now().toIso8601String()})
      .eq('room_id', roomId)
      .eq('user_id', userId);
  }

  Future<void> leaveRoom() async {
    if (_channel != null) {
      await _supabase.removeChannel(_channel!);
    }
  }
}