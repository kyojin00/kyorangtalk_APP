import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPrefs {
  final bool notificationsEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool messagePreviewEnabled;

  NotificationPrefs({
    required this.notificationsEnabled,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.messagePreviewEnabled,
  });

  NotificationPrefs copyWith({
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? messagePreviewEnabled,
  }) {
    return NotificationPrefs(
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled,
      soundEnabled:
          soundEnabled ?? this.soundEnabled,
      vibrationEnabled:
          vibrationEnabled ?? this.vibrationEnabled,
      messagePreviewEnabled:
          messagePreviewEnabled ?? this.messagePreviewEnabled,
    );
  }
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
        (ref) => NotificationPrefsNotifier());

class NotificationPrefsNotifier
    extends StateNotifier<NotificationPrefs> {
  NotificationPrefsNotifier()
      : super(NotificationPrefs(
          notificationsEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          messagePreviewEnabled: true,
        )) {
    load();
  }

  Future<void> load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('kyorangtalk_notification_prefs')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        state = NotificationPrefs(
          notificationsEnabled:
              data['notifications_enabled'] as bool? ?? true,
          soundEnabled:
              data['sound_enabled'] as bool? ?? true,
          vibrationEnabled:
              data['vibration_enabled'] as bool? ?? true,
          messagePreviewEnabled:
              data['message_preview_enabled'] as bool? ?? true,
        );
      }
    } catch (e) {
      print('알림 설정 로드 오류: $e');
    }
  }

  Future<void> update({
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? messagePreviewEnabled,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    state = state.copyWith(
      notificationsEnabled: notificationsEnabled,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      messagePreviewEnabled: messagePreviewEnabled,
    );

    try {
      await Supabase.instance.client
          .from('kyorangtalk_notification_prefs')
          .upsert({
        'user_id': user.id,
        'notifications_enabled': state.notificationsEnabled,
        'sound_enabled': state.soundEnabled,
        'vibration_enabled': state.vibrationEnabled,
        'message_preview_enabled': state.messagePreviewEnabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      print('알림 설정 저장 오류: $e');
    }
  }
}