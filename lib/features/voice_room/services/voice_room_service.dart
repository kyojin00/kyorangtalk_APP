import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'voice_room_notification_service.dart';

// ═══════════════════════════════════════════════════════════════
// 🎙️ VoiceRoomService
// ═══════════════════════════════════════════════════════════════

class VoiceRoom {
  final String id;
  final String roomId;
  final String hostUserId;
  final String agoraChannel;
  final String status;
  final String? title;
  final DateTime startedAt;
  final DateTime? endedAt;

  VoiceRoom({
    required this.id,
    required this.roomId,
    required this.hostUserId,
    required this.agoraChannel,
    required this.status,
    required this.startedAt,
    this.title,
    this.endedAt,
  });

  bool get isActive => status == 'active';

  factory VoiceRoom.fromMap(Map<String, dynamic> m) => VoiceRoom(
        id: m['id'] as String,
        roomId: m['room_id'] as String,
        hostUserId: m['host_user_id'] as String,
        agoraChannel: m['agora_channel'] as String,
        status: m['status'] as String,
        title: m['title'] as String?,
        startedAt: DateTime.parse(m['started_at'] as String),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.parse(m['ended_at'] as String),
      );
}

class VoiceRoomParticipant {
  final String id;
  final String voiceRoomId;
  final String userId;
  final int agoraUid;
  final bool isMuted;
  final bool isCameraOn;
  final bool isSpeaking;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final String? nickname;
  final String? avatarUrl;

  VoiceRoomParticipant({
    required this.id,
    required this.voiceRoomId,
    required this.userId,
    required this.agoraUid,
    required this.isMuted,
    required this.isCameraOn,
    required this.isSpeaking,
    required this.joinedAt,
    this.leftAt,
    this.nickname,
    this.avatarUrl,
  });

  bool get isActive => leftAt == null;

  VoiceRoomParticipant copyWith({
    bool? isMuted,
    bool? isCameraOn,
    bool? isSpeaking,
    DateTime? leftAt,
  }) =>
      VoiceRoomParticipant(
        id: id,
        voiceRoomId: voiceRoomId,
        userId: userId,
        agoraUid: agoraUid,
        isMuted: isMuted ?? this.isMuted,
        isCameraOn: isCameraOn ?? this.isCameraOn,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        joinedAt: joinedAt,
        leftAt: leftAt ?? this.leftAt,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );

