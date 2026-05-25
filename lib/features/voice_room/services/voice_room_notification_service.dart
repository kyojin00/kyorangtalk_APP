import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

const String _kPortName = 'voice_room_notification_port';

/// 알림 액션 ID
const String kActionLeaveVoiceRoom = 'leave_voice_room';
const String kActionTapNotification = 'tap_notification';

class VoiceRoomNotificationService {
  static bool _initialized = false;
  static bool _isRunning = false;
  static ReceivePort? _receivePort;

  static final _actionController = StreamController<String>.broadcast();
  static Stream<String> get actionStream => _actionController.stream;

  // ─────────────────────────────────────────────
  // 초기화
  // ─────────────────────────────────────────────
  static Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('🎙️ [N1] initialize 시작');

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kyorangtalk_voice_room',
        channelName: '교랑톡 보이스 룸',
        channelDescription: '진행 중인 보이스 룸 알림',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        playSound: false,
        enableVibration: false,
        showWhen: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _setupCommunicationPort();
    _initialized = true;
    debugPrint('🎙️ [N1] initialize 완료');
  }

  static Future<bool> _ensurePermissions() async {
    debugPrint('🎙️ [N2] 권한 확인 시작');

    final notiPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    debugPrint('🎙️ [N3] 알림 권한 현재 상태: $notiPermission');

    if (notiPermission != NotificationPermission.granted) {
      debugPrint('🎙️ [N4] 권한 요청 다이얼로그 표시');
      final result =
          await FlutterForegroundTask.requestNotificationPermission();
      debugPrint('🎙️ [N5] 요청 결과: $result');
      if (result != NotificationPermission.granted) {
        debugPrint('🔴 [N6] 알림 권한 거부됨');
        return false;
      }
    }

    final batOpt =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    debugPrint('🎙️ [N7] 배터리 최적화 무시 상태: $batOpt');
    if (!batOpt) {
      debugPrint('🎙️ [N8] 배터리 최적화 무시 요청');
      try {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      } catch (e) {
        debugPrint('🟡 [N9] 배터리 최적화 요청 실패: $e');
      }
    }

    debugPrint('🎙️ [N10] 권한 확인 완료 (OK)');
    return true;
  }

  static void _setupCommunicationPort() {
    _receivePort?.close();
    _receivePort = ReceivePort();

    IsolateNameServer.removePortNameMapping(_kPortName);
    IsolateNameServer.registerPortWithName(
      _receivePort!.sendPort,
      _kPortName,
    );

    _receivePort!.listen((message) {
      if (message is String) {
        debugPrint('🎙️ [N-ACTION] 액션 수신: $message');
        _actionController.add(message);
      }
    });
  }

  // ─────────────────────────────────────────────
  // 알림 시작
  // ─────────────────────────────────────────────
  static Future<void> start({
    required String groupName,
    required int participantCount,
  }) async {
    debugPrint('🎙️ [S1] start 호출 (group=$groupName, n=$participantCount)');

    if (!_initialized) {
      await initialize();
    }

    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      debugPrint('🔴 [S3] 권한 없음 → 알림 표시 안 함');
      return;
    }

    final title = groupName.isNotEmpty
        ? '$groupName · 보이스 룸'
        : '보이스 룸 진행 중';
    final body = '$participantCount명 참여 중 · 탭해서 돌아가기';

    try {
      final isAlreadyRunning =
          await FlutterForegroundTask.isRunningService;
      debugPrint('🎙️ [S5] isRunningService=$isAlreadyRunning');

      if (isAlreadyRunning) {
        final result = await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: body,
        );
        _isRunning = true;
        debugPrint('🎙️ [S7] updateService 결과: $result');
      } else {
        final result = await FlutterForegroundTask.startService(
          serviceId: 9001,
          notificationTitle: title,
          notificationText: body,
          notificationButtons: [
            const NotificationButton(
              id: kActionLeaveVoiceRoom,
              text: '나가기',
              textColor: Color(0xFFEF4444),
            ),
          ],
          callback: voiceRoomTaskCallback,
        );
        _isRunning = true;
        debugPrint('🎙️ [S9] startService 결과: $result');
        debugPrint('🎙️ [S10] 알림 시작 완료: title="$title"');
      }
    } catch (e, st) {
      debugPrint('🔴 [S-ERR] 시작 실패: $e');
      debugPrint('🔴 [S-ERR] StackTrace: $st');
    }
  }

  static Future<void> update({
    required String groupName,
    required int participantCount,
  }) async {
    if (!_isRunning) return;

    final title = groupName.isNotEmpty
        ? '$groupName · 보이스 룸'
        : '보이스 룸 진행 중';
    final body = '$participantCount명 참여 중 · 탭해서 돌아가기';

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    } catch (e) {
      debugPrint('🔴 [U-ERR] update 실패: $e');
    }
  }

  static Future<void> stop() async {
    if (!_isRunning) return;

    try {
      final result = await FlutterForegroundTask.stopService();
      _isRunning = false;
      debugPrint('🎙️ [X2] stopService 결과: $result');
    } catch (e) {
      debugPrint('🔴 [X-ERR] 종료 실패: $e');
    }
  }

  static bool get isRunning => _isRunning;
}

@pragma('vm:entry-point')
void voiceRoomTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_VoiceRoomTaskHandler());
}

class _VoiceRoomTaskHandler extends TaskHandler {
  SendPort? _sendPort;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _sendPort = IsolateNameServer.lookupPortByName(_kPortName);
    debugPrint('🎙️ [TaskHandler] onStart');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('🎙️ [TaskHandler] onDestroy');
  }

  // ⭐ 알림의 [나가기] 버튼 탭
  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('🎙️ [TaskHandler] button pressed: $id');
    _sendPort?.send(id);
  }

  // ⭐ 알림 본체 탭 — 앱 띄우고 보이스 룸 라우팅 액션 전달
  @override
  void onNotificationPressed() {
    debugPrint('🎙️ [TaskHandler] notification tapped');
    FlutterForegroundTask.launchApp();
    _sendPort?.send(kActionTapNotification);
  }

  @override
  void onNotificationDismissed() {
    debugPrint('🎙️ [TaskHandler] dismissed');
  }
}