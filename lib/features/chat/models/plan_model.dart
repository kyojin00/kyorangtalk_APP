// ═══════════════════════════════════════════════════
// 약속 (Plan) 데이터 모델
// ═══════════════════════════════════════════════════

class PlanModel {
  final String id;
  final String roomId;
  final String roomType; // 'dm' or 'group'
  final String sourceMessageId;
  final String createdBy;

  final String title;
  final DateTime scheduledAt;
  final String? location;
  final List<String> attendees;
  final String? notes;

  final String status; // 'upcoming' | 'completed' | 'cancelled'
  final bool isDismissed;

  final DateTime createdAt;
  final DateTime updatedAt;

  PlanModel({
    required this.id,
    required this.roomId,
    required this.roomType,
    required this.sourceMessageId,
    required this.createdBy,
    required this.title,
    required this.scheduledAt,
    this.location,
    required this.attendees,
    this.notes,
    required this.status,
    required this.isDismissed,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      roomType: json['room_type'] as String,
      sourceMessageId: json['source_message_id'] as String,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      location: json['location'] as String?,
      attendees: (json['attendees'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'upcoming',
      isDismissed: json['is_dismissed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 부분 업데이트용 (즉시 UI 반영)
  PlanModel copyWith({
    String? title,
    DateTime? scheduledAt,
    String? location,
    List<String>? attendees,
    String? notes,
    String? status,
    bool? isDismissed,
  }) {
    return PlanModel(
      id: id,
      roomId: roomId,
      roomType: roomType,
      sourceMessageId: sourceMessageId,
      createdBy: createdBy,
      title: title ?? this.title,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      location: location ?? this.location,
      attendees: attendees ?? this.attendees,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      isDismissed: isDismissed ?? this.isDismissed,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// 사용자에게 보여줄 친화적 시간 표현
  String get friendlyTime {
    final local = scheduledAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diffDays = target.difference(today).inDays;

    final hour = local.hour;
    final minute = local.minute;
    final ampm = hour < 12 ? '오전' : '오후';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = minute == 0
        ? '$ampm $h12시'
        : '$ampm $h12시 ${minute.toString().padLeft(2, '0')}분';

    if (diffDays == 0) return '오늘 $timeStr';
    if (diffDays == 1) return '내일 $timeStr';
    if (diffDays == -1) return '어제 $timeStr';
    if (diffDays > 1 && diffDays < 7) {
      final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
      final dayName = dayNames[(local.weekday - 1) % 7];
      return '${diffDays}일 후 ($dayName) $timeStr';
    }

    final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final dayName = dayNames[(local.weekday - 1) % 7];
    return '${local.month}월 ${local.day}일 ($dayName) $timeStr';
  }

  String get shortTime {
    final local = scheduledAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diffDays = target.difference(today).inDays;

    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');

    if (diffDays == 0) return '오늘 $h:$m';
    if (diffDays == 1) return '내일 $h:$m';
    return '${local.month}/${local.day} $h:$m';
  }

  bool get isUpcoming => status == 'upcoming' && !isDismissed;
  bool get isPast => scheduledAt.isBefore(DateTime.now());
}