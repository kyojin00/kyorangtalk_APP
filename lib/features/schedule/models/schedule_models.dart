// ═══════════════════════════════════════════════════
// 📅 Schedule Models
//
// 위치: lib/features/schedule/models/schedule_models.dart
//
// DB 테이블:
//   - kyorangtalk_schedule_events
//   - kyorangtalk_schedule_slots
//   - kyorangtalk_schedule_participants
// ═══════════════════════════════════════════════════

// ═══════════════════════════════════════════════════
// ScheduleEvent — 일정 이벤트
// ═══════════════════════════════════════════════════
class ScheduleEvent {
  final String id;
  final String roomId;
  final String roomType;         // 'dm' | 'group'
  final String creatorId;
  final String title;
  final String? description;

  /// 응답 가능 날짜 범위
  final DateTime dateFrom;       // date (시간 무시)
  final DateTime dateTo;         // date

  /// 하루 중 시간 범위 (예: "09:00", "22:00")
  final String timeFrom;
  final String timeTo;

  /// 슬롯 단위 (분). 30 또는 60
  final int slotMinutes;

  /// 확정된 시간 (있으면 확정 상태)
  final DateTime? confirmedStart;
  final DateTime? confirmedEnd;
  final DateTime? confirmedAt;

  final DateTime createdAt;
  final DateTime expiresAt;

  const ScheduleEvent({
    required this.id,
    required this.roomId,
    required this.roomType,
    required this.creatorId,
    required this.title,
    this.description,
    required this.dateFrom,
    required this.dateTo,
    required this.timeFrom,
    required this.timeTo,
    required this.slotMinutes,
    this.confirmedStart,
    this.confirmedEnd,
    this.confirmedAt,
    required this.createdAt,
    required this.expiresAt,
  });

  /// 확정된 일정인지
  bool get isConfirmed => confirmedStart != null;

  /// 만료됐는지
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 응답 가능 (만료 X + 확정 X)
  bool get isAcceptingResponses => !isExpired && !isConfirmed;

  /// 그리드 행 개수 (시간 슬롯 개수, 하루 기준)
  int get slotsPerDay {
    final fromMin = _parseTimeMin(timeFrom);
    final toMin   = _parseTimeMin(timeTo);
    return ((toMin - fromMin) / slotMinutes).round();
  }

  /// 그리드 열 개수 (날짜 개수)
  int get dayCount {
    return dateTo.difference(dateFrom).inDays + 1;
  }

  /// 그리드의 모든 슬롯 시작 시각들을 평탄화하여 반환
  /// (날짜별 → 시간별 순서)
  List<DateTime> allSlots() {
    final result = <DateTime>[];
    final fromMin = _parseTimeMin(timeFrom);

    for (int d = 0; d < dayCount; d++) {
      final day = dateFrom.add(Duration(days: d));
      for (int s = 0; s < slotsPerDay; s++) {
        final totalMin = fromMin + s * slotMinutes;
        final h = totalMin ~/ 60;
        final m = totalMin % 60;
        result.add(DateTime(day.year, day.month, day.day, h, m));
      }
    }
    return result;
  }

  /// 특정 날짜/시간 인덱스의 슬롯 시작 시각
  DateTime slotAt({required int dayIndex, required int slotIndex}) {
    final fromMin = _parseTimeMin(timeFrom);
    final totalMin = fromMin + slotIndex * slotMinutes;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final day = dateFrom.add(Duration(days: dayIndex));
    return DateTime(day.year, day.month, day.day, h, m);
  }