  factory VoiceRoomParticipant.fromMap(Map<String, dynamic> m) {
    final profile = m['profile'] as Map<String, dynamic>?;
    return VoiceRoomParticipant(
      id: m['id'] as String,
      voiceRoomId: m['voice_room_id'] as String,
      userId: m['user_id'] as String,
      agoraUid: (m['agora_uid'] as num).toInt(),
      isMuted: (m['is_muted'] as bool?) ?? true,
      isCameraOn: (m['is_camera_on'] as bool?) ?? false,
      isSpeaking: (m['is_speaking'] as bool?) ?? false,
      joinedAt: DateTime.parse(m['joined_at'] as String),
      leftAt: m['left_at'] == null
          ? null
          : DateTime.parse(m['left_at'] as String),
      nickname: profile?['nickname'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }
}

class _TokenResult {
  final String token;
  final String channel;
  final int uid;
  final String appId;

  _TokenResult({
    required this.token,
    required this.channel,
    required this.uid,
    required this.appId,
  });
}

// ═══════════════════════════════════════════════════════════════
// 서비스 (싱글톤)
// ═══════════════════════════════════════════════════════════════

class VoiceRoomService {
  VoiceRoomService._() {
    _listenToNotificationActions();
  }
  static final instance = VoiceRoomService._();

  RtcEngine? _engine;
  String? _currentVoiceRoomId;
  String? _currentChannel;
  int? _myAgoraUid;
  String? _currentGroupName;

  bool _engineWarmedUp = false;
  Future<void>? _warmupFuture;

  final Map<String, VoiceRoomParticipant> _participants = {};
  final Set<int> _remoteUids = {};
  final Set<int> _speakingUids = {};

  bool _localMicEnabled = false;
  bool _localCameraEnabled = false;

  RealtimeChannel? _participantsChannel;
  RealtimeChannel? _roomChannel;

  final _stateController =
      StreamController<VoiceRoomState>.broadcast();
  Stream<VoiceRoomState> get stateStream => _stateController.stream;

  // ⭐ 알림 본체 탭 이벤트 (UI 단에서 listen 해서 라우팅 처리)
  final _notificationTapController = StreamController<String>.broadcast();
  Stream<String> get notificationTapStream =>
      _notificationTapController.stream;

  StreamSubscription<String>? _notificationActionSub;

  String? get currentVoiceRoomId => _currentVoiceRoomId;
  bool get isInRoom => _currentVoiceRoomId != null;
  bool get isMicOn => _localMicEnabled;
  bool get isCameraOn => _localCameraEnabled;
  RtcEngine? get engine => _engine;

  // ─────────────────────────────────────────────
  // ⭐ 알림창 액션 수신
  // ─────────────────────────────────────────────
  void _listenToNotificationActions() {
    _notificationActionSub?.cancel();
    _notificationActionSub =
        VoiceRoomNotificationService.actionStream.listen((action) {
      debugPrint('🎙️ [Service] 알림 액션 수신: $action');

      if (action == kActionLeaveVoiceRoom) {
        // 나가기 버튼
        leaveRoom();
      } else if (action == kActionTapNotification) {
        // 알림 본체 탭 → UI 단에 라우팅하라고 알림
        final voiceRoomId = _currentVoiceRoomId;
        if (voiceRoomId != null) {
          _notificationTapController.add(voiceRoomId);
        }
      }
    });
  }

  // ═══════════════════════════════════════════════
  // warmup
  // ═══════════════════════════════════════════════

  Future<void> warmupEngine(String appId) async {
    if (_engineWarmedUp || _engine != null) return;
    _warmupFuture ??= _doWarmup(appId);
    return _warmupFuture;
  }

  Future<void> _doWarmup(String appId) async {
    try {
      debugPrint('🎙️ [warmup] 엔진 사전 초기화 시작');
      final sw = Stopwatch()..start();
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile:
            ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      await _engine!.enableAudioVolumeIndication(
        interval: 500,
        smooth: 3,
        reportVad: true,
      );
      await _engine!.enableVideo();
      await _engine!.enableLocalVideo(false);
      _registerEngineHandlers();
      _engineWarmedUp = true;
      debugPrint('🎙️ [warmup] 엔진 준비 완료 (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('🎙️ [warmup] 실패: $e');
      _engine = null;
      _engineWarmedUp = false;
    }
  }

  // ═══════════════════════════════════════════════
  // 룸 시작
  // ═══════════════════════════════════════════════

  Future<String> startRoom({
    required String groupRoomId,
    String? title,
  }) async {
    final sw = Stopwatch()..start();

    final result = await Supabase.instance.client.rpc(
      'start_voice_room',
      params: {
        'p_room_id': groupRoomId,
        'p_title': title,
      },
    );
    if (result == null) {
      throw Exception('start_voice_room returned null');
    }
    final voiceRoomId = result as String;

    debugPrint('🎙️ [startRoom] RPC 완료 (${sw.elapsedMilliseconds}ms)');
    return voiceRoomId;
  }

  Future<void> joinRoom(String voiceRoomId,
      {String? groupRoomIdForPush, String? groupName}) async {
    if (_currentVoiceRoomId == voiceRoomId) {
      debugPrint('🎙️ 이미 입장 중인 룸');
      return;
    }

    if (_currentVoiceRoomId != null) {
      await leaveRoom();
    }

    final sw = Stopwatch()..start();

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      throw Exception('마이크 권한이 필요합니다');
    }
    debugPrint('🎙️ [join] 마이크 권한 ${sw.elapsedMilliseconds}ms');

    final token = await _fetchToken(voiceRoomId);
    debugPrint('🎙️ [join] 토큰 발급 ${sw.elapsedMilliseconds}ms');

    _currentVoiceRoomId = voiceRoomId;
    _currentChannel = token.channel;
    _myAgoraUid = token.uid;
    _currentGroupName = groupName ?? '';

    await _initEngine(token.appId);
    debugPrint('🎙️ [join] 엔진 준비 ${sw.elapsedMilliseconds}ms');

    await _engine!.joinChannel(
      token: token.token,
      channelId: token.channel,
      uid: token.uid,
      options: const ChannelMediaOptions(
        channelProfile:
            ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishMicrophoneTrack: false,
        publishCameraTrack: false,
      ),
    );
    debugPrint('🎙️ [join] joinChannel 호출 ${sw.elapsedMilliseconds}ms');

    unawaited(VoiceRoomNotificationService.start(
      groupName: _currentGroupName ?? '',
      participantCount: 1,
    ));

    unawaited(_finalizeJoin(voiceRoomId, groupRoomIdForPush));

    _emit();
    debugPrint('🎙️ [join] 완료 ${sw.elapsedMilliseconds}ms');
  }

  Future<void> _finalizeJoin(
      String voiceRoomId, String? groupRoomIdForPush) async {
    unawaited(_updateMyParticipantState(
      isMuted: true,
      isCameraOn: false,
    ));

    await _loadParticipants(voiceRoomId);
    _subscribeParticipants(voiceRoomId);
    _subscribeRoom(voiceRoomId);

    unawaited(VoiceRoomNotificationService.update(
      groupName: _currentGroupName ?? '',
      participantCount: _participants.length,
    ));

    if (groupRoomIdForPush != null) {
      final userId =
          Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        unawaited(_sendVoiceRoomNotification(
          voiceRoomId: voiceRoomId,
          groupRoomId: groupRoomIdForPush,
          hostUserId: userId,
        ));
      }
    }

    _emit();
  }

  Future<void> _sendVoiceRoomNotification({
    required String voiceRoomId,
    required String groupRoomId,
    required String hostUserId,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-voice-room-notification',
        body: {
          'voice_room_id': voiceRoomId,
          'group_room_id': groupRoomId,
          'host_user_id': hostUserId,
        },
      );
    } catch (e) {
      debugPrint('🎙️ 보이스 룸 푸시 알림 발송 실패: $e');
    }
  }

