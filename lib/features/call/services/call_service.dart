// ════════════════════════════════════════════════════════════════
// 📞 KyorangTalk Call Service
//
// ⭐ 최적화:
//   - warmupTokenFunction(): 앱 시작 시 호출 — Edge Function cold start 방지
//   - prefetchToken(callId): IncomingCallScreen 표시 순간 호출 — 받기 누를 때 토큰 즉시 준비
//   - 병렬화: 권한 + 토큰 + RPC 동시 실행
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';
import 'call_notification_service.dart';

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

  RealtimeChannel? _callStatusChannel;
  bool _notificationShown = false;

  // ⭐ 토큰 prefetch 캐시
  String? _prefetchedCallId;
  Future<AgoraTokenResponse>? _prefetchedTokenFuture;

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

  // ════════════════════════════════════════════════
  // ⭐ Edge Function 웜업
  // 앱 시작 시 한 번 호출하면 함수가 hot 상태 유지
  // ════════════════════════════════════════════════
  Future<void> warmupTokenFunction() async {
    try {
      print('🔥 [CallService] Edge Function 웜업 시작');
      final sw = DateTime.now();
      // dummy callId로 invoke — 토큰 발급은 실패해도 OK (cold start만 깨움)
      await _sb.functions
          .invoke('agora-token', body: {'call_id': '__warmup__'})
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw TimeoutException('warmup timeout');
      });
      print('🔥 [CallService] 웜업 완료: ${DateTime.now().difference(sw).inMilliseconds}ms');
    } catch (e) {
      // 웜업 실패는 무시 (cold start만 trigger되면 됨)
      print('🟡 [CallService] 웜업 (오류 무시): $e');
    }
  }

  // ════════════════════════════════════════════════
  // ⭐ 토큰 prefetch
  // IncomingCallScreen이 뜨는 순간 호출 → 받기 누를 때 즉시 사용
  // ════════════════════════════════════════════════
  void prefetchToken(String callId) {
    if (_prefetchedCallId == callId && _prefetchedTokenFuture != null) {
      print('🔵 [CallService] 이미 prefetch 중: $callId');
      return;
    }
    print('🚀 [CallService] 토큰 prefetch 시작: $callId');
    _prefetchedCallId = callId;
    _prefetchedTokenFuture = _fetchToken(callId);
    _prefetchedTokenFuture!.then((_) {
      print('🚀 [CallService] 토큰 prefetch 완료');
    }).catchError((e) {
      print('🟡 [CallService] prefetch 오류: $e');
      // 실패 시 캐시 비움 → 다음에 다시 시도
      if (_prefetchedCallId == callId) {
        _prefetchedCallId = null;
        _prefetchedTokenFuture = null;
      }
    });
  }

  /// prefetch된 토큰을 사용하거나 새로 fetch
  Future<AgoraTokenResponse> _getTokenForCall(String callId) {
    if (_prefetchedCallId == callId && _prefetchedTokenFuture != null) {
      print('🚀 [CallService] prefetch된 토큰 사용');
      final future = _prefetchedTokenFuture!;
      _prefetchedCallId = null;
      _prefetchedTokenFuture = null;
      return future;
    }
    return _fetchToken(callId);
  }

  Future<bool> requestPermissions({required bool video}) async {
    if (kIsWeb) return true;

    final permissions = <Permission>[Permission.microphone];
    if (video) permissions.add(Permission.camera);

    final results = await permissions.request();
    return results.values.every((s) => s.isGranted);
  }

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

    final callId = result as String;

    // ⭐ 발신자도 callId 받자마자 prefetch (joinChannel 직전이라 효과 적지만 안전)
    prefetchToken(callId);

    return callId;
  }

  Future<void> joinChannel({
    required String callId,
    required bool isVideo,
  }) async {
    final swStart = DateTime.now();

    final permFuture = requestPermissions(video: isVideo);
    final tokenFuture = _getTokenForCall(callId);

    final results = await Future.wait([permFuture, tokenFuture]);
    final ok = results[0] as bool;
    final tokenResp = results[1] as AgoraTokenResponse;

    if (!ok) {
      throw Exception('마이크${isVideo ? '/카메라' : ''} 권한이 필요해요');
    }

    print('🔵 [CallService] 권한+토큰 완료: ${DateTime.now().difference(swStart).inMilliseconds}ms');

    await _initEngine(
      appId: tokenResp.appId,
      isVideo: isVideo,
    );

    _isVideoCall = isVideo;
    _currentCallId = callId;
    _myAgoraUid = tokenResp.agoraUid;
    _notificationShown = false;

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

    print('🟢 [CallService] joinChannel 완료: ${DateTime.now().difference(swStart).inMilliseconds}ms');

    if (isVideo) {
      _engine!.startPreview().catchError((e) {
        print('🟡 startPreview 실패 (무시): $e');
        return null;
      });
    }

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

    _maybeShowNotificationForCurrentStatus(callId, isVideo);
    _watchCallStatus(callId, isVideo);
  }

  Future<void> _maybeShowNotificationForCurrentStatus(
      String callId, bool isVideo) async {
    try {
      final row = await _sb
          .from('kyorangtalk_calls')
          .select('status')
          .eq('id', callId)
          .maybeSingle();
      final status = row?['status'] as String?;
      if (status == 'active') {
        _showCallNotification(callId, isVideo);
      }
    } catch (e) {
      print('🟡 [CallService] status 확인 오류: $e');
    }
  }

  // ════════════════════════════════════════════════
  // ⭐ acceptCall — RPC + 토큰 + 권한 + 엔진 모두 병렬
  // 토큰은 prefetch 캐시에서 즉시 사용 (가장 큰 단축)
  // ════════════════════════════════════════════════
  Future<void> acceptCall({
    required String callId,
    required bool isVideo,
  }) async {
    final swStart = DateTime.now();

    final rpcFuture = _sb
        .rpc('kyorangtalk_accept_call', params: {'p_call_id': callId})
        .catchError((e) {
          print('🔴 accept_call RPC 오류: $e');
          throw e;
        });

    final permFuture = requestPermissions(video: isVideo);
    final tokenFuture = _getTokenForCall(callId);

    final results = await Future.wait([rpcFuture, permFuture, tokenFuture]);
    final ok = results[1] as bool;
    final tokenResp = results[2] as AgoraTokenResponse;

    if (!ok) {
      throw Exception('마이크${isVideo ? '/카메라' : ''} 권한이 필요해요');
    }

    print('🔵 [CallService] accept RPC+권한+토큰 완료: ${DateTime.now().difference(swStart).inMilliseconds}ms');

    await _initEngine(
      appId: tokenResp.appId,
      isVideo: isVideo,
    );

    _isVideoCall = isVideo;
    _currentCallId = callId;
    _myAgoraUid = tokenResp.agoraUid;
    _notificationShown = false;

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

    print('🟢 [CallService] acceptCall joinChannel 완료: ${DateTime.now().difference(swStart).inMilliseconds}ms');

    if (isVideo) {
      _engine!.startPreview().catchError((e) {
        print('🟡 startPreview 실패 (무시): $e');
        return null;
      });
    }

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
    _showCallNotification(callId, isVideo);
    _watchCallStatus(callId, isVideo);
  }

  Future<void> declineCall(String callId) async {
    await _sb.rpc('kyorangtalk_decline_call', params: {'p_call_id': callId});
  }

  Future<void> cancelCall(String callId) async {
    await _sb.rpc('kyorangtalk_cancel_call', params: {'p_call_id': callId});
    await leaveChannel();
  }

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

    if (_callStatusChannel != null) {
      try {
        await _sb.removeChannel(_callStatusChannel!);
      } catch (_) {}
      _callStatusChannel = null;
    }

    CallNotificationService.instance.hide();
    _notificationShown = false;

    // prefetch 캐시 비우기
    _prefetchedCallId = null;
    _prefetchedTokenFuture = null;

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

  void _watchCallStatus(String callId, bool isVideo) {
    if (_callStatusChannel != null) {
      try {
        _sb.removeChannel(_callStatusChannel!);
      } catch (_) {}
      _callStatusChannel = null;
    }

    _callStatusChannel = _sb
        .channel('call_status_watch_$callId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'kyorangtalk_calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: callId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            final status = newRow['status'] as String?;
            print('🔵 [CallService] 통화 상태 변경: $status');

            if (status == 'active' && !_notificationShown) {
              _showCallNotification(callId, isVideo);
            }

            if (status == 'ended' ||
                status == 'declined' ||
                status == 'cancelled' ||
                status == 'missed') {
              print('🟡 [CallService] 통화 종료 감지 → 자동 정리');
              leaveChannel();
            }
          },
        )
        .subscribe();
  }

  Future<void> _showCallNotification(String callId, bool isVideo) async {
    if (_notificationShown) return;
    _notificationShown = true;
    try {
      final displayName = await _fetchCallDisplayName(callId);
      await CallNotificationService.instance.show(
        callId: callId,
        isVideo: isVideo,
        displayName: displayName,
      );
    } catch (e) {
      print('🟡 _showCallNotification 오류: $e');
      _notificationShown = false;
    }
  }

  Future<String> _fetchCallDisplayName(String callId) async {
    try {
      final call = await _sb
          .from('kyorangtalk_calls')
          .select('initiator_id, room_type, source_room_id')
          .eq('id', callId)
          .maybeSingle();

      if (call == null) return '통화 중';

      final roomType = call['room_type'] as String?;
      final myId = _sb.auth.currentUser?.id;

      if (roomType == 'group') {
        final sourceRoomId = call['source_room_id'] as String?;
        if (sourceRoomId == null) return '그룹 통화';
        final room = await _sb
            .from('kyorangtalk_group_rooms')
            .select('name')
            .eq('id', sourceRoomId)
            .maybeSingle();
        return room?['name'] as String? ?? '그룹 통화';
      }

      final initiatorId = call['initiator_id'] as String;
      final sourceRoomId = call['source_room_id'] as String?;

      String? otherId;
      if (sourceRoomId != null) {
        final room = await _sb
            .from('kyorangtalk_rooms')
            .select('user1_id, user2_id')
            .eq('id', sourceRoomId)
            .maybeSingle();

        if (room != null) {
          final u1 = room['user1_id'] as String;
          final u2 = room['user2_id'] as String;
          otherId = u1 == myId ? u2 : u1;
        }
      }
      otherId ??= initiatorId == myId ? null : initiatorId;

      if (otherId == null) return '통화 중';

      final prof = await _sb
          .from('kyorangtalk_profiles')
          .select('nickname')
          .eq('id', otherId)
          .maybeSingle();

      return prof?['nickname'] as String? ?? '통화 중';
    } catch (e) {
      print('🟡 _fetchCallDisplayName 오류: $e');
      return '통화 중';
    }
  }

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