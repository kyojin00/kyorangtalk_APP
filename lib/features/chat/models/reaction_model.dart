// ═══════════════════════════════════════════════════
// 메시지 반응 모델
// ═══════════════════════════════════════════════════
class ReactionModel {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  ReactionModel({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      id:        json['id'] as String,
      messageId: json['message_id'] as String,
      userId:    json['user_id'] as String,
      emoji:     json['emoji'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'message_id': messageId,
        'user_id':    userId,
        'emoji':      emoji,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════
// 같은 이모지끼리 그룹핑한 결과 (UI 표시용)
// ═══════════════════════════════════════════════════
class ReactionGroup {
  final String emoji;
  final int count;
  final bool reactedByMe;
  final List<String> userIds;

  ReactionGroup({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
    required this.userIds,
  });
}