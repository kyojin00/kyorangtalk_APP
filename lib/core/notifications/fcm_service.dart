import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import '../../features/chat/providers/chat_provider.dart' show currentOpenRoomId;
import '../../features/group_chat/providers/group_chat_provider.dart' show currentOpenGroupRoomId;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

typedef OnNotificationTap = void Function(String roomId, String senderId);
OnNotificationTap? _onNotificationTap;

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // ✨ 사운드 있는 채널
  static const _androidChannelWithSound = AndroidNotificationChannel(
    'kyorangtalk_messages',
    '교랑톡 메시지',
    description: '새 메시지 알림',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ✨ 무음 채널
  static const _androidChannelSilent = AndroidNotificationChannel(
    'kyorangtalk_messages_silent',
    '교랑톡 메시지 (무음)',
    description: '새 메시지 알림 (소리/진동 없음)',
    importance: Importance.max,
    playSound: false,
    enableVibration: false,
  );

  // ✨ 진동만 있는 채널
  static const _androidChannelVibrationOnly = AndroidNotificationChannel(
    'kyorangtalk_messages_vibration',
    '교랑톡 메시지 (진동)',
    description: '새 메시지 알림 (진동만)',
    importance: Importance.max,
    playSound: false,
    enableVibration: true,
  );

  // ✨ 소리만 있는 채널
  static const _androidChannelSoundOnly = AndroidNotificationChannel(
    'kyorangtalk_messages_sound',
    '교랑톡 메시지 (소리)',
    description: '새 메시지 알림 (소리만)',
    importance: Importance.max,
    playSound: true,
    enableVibration: false,
  );

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null) {
          final parts = payload.split('|');
          if (parts.length == 2) {
            _onNotificationTap?.call(parts[0], parts[1]);
          }
        }
      },
    );

    // ✨ 모든 채널 등록
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannelWithSound);
    await androidPlugin?.createNotificationChannel(_androidChannelSilent);
    await androidPlugin?.createNotificationChannel(_androidChannelVibrationOnly);
    await androidPlugin?.createNotificationChannel(_androidChannelSoundOnly);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  static void setOnNotificationTap(OnNotificationTap callback) {
    _onNotificationTap = callback;
  }

  // ✨ 사용자 알림 설정 조회
  static Future<Map<String, bool>> _loadNotificationPrefs() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return {
        'notifications_enabled': true,
        'sound_enabled': true,
        'vibration_enabled': true,
        'message_preview_enabled': true,
      };
    }

    try {
      final data = await Supabase.instance.client
          .from('kyorangtalk_notification_prefs')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      return {
        'notifications_enabled':
            (data?['notifications_enabled'] as bool?) ?? true,
        'sound_enabled':
            (data?['sound_enabled'] as bool?) ?? true,
        'vibration_enabled':
            (data?['vibration_enabled'] as bool?) ?? true,
        'message_preview_enabled':
            (data?['message_preview_enabled'] as bool?) ?? true,
      };
    } catch (e) {
      print('알림 설정 로드 실패: $e');
      return {
        'notifications_enabled': true,
        'sound_enabled': true,
        'vibration_enabled': true,
        'message_preview_enabled': true,
      };
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final roomId      = message.data['room_id']       ?? '';
    final groupRoomId = message.data['group_room_id'] ?? '';
    final senderId    = message.data['sender_id']     ?? '';

    // ✨ 1. 전역 알림 설정 확인
    final prefs = await _loadNotificationPrefs();

    if (!prefs['notifications_enabled']!) {
      print('🔕 전역 알림 꺼짐 - 알림 차단');
      return;
    }

    // ✨ 2. 개별 방 음소거 확인
    if (roomId.isNotEmpty) {
      final isMuted = await NotificationService.isMuted(roomId: roomId);
      if (isMuted) {
        print('🔕 방 음소거 - 알림 차단: $roomId');
        return;
      }
    } else if (groupRoomId.isNotEmpty) {
      final isMuted = await NotificationService.isMuted(groupRoomId: groupRoomId);
      if (isMuted) {
        print('🔕 그룹 음소거 - 알림 차단: $groupRoomId');
        return;
      }
    }

    // ✨ 3. 현재 열린 방이면 알림 표시 안 함
    if (roomId.isNotEmpty && currentOpenRoomId == roomId) {
      print('🔕 현재 열린 방 - 알림 차단');
      return;
    }
    if (groupRoomId.isNotEmpty && currentOpenGroupRoomId == groupRoomId) {
      print('🔕 현재 열린 그룹 - 알림 차단');
      return;
    }

    if (notification == null) return;

    // ✨ 4. 소리/진동 설정에 따라 채널 선택
    final soundOn = prefs['sound_enabled']!;
    final vibrationOn = prefs['vibration_enabled']!;

    AndroidNotificationChannel channel;
    if (soundOn && vibrationOn) {
      channel = _androidChannelWithSound;
    } else if (soundOn && !vibrationOn) {
      channel = _androidChannelSoundOnly;
    } else if (!soundOn && vibrationOn) {
      channel = _androidChannelVibrationOnly;
    } else {
      channel = _androidChannelSilent;
    }

    // ✨ 5. 메시지 미리보기 설정에 따라 body 조절
    final previewOn = prefs['message_preview_enabled']!;
    final title = previewOn ? notification.title : '새 메시지';
    final body = previewOn ? notification.body : '메시지가 도착했어요';

    _localNotifications.show(
      notification.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: soundOn,
          enableVibration: vibrationOn,
          sound: soundOn
              ? const RawResourceAndroidNotificationSound('default')
              : null,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: soundOn,
          sound: soundOn ? 'default' : null,
        ),
      ),
      payload: '${roomId.isNotEmpty ? roomId : groupRoomId}|$senderId',
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final roomId      = message.data['room_id']       ?? '';
    final groupRoomId = message.data['group_room_id'] ?? '';
    final senderId    = message.data['sender_id']     ?? '';

    final id = roomId.isNotEmpty ? roomId : groupRoomId;
    if (id.isNotEmpty && senderId.isNotEmpty) {
      _onNotificationTap?.call(id, senderId);
    }
  }

  static Future<void> saveTokenAfterLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
      _messaging.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      print('FCM saveTokenAfterLogin 오류: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('fcm_tokens').upsert(
        {
          'user_id':    user.id,
          'token':      token,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      print('FCM 토큰 저장 성공!');
    } catch (e) {
      print('FCM 토큰 저장 실패: $e');
    }
  }

  static Future<void> deleteToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client
        .from('fcm_tokens')
        .delete()
        .eq('user_id', user.id);
    await _messaging.deleteToken();
  }
}