  /// "HH:mm" → 분으로 변환
  static int _parseTimeMin(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) {
    return ScheduleEvent(
      id:              json['id'] as String,
      roomId:          json['room_id'] as String,
      roomType:        json['room_type'] as String,
      creatorId:       json['creator_id'] as String,
      title:           json['title'] as String,
      description:     json['description'] as String?,
      dateFrom:        DateTime.parse(json['date_from'] as String),
      dateTo:          DateTime.parse(json['date_to'] as String),
      timeFrom:        json['time_from'] as String,
      timeTo:          json['time_to'] as String,
      slotMinutes:     (json['slot_minutes'] as num).toInt(),
      confirmedStart:  json['confirmed_start'] != null
          ? DateTime.parse(json['confirmed_start'] as String).toLocal()
          : null,
      confirmedEnd:    json['confirmed_end'] != null
          ? DateTime.parse(json['confirmed_end'] as String).toLocal()
          : null,
      confirmedAt:     json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String).toLocal()
          : null,
      createdAt:       DateTime.parse(json['created_at'] as String).toLocal(),
      expiresAt:       DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toInsertJson() {
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    return {
      'room_id':      roomId,
      'room_type':    roomType,
      'creator_id':   creatorId,
      'title':        title,
      if (description != null) 'description': description,
      'date_from':    dateOnly(dateFrom),
      'date_to':      dateOnly(dateTo),
      'time_from':    timeFrom,
      'time_to':      timeTo,
      'slot_minutes': slotMinutes,
      'expires_at':   expiresAt.toUtc().toIso8601String(),
    };
  }
}

// ═══════════════════════════════════════════════════
// ScheduleSlot — 한 사용자가 가능한 한 슬롯
// ═══════════════════════════════════════════════════
class ScheduleSlot {
  final String id;
  final String eventId;
  final String userId;
  final DateTime slotStart;
  final DateTime createdAt;

  const ScheduleSlot({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.slotStart,
    required this.createdAt,
  });

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) {
    return ScheduleSlot(
      id:        json['id'] as String,
      eventId:   json['event_id'] as String,
      userId:    json['user_id'] as String,
      slotStart: DateTime.parse(json['slot_start'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

// ═══════════════════════════════════════════════════
// ScheduleHeatmapEntry — 시간 슬롯별 응답자 수
// ═══════════════════════════════════════════════════
class ScheduleHeatmapEntry {
  final DateTime slotStart;
  final int userCount;

  const ScheduleHeatmapEntry({
    required this.slotStart,
    required this.userCount,
  });

  factory ScheduleHeatmapEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleHeatmapEntry(
      slotStart: DateTime.parse(json['slot_start'] as String).toLocal(),
      userCount: (json['user_count'] as num).toInt(),
    );
  }
}

// ═══════════════════════════════════════════════════
// ScheduleParticipant — 응답한 사용자
// ═══════════════════════════════════════════════════
class ScheduleParticipant {
  final String id;
  final String eventId;
  final String userId;
  final DateTime respondedAt;

  /// 조회 시 join 으로 채워짐
  final String? nickname;
  final String? avatarUrl;

  const ScheduleParticipant({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.respondedAt,
    this.nickname,
    this.avatarUrl,
  });

  factory ScheduleParticipant.fromJson(Map<String, dynamic> json) {
    return ScheduleParticipant(
      id:          json['id'] as String,
      eventId:     json['event_id'] as String,
      userId:      json['user_id'] as String,
      respondedAt: DateTime.parse(json['responded_at'] as String).toLocal(),
      nickname:    json['nickname'] as String?,
      avatarUrl:   json['avatar_url'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════
// ScheduleSummary — 화면 표시용 통합 데이터
// ═══════════════════════════════════════════════════
class ScheduleSummary {
  final ScheduleEvent event;
  final List<ScheduleHeatmapEntry> heatmap;
  final List<ScheduleParticipant> participants;
  final Set<DateTime> mySlots;   // 내가 선택한 슬롯들

  const ScheduleSummary({
    required this.event,
    required this.heatmap,
    required this.participants,
    required this.mySlots,
  });

  /// 슬롯 시작 시각 → 응답자 수
  Map<DateTime, int> get heatmapMap {
    return {
      for (final h in heatmap) h.slotStart: h.userCount,
    };
  }

  /// 최대 응답자 수
  int get maxCount {
    if (heatmap.isEmpty) return 0;
    return heatmap.map((h) => h.userCount).reduce((a, b) => a > b ? a : b);
  }

  /// 모두 가능한 슬롯들 (최적 시간 후보)
  List<DateTime> get bestSlots {
    if (participants.isEmpty) return [];
    final total = participants.length;
    return heatmap
        .where((h) => h.userCount == total)
        .map((h) => h.slotStart)
        .toList();
  }
}