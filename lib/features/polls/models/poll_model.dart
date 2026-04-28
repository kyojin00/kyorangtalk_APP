// ═══════════════════════════════════════════════
// 📊 투표 모델
// ═══════════════════════════════════════════════

/// 투표 옵션 (1개의 선택지)
class PollOption {
  final int id;
  final String text;

  PollOption({
    required this.id,
    required this.text,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id'] as int,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
  };
}

/// 투표 정보
class PollModel {
  final String id;
  final String roomId;
  final String roomType;  // 'dm' or 'group'
  final String createdBy;
  
  final String question;
  final List<PollOption> options;
  
  final bool allowMultiple;  // 복수 선택 가능
  final bool isAnonymous;    // 익명 투표
  
  final DateTime? expiresAt;  // 마감 시간 (NULL = 무기한)
  final bool isClosed;        // 수동 마감 여부
  
  final DateTime createdAt;
  final DateTime updatedAt;

  // ✨ 추가 정보 (조회 시 계산됨)
  final String? creatorNickname;
  final String? creatorAvatar;

  PollModel({
    required this.id,
    required this.roomId,
    required this.roomType,
    required this.createdBy,
    required this.question,
    required this.options,
    required this.allowMultiple,
    required this.isAnonymous,
    this.expiresAt,
    required this.isClosed,
    required this.createdAt,
    required this.updatedAt,
    this.creatorNickname,
    this.creatorAvatar,
  });

  factory PollModel.fromJson(Map<String, dynamic> json) {
    return PollModel(
      id:         json['id'] as String,
      roomId:     json['room_id'] as String,
      roomType:   json['room_type'] as String,
      createdBy:  json['created_by'] as String,
      question:   json['question'] as String,
      options:    (json['options'] as List)
          .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      allowMultiple: json['allow_multiple'] as bool? ?? false,
      isAnonymous:   json['is_anonymous'] as bool? ?? false,
      expiresAt:  json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String).toLocal()
          : null,
      isClosed:   json['is_closed'] as bool? ?? false,
      createdAt:  DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt:  DateTime.parse(json['updated_at'] as String).toLocal(),
      creatorNickname: json['creator_nickname'] as String?,
      creatorAvatar:   json['creator_avatar'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'room_id':        roomId,
    'room_type':      roomType,
    'created_by':     createdBy,
    'question':       question,
    'options':        options.map((o) => o.toJson()).toList(),
    'allow_multiple': allowMultiple,
    'is_anonymous':   isAnonymous,
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    'is_closed':      isClosed,
  };

  PollModel copyWith({
    bool? isClosed,
    DateTime? expiresAt,
    String? creatorNickname,
    String? creatorAvatar,
  }) {
    return PollModel(
      id:            id,
      roomId:        roomId,
      roomType:      roomType,
      createdBy:     createdBy,
      question:      question,
      options:       options,
      allowMultiple: allowMultiple,
      isAnonymous:   isAnonymous,
      expiresAt:     expiresAt ?? this.expiresAt,
      isClosed:      isClosed ?? this.isClosed,
      createdAt:     createdAt,
      updatedAt:     updatedAt,
      creatorNickname: creatorNickname ?? this.creatorNickname,
      creatorAvatar:   creatorAvatar ?? this.creatorAvatar,
    );
  }

  // ═══════════════════════════════════════════════
  // 유용한 getter
  // ═══════════════════════════════════════════════

  /// 투표가 마감됐는지 (수동 마감 or 시간 만료)
  bool get isEnded {
    if (isClosed) return true;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return true;
    return false;
  }

  /// 마감까지 남은 시간 (텍스트)
  String get remainingTimeText {
    if (isClosed) return '마감됨';
    if (expiresAt == null) return '무기한';
    
    final now = DateTime.now();
    if (now.isAfter(expiresAt!)) return '마감됨';
    
    final diff = expiresAt!.difference(now);
    
    if (diff.inDays >= 1) return '${diff.inDays}일 남음';
    if (diff.inHours >= 1) return '${diff.inHours}시간 남음';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 남음';
    return '곧 마감';
  }
}