  Future<void> leaveRoom() async {
    final voiceRoomId = _currentVoiceRoomId;
    if (voiceRoomId == null) return;

    unawaited(VoiceRoomNotificationService.stop());

    try {
      if (_localCameraEnabled) {
        try {
          await _engine?.stopPreview();
        } catch (_) {}
      }
      await _engine?.leaveChannel();
    } catch (e) {
      debugPrint('🎙️ leaveChannel 실패: $e');
    }

    await _unsubscribeAll();

    try {
      await Supabase.instance.client.rpc(
        'leave_voice_room',
        params: {'p_voice_room_id': voiceRoomId},
      );
    } catch (e) {
      debugPrint('🎙️ leave_voice_room RPC 실패: $e');
    }

    await _disposeEngine();

    _currentVoiceRoomId = null;
    _currentChannel = null;
    _myAgoraUid = null;
    _currentGroupName = null;
    _participants.clear();
    _remoteUids.clear();
    _speakingUids.clear();
    _localMicEnabled = false;
    _localCameraEnabled = false;
    _engineWarmedUp = false;
    _warmupFuture = null;

    _emit();
  }

  Future<void> endRoomAsHost(String voiceRoomId) async {
    await Supabase.instance.client.rpc(
      'end_voice_room',
      params: {'p_voice_room_id': voiceRoomId},
    );
    if (_currentVoiceRoomId == voiceRoomId) {
      await leaveRoom();
    }
  }

  // ═══════════════════════════════════════════════
  // 미디어 토글
  // ═══════════════════════════════════════════════

