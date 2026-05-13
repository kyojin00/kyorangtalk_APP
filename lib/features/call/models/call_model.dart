// ════════════════════════════════════════════════════════════════
// 📞 KyorangTalk Call Models
// ════════════════════════════════════════════════════════════════

// ─── enum ────────────────────────────────────────────────────────

/// 통화 유형
enum CallType {
  voice,
  video;

  String get label => this == voice ? '음성 통화' : '영상 통화';
  bool get isVideo => this == video;

  static CallType fromString(String s) {
    return s == 'video' ? CallType.video : CallType.voice;
  }

  String toJson() => name;
}

/// 채팅방 유형
enum CallRoomType {
  dm,
  group;

  static CallRoomType fromString(String s) {
    return s == 'group' ? CallRoomType.group : CallRoomType.dm;
  }

  String toJson() => name;
}

/// 통화 상태
enum CallStatus {
  ringing,
  active,
  ended,
  declined,
  missed,
  cancelled;

  bool get isActive => this == active;
  bool get isRinging => this == ringing;
  bool get isFinished =>
      this == ended ||
      this == declined ||
      this == missed ||
      this == cancelled;

  String get label {
    switch (this) {
      case CallStatus.ringing:   return '호출 중';
      case CallStatus.active:    return '통화 중';
      case CallStatus.ended:     return '통화 종료';
      case CallStatus.declined:  return '거절됨';
      case CallStatus.missed:    return '부재중';
      case CallStatus.cancelled: return '취소됨';
    }
  }

  static CallStatus fromString(String s) {
    return CallStatus.values.firstWhere(
      (v) => v.name == s,
      orElse: () => CallStatus.ringing,
    );
  }

  String toJson() => name;
}

/// 참가자 상태
enum CallParticipantStatus {
  invited,
  accepted,
  left,
  declined,
  missed;

  bool get isInCall => this == accepted;

  static CallParticipantStatus fromString(String s) {
    return CallParticipantStatus.values.firstWhere(
      (v) => v.name == s,
      orElse: () => CallParticipantStatus.invited,
    );
  }

  String toJson() => name;
}

// ─── CallModel ───────────────────────────────────────────────────

class CallModel {
  final String id;            // == Agora 채널 이름
  final CallType callType;
  final CallRoomType roomType;
  final String sourceRoomId;
  final String initiatorId;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endReason;
  final int durationSec;

  const CallModel({
    required this.id,
    required this.callType,
    required this.roomType,
    required this.sourceRoomId,
    required this.initiatorId,
    required this.status,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.endReason,
    this.durationSec = 0,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      id:           json['id'] as String,
      callType:     CallType.fromString(json['call_type'] as String? ?? 'voice'),
      roomType:     CallRoomType.fromString(json['room_type'] as String? ?? 'dm'),
      sourceRoomId: json['source_room_id'] as String,
      initiatorId:  json['initiator_id'] as String,
      status:       CallStatus.fromString(json['status'] as String? ?? 'ringing'),
      startedAt:    DateTime.parse(json['started_at'] as String),
      answeredAt: json['answered_at'] != null
          ? DateTime.parse(json['answered_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      endReason:   json['end_reason'] as String?,
      durationSec: json['duration_sec'] as int? ?? 0,
    );
  }

  CallModel copyWith({
    CallStatus? status,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endReason,
    int? durationSec,
  }) {
    return CallModel(
      id:           id,
      callType:     callType,
      roomType:     roomType,
      sourceRoomId: sourceRoomId,
      initiatorId:  initiatorId,
      status:       status     ?? this.status,
      startedAt:    startedAt,
      answeredAt:   answeredAt ?? this.answeredAt,
      endedAt:      endedAt    ?? this.endedAt,
      endReason:    endReason  ?? this.endReason,
      durationSec:  durationSec ?? this.durationSec,
    );
  }

  bool get isIncoming => status == CallStatus.ringing;

  /// 채널명 = call_id (Agora에서 사용)
  String get channelName => id;
}

// ─── CallParticipantModel ────────────────────────────────────────

class CallParticipantModel {
  final String id;
  final String callId;
  final String userId;
  final CallParticipantStatus status;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final int? agoraUid;

  // 표시용 (조인으로 채워짐)
  final String? nickname;
  final String? avatarUrl;

  const CallParticipantModel({
    required this.id,
    required this.callId,
    required this.userId,
    required this.status,
    this.joinedAt,
    this.leftAt,
    this.agoraUid,
    this.nickname,
    this.avatarUrl,
  });

  factory CallParticipantModel.fromJson(Map<String, dynamic> json) {
    return CallParticipantModel(
      id:       json['id'] as String,
      callId:   json['call_id'] as String,
      userId:   json['user_id'] as String,
      status:   CallParticipantStatus.fromString(
          json['status'] as String? ?? 'invited'),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
      leftAt: json['left_at'] != null
          ? DateTime.parse(json['left_at'] as String)
          : null,
      agoraUid:  json['agora_uid'] as int?,
      nickname:  json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

// ─── Token 응답 ──────────────────────────────────────────────────

class AgoraTokenResponse {
  final String token;
  final int agoraUid;
  final String appId;
  final String channel;
  final int expiresIn;

  const AgoraTokenResponse({
    required this.token,
    required this.agoraUid,
    required this.appId,
    required this.channel,
    required this.expiresIn,
  });

  factory AgoraTokenResponse.fromJson(Map<String, dynamic> json) {
    return AgoraTokenResponse(
      token:     json['token'] as String,
      agoraUid:  json['agora_uid'] as int,
      appId:     json['app_id'] as String,
      channel:   json['channel'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }
}

// ─── 통화 이벤트 (UI에서 listen) ─────────────────────────────────

/// 통화 진행 중 발생하는 원격 사용자 이벤트
class RemoteUserEvent {
  final int agoraUid;
  final RemoteUserEventType type;
  final bool? muted;       // muted 변경 시
  final bool? videoEnabled; // video 변경 시

  const RemoteUserEvent({
    required this.agoraUid,
    required this.type,
    this.muted,
    this.videoEnabled,
  });
}

enum RemoteUserEventType {
  joined,
  left,
  audioMuted,
  videoMuted,
  videoEnabled,
}