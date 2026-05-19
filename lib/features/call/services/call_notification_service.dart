// ════════════════════════════════════════════════════════════════
// 📞 CallNotificationService
//
// 통화 진행 중 시스템 알림 영역에 ongoing notification 표시.
// - 사용자가 dismiss 못 함 (ongoing: true)
// - 통화 시간 자동 표시 (usesChronometer)
// - 알림 탭 → 앱 foreground + ActiveCallScreen으로 복귀
// ════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../main.dart' show navigatorKey;
import '../screens/active_call_screen.dart';

class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  static const _channelId = 'kyorang_active_call';
  static const _channelName = '진행 중인 통화';
  static const _notificationId = 9001;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 알림 탭 시 ActiveCallScreen 복귀에 사용
  String? _activeCallId;
  bool _activeIsVideo = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '진행 중인 통화 상태 표시',
        importance: Importance.high,
      ),
    );

    print('🟢 CallNotificationService initialized');
  }

  Future<void> show({
    required String callId,
    required bool isVideo,
    required String displayName,
  }) async {
    await initialize();

    _activeCallId = callId;
    _activeIsVideo = isVideo;

    try {
      await _plugin.show(
        _notificationId,
        isVideo ? '영상 통화 중' : '음성 통화 중',
        displayName,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '진행 중인 통화 상태 표시',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true,         // 사용자가 dismiss 못 함
            autoCancel: false,
            showWhen: true,
            usesChronometer: true, // 통화 시간 자동 표시
            when: DateTime.now().millisecondsSinceEpoch,
            category: AndroidNotificationCategory.call,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        payload: callId,
      );
      print('🟢 [CallNotification] 표시: $callId ($displayName)');
    } catch (e) {
      print('🟡 [CallNotification] show 오류: $e');
    }
  }

  Future<void> hide() async {
    _activeCallId = null;
    try {
      await _plugin.cancel(_notificationId);
      print('🔵 [CallNotification] 숨김');
    } catch (e) {
      print('🟡 [CallNotification] hide 오류: $e');
    }
  }

  // 알림 탭 → ActiveCallScreen 복귀
  void _onTap(NotificationResponse response) {
    final callId = _activeCallId ?? response.payload;
    if (callId == null) return;

    print('🔵 [CallNotification] 탭 → ActiveCallScreen 복귀: $callId');

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActiveCallScreen(
        callId: callId,
        isVideo: _activeIsVideo,
        isInitiator: false, // 이미 통화 중이라 _joinCall 멱등 스킵됨
      ),
    ));
  }
}