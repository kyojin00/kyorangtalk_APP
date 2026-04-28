// ═══════════════════════════════════════════════
// 📊 투표 기록 모델
// ═══════════════════════════════════════════════

/// 개별 사용자의 투표 기록
class PollVoteModel {
  final String id;
  final String pollId;
  final String userId;
  
  /// 선택한 옵션 ID들 (복수 선택 가능)
  final List<int> optionIds;
  
  final DateTime votedAt;

  // ✨ 추가 정보 (조회 시 계산됨)
  final String? userNickname;
  final String? userAvatar;

  PollVoteModel({
    required this.id,
    required this.pollId,
    required this.userId,
    required this.optionIds,
    required this.votedAt,
    this.userNickname,
    this.userAvatar,
  });

  factory PollVoteModel.fromJson(Map<String, dynamic> json) {
    return PollVoteModel(
      id:         json['id'] as String,
      pollId:     json['poll_id'] as String,
      userId:     json['user_id'] as String,
      optionIds:  (json['option_ids'] as List).cast<int>(),
      votedAt:    DateTime.parse(json['voted_at'] as String).toLocal(),
      userNickname: json['user_nickname'] as String?,
      userAvatar:   json['user_avatar'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'poll_id':    pollId,
    'user_id':    userId,
    'option_ids': optionIds,
  };
}


// ═══════════════════════════════════════════════
// 투표 집계 결과 (UI용)
// ═══════════════════════════════════════════════

/// 옵션별 집계 결과
class PollOptionResult {
  final int optionId;
  final String optionText;
  final int voteCount;
  final List<String> voterIds;  // 투표한 사용자 ID들 (익명이 아닐 경우)
  final List<PollVoteModel> voters;  // 투표자 전체 정보 (익명이 아닐 경우)

  PollOptionResult({
    required this.optionId,
    required this.optionText,
    required this.voteCount,
    this.voterIds = const [],
    this.voters = const [],
  });

  /// 전체 투표 수 대비 퍼센트
  double percentage(int totalVotes) {
    if (totalVotes == 0) return 0;
    return (voteCount / totalVotes) * 100;
  }
}

/// 투표 전체 집계 결과
class PollResult {
  final List<PollOptionResult> options;
  final int totalVoters;      // 투표한 사람 수 (중복 제거)
  final int totalVotes;       // 총 투표 수 (복수 선택 시 여러 번)
  final bool iVoted;          // 내가 투표했는지
  final List<int> myChoices;  // 내가 선택한 옵션 ID들

  PollResult({
    required this.options,
    required this.totalVoters,
    required this.totalVotes,
    required this.iVoted,
    this.myChoices = const [],
  });

  /// 가장 많이 선택된 옵션
  PollOptionResult? get topOption {
    if (options.isEmpty) return null;
    return options.reduce((a, b) => a.voteCount > b.voteCount ? a : b);
  }
}