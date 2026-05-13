// ════════════════════════════════════════════════════════════════
// 📞 KyorangTalk Call Service
//
// Agora RTC Engine 래퍼.
// Agora SDK 6.x 기준 (agora_rtc_engine: ^6.5.0)
//
// ⭐ 웹 지원 추가:
//   - kIsWeb일 때 permission_handler 우회 (브라우저가 알아서 권한 요청)
//   - web/index.html에 AgoraRTC SDK 스크립트 필수
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final _sb = Supabase.instance.client;

  RtcEngine? _engine;
  String? _currentCallId;
  int? _myAgoraUid;
  bool _isVideoCall = false;

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = false;
  bool _frontCamera = true;

  RtcEngine? get engine => _engine;

  bool get micMuted   => _micMuted;
  bool get cameraOff  => _cameraOff;
  bool get speakerOn  => _speakerOn;
  bool get isInCall   => _engine != null && _currentCallId != null;
  String? get currentCallId => _currentCallId;
  int? get myAgoraUid => _myAgoraUid;
  bool get isVideoCall => _isVideoCall;

  final _remoteUserController = StreamController<RemoteUserEvent>.broadcast();
  Stream<RemoteUserEvent> get remoteUserStream =>
      _remoteUserController.stream;

  final _connectionController =
      StreamController<ConnectionStateType>.broadcast();
  Stream<ConnectionStateType> get connectionStream =>
      _connectionController.stream;

  final _durationController = StreamController<int>.broadcast();
  Stream<int> get durationStream => _durationController.stream;
  Timer? _durationTimer;
  DateTime? _callStartTime;

  // ═══════════════════════════════════════════════════
  // 권한
  // ═══════════════════════════════════════════════════
  //
  // ⭐ 웹에서는 permission_handler가 일부 권한을 항상 denied 반환.
  //    Agora SDK가 브라우저 권한 다이얼로그를 알아서 띄우므로
  //    웹에서는 권한 체크를 스킵하고 true 반환.
  Future<bool> requestPermissions({required bool video}) async {
    if (kIsWeb) {
      // 웹: 브라우저가 알아서 처리. 항상 통과.
      return true;
    }

    final permissions = <Permission>[Permission.microphone];
    if (video) permissions.add(Permission.camera);

    final results = await permissions.request();
    return results.values.every((s) => s.isGranted);
  }

  // ═══════════════════════════════════════════════════
  // 통화 시작
  // ═══════════════════════════════════════════════════

  Future<String> startCall({
    required CallRoomType roomType,
    required String sourceRoomId,
    required CallType callType,
  }) async {
    final result = await _sb.rpc(
      'kyorangtalk_start_call',
      params: {
        'p_room_type':      roomType.toJson(),
        'p_source_room_id': sourceRoomId,
        'p_call_type':      callType.toJson(),
      },
    );

    if (result == null) {
      throw Exception('통화 시작 실패: RPC 응답 없음');
    }
    return result as String;
  }

  // ═══════════════════════════════════════════════════
  // 채널 입장
  // ═══════════════════════════════════════════════════

  Future<void> joinChannel({
    required String callId,
    required bool isVideo,
  }) async {
    final ok = await requestPermissions(video: isVideo);
    if (!ok) {
      throw Exception('마이크${isVideo ? '/카메라' : ''} 권한이 필요해요');
    }

    final tokenResp = await _fetchToken(callId);

    await _initEngine(
      appId: tokenResp.appId,
      isVideo: isVideo,
    );

    _isVideoCall = isVideo;
    _currentCallId = callId;
    _myAgoraUid = tokenResp.agoraUid;

    await _engine!.joinChannel(
      token: tokenResp.token,
      channelId: tokenResp.channel,
      uid: tokenResp.agoraUid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        publishCameraTrack: isVideo,
        autoSubscribeAudio: true,
        autoSubscribeVideo: isVideo,
      ),
    );

    if (isVideo) {
      try {
        await _engine!.startPreview();
      } catch (e) {
        print('🟡 startPreview 실패 (무시): $e');
      }
    }

    // 채널 입장 직후 setEnableSpeakerphone이 -3 반환할 수 있음
    // 웹에서는 의미 없으므로 모바일만 시도
    if (!kIsWeb) {
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          await setSpeaker(isVideo);
        } catch (e) {
          print('🟡 setSpeaker 실패 (무시): $e');
        }
      });
    }

    _startDurationTimer();
  }

  // ═══════════════════════════════════════════════════
  // 통화 받기
  // ═══════════════════════════════════════════════════

  Future<void> acceptCall({
    required String callId,
    required bool isVideo,
  }) async {
    await _sb.rpc('kyorangtalk_accept_call', params: {'p_call_id': callId});
    await joinChannel(callId: callId, isVideo: isVideo);
  }

  // ═══════════════════════════════════════════════════
  // 통화 거절
  // ═══════════════════════════════════════════════════

  Future<void> declineCall(String callId) async {
    await _sb.rpc('kyorangtalk_decline_call', params: {'p_call_id': callId});
  }

  // ═══════════════════════════════════════════════════
  // 통화 취소
  // ═══════════════════════════════════════════════════

  Future<void> cancelCall(String callId) async {
    await _sb.rpc('kyorangtalk_cancel_call', params: {'p_call_id': callId});
    await leaveChannel();
  }

  // ═══════════════════════════════════════════════════
  // 통화 종료
  // ═══════════════════════════════════════════════════

  Future<void> endCall() async {
    final callId = _currentCallId;
    await leaveChannel();
    if (callId != null) {
      try {
        await _sb.rpc('kyorangtalk_end_call', params: {'p_call_id': callId});
      } catch (e) {
        print('🔴 end_call RPC 실패: $e');
      }
    }
  }

  Future<void> leaveChannel() async {
    _stopDurationTimer();
    try {
      if (_engine != null) {
        await _engine!.leaveChannel();
        await _engine!.release();
      }
    } catch (e) {
      print('🔴 leaveChannel 오류: $e');
    } finally {
      _engine = null;
      _currentCallId = null;
      _myAgoraUid = null;
      _isVideoCall = false;
      _micMuted = false;
      _cameraOff = false;
      _speakerOn = false;
      _frontCamera = true;
    }
  }

  // ═══════════════════════════════════════════════════
  // 통화 중 컨트롤
  // ═══════════════════════════════════════════════════

  Future<void> toggleMic() async {
    if (_engine == null) return;
    try {
      _micMuted = !_micMuted;
      await _engine!.muteLocalAudioStream(_micMuted);
    } catch (e) {
      print('🟡 toggleMic 실패: $e');
    }
  }

  Future<void> toggleCamera() async {
    if (_engine == null || !_isVideoCall) return;
    try {
      _cameraOff = !_cameraOff;
      await _engine!.muteLocalVideoStream(_cameraOff);
      await _engine!.enableLocalVideo(!_cameraOff);
    } catch (e) {
      print('🟡 toggleCamera 실패: $e');
    }
  }

  Future<void> switchCamera() async {
    if (_engine == null || !_isVideoCall) return;
    try {
      _frontCamera = !_frontCamera;
      await _engine!.switchCamera();
    } catch (e) {
      print('🟡 switchCamera 실패: $e');
    }
  }

  Future<void> setSpeaker(bool on) async {
    if (_engine == null) return;
    // 웹에서는 스피커폰 토글이 의미 없음
    if (kIsWeb) {
      _speakerOn = on;
      return;
    }
    _speakerOn = on;
    await _engine!.setEnableSpeakerphone(on);
  }

  Future<void> toggleSpeaker() async {
    try {
      await setSpeaker(!_speakerOn);
    } catch (e) {
      print('🟡 toggleSpeaker 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 그룹 통화 — 도중 참여
  // ═══════════════════════════════════════════════════

  Future<bool> joinActiveGroupCall({
    required String callId,
    required bool isVideo,
  }) async {
    final ok = await _sb.rpc(
      'kyorangtalk_join_active_call',
      params: {'p_call_id': callId},
    );
    if (ok != true) return false;
    await joinChannel(callId: callId, isVideo: isVideo);
    return true;
  }

  // ═══════════════════════════════════════════════════
  // 내부: Agora 엔진 초기화
  // ═══════════════════════════════════════════════════

  Future<void> _initEngine({
    required String appId,
    required bool isVideo,
  }) async {
    if (_engine != null) {
      await leaveChannel();
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('🟢 [Agora] 채널 입장: ${connection.channelId} uid=${connection.localUid}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('🟢 [Agora] 원격 입장: $remoteUid');
        _remoteUserController.add(RemoteUserEvent(
          agoraUid: remoteUid,
          type: RemoteUserEventType.joined,
        ));
        _callStartTime ??= DateTime.now();
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('🟡 [Agora] 원격 퇴장: $remoteUid reason=$reason');
        _remoteUserController.add(RemoteUserEvent(
          agoraUid: remoteUid,
          type: RemoteUserEventType.left,
        ));
      },
      onUserMuteAudio: (connection, remoteUid, muted) {
        _remoteUserController.add(RemoteUserEvent(
          agoraUid: remoteUid,
          type: RemoteUserEventType.audioMuted,
          muted: muted,
        ));
      },
      onUserMuteVideo: (connection, remoteUid, muted) {
        _remoteUserController.add(RemoteUserEvent(
          agoraUid: remoteUid,
          type: RemoteUserEventType.videoMuted,
          muted: muted,
        ));
      },
      onUserEnableVideo: (connection, remoteUid, enabled) {
        _remoteUserController.add(RemoteUserEvent(
          agoraUid: remoteUid,
          type: RemoteUserEventType.videoEnabled,
          videoEnabled: enabled,
        ));
      },
      onConnectionStateChanged: (connection, state, reason) {
        print('🔵 [Agora] 연결 상태: $state ($reason)');
        _connectionController.add(state);
      },
      onError: (err, msg) {
        print('🔴 [Agora] 오류: $err $msg');
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        print('🟡 [Agora] 토큰 만료 임박, 재발급 시도');
        if (_currentCallId != null) {
          try {
            final newToken = await _fetchToken(_currentCallId!);
            await _engine?.renewToken(newToken.token);
            print('🟢 [Agora] 토큰 재발급 성공');
          } catch (e) {
            print('🔴 [Agora] 토큰 재발급 실패: $e');
          }
        }
      },
    ));

    if (isVideo) {
      await _engine!.enableVideo();
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 400,
        ),
      );
    } else {
      await _engine!.disableVideo();
    }

    await _engine!.enableAudio();
  }

  // ═══════════════════════════════════════════════════
  // 내부: 토큰 발급
  // ═══════════════════════════════════════════════════

  Future<AgoraTokenResponse> _fetchToken(String callId) async {
    final response = await _sb.functions.invoke(
      'agora-token',
      body: {'call_id': callId},
    );

    if (response.status != 200 || response.data == null) {
      throw Exception(
          '토큰 발급 실패: status=${response.status}, data=${response.data}');
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return AgoraTokenResponse.fromJson(data);
    } else if (data is Map) {
      return AgoraTokenResponse.fromJson(
          Map<String, dynamic>.from(data));
    } else {
      throw Exception('토큰 응답 형식 오류: $data');
    }
  }

  // ═══════════════════════════════════════════════════
  // 내부: 통화 시간 타이머
  // ═══════════════════════════════════════════════════

  void _startDurationTimer() {
    _stopDurationTimer();
    _callStartTime = null;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStartTime == null) {
        _durationController.add(0);
        return;
      }
      final elapsed = DateTime.now().difference(_callStartTime!).inSeconds;
      _durationController.add(elapsed);
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _callStartTime = null;
  }

  Future<void> dispose() async {
    await leaveChannel();
    await _remoteUserController.close();
    await _connectionController.close();
    await _durationController.close();
  }
}