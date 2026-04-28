import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _supabase = Supabase.instance.client;

  // 채팅방 음소거 여부 확인
  static Future<bool> isMuted({
    String? roomId,
    String? groupRoomId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final query = _supabase
        .from('kyorangtalk_notification_settings')
        .select('muted, muted_until')
        .eq('user_id', user.id);

    final result = roomId != null
        ? await query.eq('room_id', roomId).maybeSingle()
        : await query.eq('group_room_id', groupRoomId!).maybeSingle();

    if (result == null) return false;

    final muted = result['muted'] as bool? ?? false;
    if (!muted) return false;

    final mutedUntilStr = result['muted_until'] as String?;
    if (mutedUntilStr != null) {
      final mutedUntil = DateTime.parse(mutedUntilStr);
      if (DateTime.now().isAfter(mutedUntil)) {
        await unmute(roomId: roomId, groupRoomId: groupRoomId);
        return false;
      }
    }
    return true;
  }

  // 음소거 설정
  static Future<void> mute({
    String? roomId,
    String? groupRoomId,
    Duration? duration,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final mutedUntil = duration != null
        ? now.add(duration).toIso8601String()
        : null;

    final data = {
      'user_id':      user.id,
      'muted':        true,
      'muted_until':  mutedUntil,
      'updated_at':   now.toIso8601String(),
      if (roomId != null)      'room_id':       roomId,
      if (groupRoomId != null) 'group_room_id': groupRoomId,
    };

    await _supabase
        .from('kyorangtalk_notification_settings')
        .upsert(data,
            onConflict: roomId != null
                ? 'user_id,room_id'
                : 'user_id,group_room_id');
  }

  // 음소거 해제
  static Future<void> unmute({
    String? roomId,
    String? groupRoomId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final query = _supabase
        .from('kyorangtalk_notification_settings')
        .update({
          'muted':       false,
          'muted_until': null,
          'updated_at':  DateTime.now().toIso8601String(),
        })
        .eq('user_id', user.id);

    if (roomId != null) {
      await query.eq('room_id', roomId);
    } else if (groupRoomId != null) {
      await query.eq('group_room_id', groupRoomId);
    }
  }

  // 내가 음소거한 모든 방 ID
  static Future<Set<String>> getMutedRoomIds() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return {};

    final data = await _supabase
        .from('kyorangtalk_notification_settings')
        .select('room_id, group_room_id, muted_until')
        .eq('user_id', user.id)
        .eq('muted', true);

    final muted = <String>{};
    final now = DateTime.now();

    for (final item in data) {
      final mutedUntilStr = item['muted_until'] as String?;
      if (mutedUntilStr != null) {
        final mutedUntil = DateTime.parse(mutedUntilStr);
        if (now.isAfter(mutedUntil)) continue;
      }
      final rId = item['room_id'] as String?;
      final gId = item['group_room_id'] as String?;
      if (rId != null) muted.add(rId);
      if (gId != null) muted.add(gId);
    }
    return muted;
  }
}

// 음소거된 방 ID들
final mutedRoomsProvider =
    FutureProvider<Set<String>>((ref) async {
  return await NotificationService.getMutedRoomIds();
});