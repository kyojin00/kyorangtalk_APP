import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import '../../features/chat/providers/chat_provider.dart' show currentOpenRoomId;
import '../../features/group_chat/providers/group_chat_provider.dart' show currentOpenGroupRoomId;
import '../../features/call/services/call_kit_service.dart';

// ⭐ 백그라운드 핸들러 — entry point 등록 필수
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ⭐ call_invite는 백그라운드에서도 시스템 통화 UI 띄워야 함
  if (message.data['type'] == 'call_invite') {
    final invite = CallInvite.fromFcmData(message.data);
    if (invite.callId.isNotEmpty) {
      await CallKitService.instance.showIncomingCall(
        callId:       invite.callId,
        callerName:   invite.callerName,
        callerAvatar: invite.callerAvatar,
        isVideo:      invite.isVideo,
        roomType:     invite.roomType,
        sourceRoomId: invite.sourceRoomId,
        initiatorId:  invite.initiatorId,
        groupName:    invite.groupName,
      );
    }
  }
}

typedef OnNotificationTap = void Function(String roomId, String senderId);
typedef OnVoiceRoomTap = void Function(String voiceRoomId, String? title);

OnNotificationTap? _onNotificationTap;
OnVoiceRoomTap? _onVoiceRoomTap;

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
          // ⭐ 보이스 룸 페이로드 처리
          if (payload.startsWith('voice_room:')) {
            final parts = payload.substring('voice_room:'.length).split('|');
            if (parts.isNotEmpty) {
              final voiceRoomId = parts[0];
              final title = parts.length > 1 ? parts[1] : null;
              _onVoiceRoomTap?.call(voiceRoomId, title);
            }
            return;
          }
          // 일반 메시지 페이로드
          final parts = payload.split('|');
          if (parts.length == 2) {
            _onNotificationTap?.call(parts[0], parts[1]);
          }
        }
      },
    );

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

  // ⭐ NEW: 보이스 룸 푸시 탭 콜백
  static void setOnVoiceRoomTap(OnVoiceRoomTap callback) {
    _onVoiceRoomTap = callback;
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
    // ⭐ 통화 초대
    if (message.data['type'] == 'call_invite') {
      await _handleCallInvite(message.data);
      return;
    }

    // ⭐ NEW: 보이스 룸 시작
    if (message.data['type'] == 'voice_room_started') {
      await _handleVoiceRoomNotification(message);
      return;
    }

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

  // ⭐ 통화 초대 FCM 처리
  static Future<void> _handleCallInvite(Map<String, dynamic> data) async {
    final invite = CallInvite.fromFcmData(data);
    if (invite.callId.isEmpty) {
      print('🔴 통화 초대: call_id 없음');
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final myId = supabase.auth.currentUser?.id;
      if (myId != null) {
        final blocked = await supabase
            .from('kyorangtalk_blocks')
            .select('id')
            .eq('blocker_id', myId)
            .eq('blocked_id', invite.initiatorId)
            .maybeSingle();
        if (blocked != null) {
          print('🚫 차단된 사용자로부터의 통화 - 무시');
          return;
        }
      }
    } catch (e) {
      print('🟡 차단 확인 실패 (무시): $e');
    }

    print('📞 통화 초대 수신: ${invite.callerName} (${invite.callId})');

    await CallKitService.instance.showIncomingCall(
      callId:       invite.callId,
      callerName:   invite.callerName,
      callerAvatar: invite.callerAvatar,
      isVideo:      invite.isVideo,
      roomType:     invite.roomType,
      sourceRoomId: invite.sourceRoomId,
      initiatorId:  invite.initiatorId,
      groupName:    invite.groupName,
    );
  }

  // ⭐ NEW: 보이스 룸 시작 푸시 처리
  static Future<void> _handleVoiceRoomNotification(
      RemoteMessage message) async {
    final voiceRoomId = message.data['voice_room_id'] ?? '';
    final groupRoomId = message.data['group_room_id'] ?? '';
    final hostName = message.data['host_name'] ?? '누군가';
    final groupName = message.data['group_name'] ?? '';
    final initiatorId = message.data['host_user_id'] ?? '';

    if (voiceRoomId.isEmpty) {
      print('🔴 보이스 룸 푸시: voice_room_id 없음');
      return;
    }

    // 전역 알림 설정 확인
    final prefs = await _loadNotificationPrefs();
    if (!prefs['notifications_enabled']!) {
      print('🔕 전역 알림 꺼짐 - 보이스 룸 푸시 차단');
      return;
    }

    // 그룹 방 음소거 확인
    if (groupRoomId.isNotEmpty) {
      final isMuted =
          await NotificationService.isMuted(groupRoomId: groupRoomId);
      if (isMuted) {
        print('🔕 그룹 음소거 - 보이스 룸 푸시 차단');
        return;
      }
    }

    // 차단된 사용자인지 확인
    try {
      final supabase = Supabase.instance.client;
      final myId = supabase.auth.currentUser?.id;
      if (myId != null && initiatorId.isNotEmpty) {
        final blocked = await supabase
            .from('kyorangtalk_blocks')
            .select('id')
            .eq('blocker_id', myId)
            .eq('blocked_id', initiatorId)
            .maybeSingle();
        if (blocked != null) {
          print('🚫 차단된 사용자의 보이스 룸 - 무시');
          return;
        }
      }
    } catch (_) {}

    print('🎙️ 보이스 룸 푸시: $hostName ($voiceRoomId)');

    // 소리/진동 설정
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

    final title = groupName.isNotEmpty
        ? '$groupName · 보이스 룸 시작'
        : '보이스 룸 시작';
    final body = '$hostName 님이 보이스 룸을 시작했어요. 탭해서 참여하세요.';

    // payload 형식: "voice_room:{voiceRoomId}|{groupName}"
    final payload = 'voice_room:$voiceRoomId|$groupName';

    _localNotifications.show(
      voiceRoomId.hashCode,
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
      payload: payload,
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    // 통화 초대는 별도 핸들러에서 처리
    if (message.data['type'] == 'call_invite') {
      return;
    }

    // ⭐ NEW: 보이스 룸 시작 푸시 탭
    if (message.data['type'] == 'voice_room_started') {
      final voiceRoomId = message.data['voice_room_id'] ?? '';
      final groupName = message.data['group_name'] ?? '';
      if (voiceRoomId.isNotEmpty) {
        _onVoiceRoomTap?.call(
          voiceRoomId,
          groupName.isNotEmpty ? groupName : null,
        );
      }
      return;
    }

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