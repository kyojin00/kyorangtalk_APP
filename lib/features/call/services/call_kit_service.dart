// ════════════════════════════════════════════════════════════════
// 📞 CallKitService
//
// 시스템 통화 UI를 띄우는 서비스. flutter_callkit_incoming 래퍼.
// 잠금화면 / 백그라운드 / 앱 종료 상태에서도 동작.
//
// ⭐ 수정 (native decline 의도치 않은 fire 차단 + 살아있음 체크):
//   - setIncomingScreenActive(bool) 메서드
//   - incomingScreenActive getter (CallRouter가 재push 판단용으로 사용)
//   - IncomingCallScreen이 마운트되어 있는 동안 actionCallDecline 이벤트 무시
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  Function(CallInvite invite)? onAccept;
  Function(String callId)? onDecline;
  Function(String callId)? onTimeout;

  StreamSubscription? _eventSub;
  bool _initialized = false;

  final Set<String> _activeCallIds = {};

  bool _incomingScreenActive = false;

  void setIncomingScreenActive(bool active) {
    _incomingScreenActive = active;
    print('🔵 [CallKitService] incomingScreenActive = $active');
  }

  /// CallRouter가 IncomingCallScreen이 살아있는지 확인할 때 사용
  bool get incomingScreenActive => _incomingScreenActive;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _eventSub = FlutterCallkitIncoming.onEvent.listen(_handleEvent);
    print('🟢 CallKitService initialized');
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _initialized = false;
  }

  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String? callerAvatar,
    required bool isVideo,
    required String roomType,
    required String sourceRoomId,
    required String initiatorId,
    String? groupName,
  }) async {
    if (_activeCallIds.contains(callId)) {
      print('🟡 통화 이미 표시 중: $callId');
      return;
    }
    _activeCallIds.add(callId);

    final params = CallKitParams(
      id: callId,
      nameCaller: roomType == 'group' ? (groupName ?? '그룹') : callerName,
      appName: '교랑톡',
      avatar: callerAvatar?.isNotEmpty == true ? callerAvatar : null,
      handle: roomType == 'group' ? (groupName ?? '그룹') : callerName,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: '받기',
      textDecline: '거절',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: '부재 중 통화',
      ),
      extra: {
        'call_id': callId,
        'caller_name': callerName,
        'caller_avatar': callerAvatar ?? '',
        'is_video': isVideo,
        'room_type': roomType,
        'source_room_id': sourceRoomId,
        'initiator_id': initiatorId,
        'group_name': groupName ?? '',
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#7C3AED',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: '수신 통화',
        missedCallNotificationChannelName: '부재 중 통화',
        isImportant: true,
        isBot: false,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      print('🟢 시스템 통화 UI 표시: $callId');
    } catch (e) {
      print('🔴 showCallkitIncoming 실패: $e');
      _activeCallIds.remove(callId);
    }
  }

  Future<void> endCall(String callId) async {
    _activeCallIds.remove(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      print('🟡 endCall 오류 (무시): $e');
    }
  }

  Future<void> endAllCalls() async {
    _activeCallIds.clear();
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      print('🟡 endAllCalls 오류 (무시): $e');
    }
  }

  Future<CallInvite?> getActiveCall() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        final first = calls.first;
        if (first is Map) {
          final extra = first['extra'];
          if (extra is Map) {
            return CallInvite.fromExtra(extra);
          }
        }
      }
    } catch (e) {
      print('🟡 getActiveCall 오류: $e');
    }
    return null;
  }

  void _handleEvent(CallEvent? event) async {
    if (event == null) return;
    print('📞 [CallKit Event] ${event.event} '
        '(incomingScreenActive=$_incomingScreenActive)');

    final body = event.body;
    final extra = (body is Map && body['extra'] is Map)
        ? body['extra'] as Map<dynamic, dynamic>
        : <dynamic, dynamic>{};
    final callId = (extra['call_id'] as String?) ??
        (body is Map ? body['id'] as String? : null) ??
        '';

    if (callId.isEmpty) return;

    switch (event.event) {
      case Event.actionCallAccept:
        _activeCallIds.remove(callId);
        final invite = CallInvite.fromExtra(extra);
        onAccept?.call(invite);
        break;

      case Event.actionCallDecline:
        _activeCallIds.remove(callId);
        if (_incomingScreenActive) {
          print('🟡 [actionCallDecline] suppressed — IncomingCallScreen active');
          return;
        }
        onDecline?.call(callId);
        break;

      case Event.actionCallEnded:
      case Event.actionCallTimeout:
        _activeCallIds.remove(callId);
        onTimeout?.call(callId);
        break;

      case Event.actionCallCallback:
        break;

      default:
        break;
    }
  }
}

class CallInvite {
  final String callId;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;
  final String roomType;
  final String sourceRoomId;
  final String initiatorId;
  final String? groupName;

  CallInvite({
    required this.callId,
    required this.callerName,
    this.callerAvatar,
    required this.isVideo,
    required this.roomType,
    required this.sourceRoomId,
    required this.initiatorId,
    this.groupName,
  });

  factory CallInvite.fromExtra(Map<dynamic, dynamic> extra) {
    return CallInvite(
      callId:       extra['call_id'] as String? ?? '',
      callerName:   extra['caller_name'] as String? ?? '',
      callerAvatar: extra['caller_avatar'] as String?,
      isVideo:      extra['is_video'] == true || extra['is_video'] == 'true',
      roomType:     extra['room_type'] as String? ?? 'dm',
      sourceRoomId: extra['source_room_id'] as String? ?? '',
      initiatorId:  extra['initiator_id'] as String? ?? '',
      groupName:    extra['group_name'] as String?,
    );
  }

  factory CallInvite.fromFcmData(Map<String, dynamic> data) {
    return CallInvite(
      callId:       data['call_id'] as String? ?? '',
      callerName:   data['initiator_name'] as String? ?? '',
      callerAvatar: data['initiator_avatar'] as String?,
      isVideo:      data['call_type'] == 'video',
      roomType:     data['room_type'] as String? ?? 'dm',
      sourceRoomId: data['source_room_id'] as String? ?? '',
      initiatorId:  data['initiator_id'] as String? ?? '',
      groupName:    data['group_name'] as String?,
    );
  }
}

Future<void> declineCallRpc(String callId) async {
  try {
    await Supabase.instance.client.rpc(
      'kyorangtalk_decline_call',
      params: {'p_call_id': callId},
    );
    print('🟢 declineCall RPC 성공: $callId');
  } catch (e) {
    print('🔴 declineCall RPC 실패: $e');
  }
}