  Future<void> toggleMic() async {
    if (_engine == null) return;
    final newMicEnabled = !_localMicEnabled;

    await _engine!.muteLocalAudioStream(!newMicEnabled);
    await _engine!.updateChannelMediaOptions(
      ChannelMediaOptions(publishMicrophoneTrack: newMicEnabled),
    );

    _localMicEnabled = newMicEnabled;
    unawaited(_updateMyParticipantState(isMuted: !newMicEnabled));
    _emit();
  }

  Future<void> toggleCamera() async {
    if (_engine == null) return;
    final newCameraEnabled = !_localCameraEnabled;

    if (newCameraEnabled) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        throw Exception('카메라 권한이 필요합니다');
      }
      try {
        await _engine!.enableLocalVideo(true);
        await _engine!.startPreview();
      } catch (e) {
        debugPrint('🎙️ camera enable 실패: $e');
        rethrow;
      }
      await _engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: true),
      );
    } else {
      await _engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: false),
      );
      try {
        await _engine!.stopPreview();
      } catch (e) {
        debugPrint('🎙️ stopPreview 실패: $e');
      }
      try {
        await _engine!.enableLocalVideo(false);
      } catch (e) {
        debugPrint('🎙️ enableLocalVideo(false) 실패: $e');
      }
    }

    _localCameraEnabled = newCameraEnabled;
    unawaited(_updateMyParticipantState(isCameraOn: newCameraEnabled));
    _emit();
  }

  Future<void> switchCamera() async {
    if (_engine == null || !_localCameraEnabled) return;
    try {
      await _engine!.switchCamera();
    } catch (e) {
      debugPrint('🎙️ switchCamera 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════
  // Agora 엔진
  // ═══════════════════════════════════════════════

  Future<void> _initEngine(String appId) async {
    if (_engineWarmedUp && _engine != null) {
      debugPrint('🎙️ [init] warmup 된 엔진 재사용');
      return;
    }

    if (_warmupFuture != null) {
      debugPrint('🎙️ [init] warmup 대기');
      await _warmupFuture;
      if (_engineWarmedUp && _engine != null) return;
    }

    if (_engine != null) {
      await _disposeEngine();
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile:
          ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    await _engine!.enableAudioVolumeIndication(
      interval: 500,
      smooth: 3,
      reportVad: true,
    );

    await _engine!.enableVideo();
    await _engine!.enableLocalVideo(false);

    _registerEngineHandlers();
    _engineWarmedUp = true;
  }

  void _registerEngineHandlers() {
    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        debugPrint(
            '🎙️ [Agora] 채널 입장: ${conn.channelId}, uid=${conn.localUid}');
      },
      onUserJoined: (conn, remoteUid, elapsed) {
        debugPrint('🎙️ [Agora] 원격 입장: $remoteUid');
        _remoteUids.add(remoteUid);
        _emit();
      },
      onUserOffline: (conn, remoteUid, reason) {
        debugPrint('🎙️ [Agora] 원격 퇴장: $remoteUid ($reason)');
        _remoteUids.remove(remoteUid);
        _speakingUids.remove(remoteUid);
        _emit();
      },
      onAudioVolumeIndication: (conn, speakers, totalVolume, vad) {
        final newSpeaking = <int>{};
        for (final s in speakers) {
          if (s.volume != null && s.volume! > 30) {
            final uid =
                (s.uid == 0) ? (_myAgoraUid ?? 0) : s.uid ?? 0;
            if (uid > 0) newSpeaking.add(uid);
          }
        }
        if (!setEquals(_speakingUids, newSpeaking)) {
          _speakingUids
            ..clear()
            ..addAll(newSpeaking);
          _emit();
        }
      },
      onError: (err, msg) {
        debugPrint('🔴 [Agora] error: $err / $msg');
      },
    ));
  }

  Future<void> _disposeEngine() async {
    try {
      await _engine?.release();
    } catch (e) {
      debugPrint('🎙️ engine release 실패: $e');
    }
    _engine = null;
    _engineWarmedUp = false;
    _warmupFuture = null;
  }

  // ═══════════════════════════════════════════════
  // 참가자 로드 / Realtime
  // ═══════════════════════════════════════════════

  Future<void> _loadParticipants(String voiceRoomId) async {
    try {
      final rows = await Supabase.instance.client
          .from('kyorangtalk_voice_room_participants')
          .select(
              '*, profile:kyorangtalk_profiles!user_id(nickname, avatar_url)')
          .eq('voice_room_id', voiceRoomId)
          .eq('is_active', true);

      _participants.clear();
      for (final row in (rows as List)) {
        final p = VoiceRoomParticipant.fromMap(
            row as Map<String, dynamic>);
        _participants[p.userId] = p;
      }
    } catch (e) {
      debugPrint('🎙️ 참가자 로드 실패 (조인): $e');
      try {
        final rows = await Supabase.instance.client
            .from('kyorangtalk_voice_room_participants')
            .select()
            .eq('voice_room_id', voiceRoomId)
            .eq('is_active', true);

        _participants.clear();
        for (final row in (rows as List)) {
          final p = VoiceRoomParticipant.fromMap(
              row as Map<String, dynamic>);
          _participants[p.userId] = p;
        }
      } catch (e2) {
        debugPrint('🎙️ 참가자 로드 실패 (폴백): $e2');
      }
    }
  }

  void _subscribeParticipants(String voiceRoomId) {
    _participantsChannel?.unsubscribe();
    _participantsChannel = Supabase.instance.client
        .channel('voice_room_participants:$voiceRoomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kyorangtalk_voice_room_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'voice_room_id',
            value: voiceRoomId,
          ),
          callback: (payload) async {
            await _handleParticipantChange(payload);
          },
        )
        .subscribe();
  }

  void _subscribeRoom(String voiceRoomId) {
    _roomChannel?.unsubscribe();
    _roomChannel = Supabase.instance.client
        .channel('voice_room:$voiceRoomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'kyorangtalk_voice_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: voiceRoomId,
          ),
          callback: (payload) async {
            final newRow = payload.newRecord;
            final newStatus = newRow['status'] as String?;
            if (newStatus == 'ended') {
              debugPrint('🎙️ 룸이 종료됨, 자동 leaveRoom');
              await leaveRoom();
            }
          },
        )
        .subscribe();
  }

  Future<void> _handleParticipantChange(
      PostgresChangePayload payload) async {
    final voiceRoomId = _currentVoiceRoomId;
    if (voiceRoomId == null) return;

    final event = payload.eventType;
    final newRow = payload.newRecord;
    final oldRow = payload.oldRecord;

    if (event == PostgresChangeEvent.delete) {
      final uid = oldRow['user_id'] as String?;
      if (uid != null) _participants.remove(uid);
      _emit();
      _notifyParticipantCountChanged();
      return;
    }

    final isActive = (newRow['left_at'] == null);
    final userId = newRow['user_id'] as String;

    if (!isActive) {
      _participants.remove(userId);
      _emit();
      _notifyParticipantCountChanged();
      return;
    }

    if (!_participants.containsKey(userId)) {
      try {
        final row = await Supabase.instance.client
            .from('kyorangtalk_voice_room_participants')
            .select(
                '*, profile:kyorangtalk_profiles!user_id(nickname, avatar_url)')
            .eq('id', newRow['id'] as String)
            .maybeSingle();
        if (row != null) {
          final p = VoiceRoomParticipant.fromMap(row);
          _participants[userId] = p;
        }
      } catch (e) {
        debugPrint('🎙️ 참가자 프로필 조회 실패: $e');
        _participants[userId] =
            VoiceRoomParticipant.fromMap(newRow);
      }
      _notifyParticipantCountChanged();
    } else {
      final existing = _participants[userId]!;
      _participants[userId] = existing.copyWith(
        isMuted: (newRow['is_muted'] as bool?) ?? existing.isMuted,
        isCameraOn:
            (newRow['is_camera_on'] as bool?) ?? existing.isCameraOn,
        isSpeaking:
            (newRow['is_speaking'] as bool?) ?? existing.isSpeaking,
      );
    }
    _emit();
  }

  void _notifyParticipantCountChanged() {
    unawaited(VoiceRoomNotificationService.update(
      groupName: _currentGroupName ?? '',
      participantCount: _participants.length,
    ));
  }

  Future<void> _unsubscribeAll() async {
    try {
      await _participantsChannel?.unsubscribe();
      await _roomChannel?.unsubscribe();
    } catch (_) {}
    _participantsChannel = null;
    _roomChannel = null;
  }

  // ═══════════════════════════════════════════════
  // 내부 헬퍼
  // ═══════════════════════════════════════════════

  Future<_TokenResult> _fetchToken(String voiceRoomId) async {
    final res = await Supabase.instance.client.functions.invoke(
      'agora_token_voice_room',
      body: {'voice_room_id': voiceRoomId},
    );

    final data = res.data;
    if (data == null) {
      throw Exception('Edge Function returned null');
    }
    if (data is Map && data['error'] != null) {
      throw Exception('토큰 발급 실패: ${data['error']}');
    }
    final m = data as Map<String, dynamic>;
    return _TokenResult(
      token: m['token'] as String,
      channel: m['channel'] as String,
      uid: (m['agora_uid'] as num).toInt(),
      appId: m['app_id'] as String,
    );
  }

  Future<void> _updateMyParticipantState({
    bool? isMuted,
    bool? isCameraOn,
  }) async {
    final voiceRoomId = _currentVoiceRoomId;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (voiceRoomId == null || userId == null) return;

    final updates = <String, dynamic>{};
    if (isMuted != null) updates['is_muted'] = isMuted;
    if (isCameraOn != null) updates['is_camera_on'] = isCameraOn;
    if (updates.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('kyorangtalk_voice_room_participants')
          .update(updates)
          .eq('voice_room_id', voiceRoomId)
          .eq('user_id', userId)
          .eq('is_active', true);
    } catch (e) {
      debugPrint('🎙️ 참가자 상태 업데이트 실패: $e');
    }
  }

  void _emit() {
    _stateController.add(VoiceRoomState(
      voiceRoomId: _currentVoiceRoomId,
      channel: _currentChannel,
      myAgoraUid: _myAgoraUid,
      participants: List.unmodifiable(_participants.values),
      remoteUids: Set.unmodifiable(_remoteUids),
      speakingUids: Set.unmodifiable(_speakingUids),
      micEnabled: _localMicEnabled,
      cameraEnabled: _localCameraEnabled,
    ));
  }
}

class VoiceRoomState {
  final String? voiceRoomId;
  final String? channel;
  final int? myAgoraUid;
  final List<VoiceRoomParticipant> participants;
  final Set<int> remoteUids;
  final Set<int> speakingUids;
  final bool micEnabled;
  final bool cameraEnabled;

  VoiceRoomState({
    required this.voiceRoomId,
    required this.channel,
    required this.myAgoraUid,
    required this.participants,
    required this.remoteUids,
    required this.speakingUids,
    required this.micEnabled,
    required this.cameraEnabled,
  });

  bool get isInRoom => voiceRoomId != null;
}

final voiceRoomStateProvider =
    StreamProvider<VoiceRoomState>((ref) {
  return VoiceRoomService.instance.stateStream;
});

final activeVoiceRoomForGroupProvider =
    FutureProvider.family<VoiceRoom?, String>((ref, groupRoomId) async {
  final row = await Supabase.instance.client
      .from('kyorangtalk_voice_rooms')
      .select()
      .eq('room_id', groupRoomId)
      .eq('status', 'active')
      .maybeSingle();

  if (row == null) return null;
  return VoiceRoom.fromMap(row);
});