// ═══════════════════════════════════════════════════
// 📍 LocationShareModel
//
// 위치: lib/features/location/models/location_share_model.dart
//
// DB 테이블: kyorangtalk_location_shares
// ═══════════════════════════════════════════════════

class LocationShareModel {
  final String id;
  final String roomId;
  final String roomType;       // 'dm' | 'group'
  final String senderId;
  final double latitude;
  final double longitude;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? endedAt;
  final DateTime lastUpdatedAt;
  final DateTime createdAt;

  const LocationShareModel({
    required this.id,
    required this.roomId,
    required this.roomType,
    required this.senderId,
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    required this.expiresAt,
    this.endedAt,
    required this.lastUpdatedAt,
    required this.createdAt,
  });

  /// 현재 활성 공유인지 (종료 안 됨 + 만료 안 됨)
  bool get isActive {
    if (endedAt != null) return false;
    return DateTime.now().isBefore(expiresAt);
  }

  /// 남은 시간 (초). 만료/종료 시 0
  int get remainingSeconds {
    if (!isActive) return 0;
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// 남은 시간 표시용 ("23분 남음", "1시간 12분 남음")
  String get remainingLabel {
    final s = remainingSeconds;
    if (s <= 0) return '종료됨';
    if (s < 60) return '${s}초 남음';
    final m = s ~/ 60;
    if (m < 60) return '${m}분 남음';
    final h = m ~/ 60;
    final mm = m % 60;
    return mm > 0 ? '${h}시간 ${mm}분 남음' : '${h}시간 남음';
  }

  factory LocationShareModel.fromJson(Map<String, dynamic> json) {
    return LocationShareModel(
      id:              json['id'] as String,
      roomId:          json['room_id'] as String,
      roomType:        json['room_type'] as String,
      senderId:        json['sender_id'] as String,
      latitude:        (json['latitude'] as num).toDouble(),
      longitude:       (json['longitude'] as num).toDouble(),
      startedAt:       DateTime.parse(json['started_at'] as String),
      expiresAt:       DateTime.parse(json['expires_at'] as String),
      endedAt:         json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      lastUpdatedAt:   DateTime.parse(json['last_updated_at'] as String),
      createdAt:       DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'room_id':    roomId,
      'room_type':  roomType,
      'sender_id':  senderId,
      'latitude':   latitude,
      'longitude':  longitude,
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  LocationShareModel copyWith({
    double? latitude,
    double? longitude,
    DateTime? endedAt,
    DateTime? lastUpdatedAt,
  }) {
    return LocationShareModel(
      id:            id,
      roomId:        roomId,
      roomType:      roomType,
      senderId:      senderId,
      latitude:      latitude ?? this.latitude,
      longitude:     longitude ?? this.longitude,
      startedAt:     startedAt,
      expiresAt:     expiresAt,
      endedAt:       endedAt ?? this.endedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      createdAt:     createdAt,
    );
  }
}


// ═══════════════════════════════════════════════════
// Broadcast로 전송되는 실시간 위치 업데이트 페이로드
// ═══════════════════════════════════════════════════

class LocationUpdateBroadcast {
  final String shareId;
  final String senderId;
  final double latitude;
  final double longitude;
  final bool ended;
  final DateTime timestamp;

  const LocationUpdateBroadcast({
    required this.shareId,
    required this.senderId,
    required this.latitude,
    required this.longitude,
    required this.ended,
    required this.timestamp,
  });

  factory LocationUpdateBroadcast.fromJson(Map<String, dynamic> json) {
    return LocationUpdateBroadcast(
      shareId:   json['share_id'] as String,
      senderId:  json['sender_id'] as String,
      latitude:  (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      ended:     json['ended'] as bool? ?? false,
      timestamp: DateTime.parse(json['ts'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'share_id':  shareId,
        'sender_id': senderId,
        'lat':       latitude,
        'lng':       longitude,
        'ended':     ended,
        'ts':        timestamp.toIso8601String(),
      };
}