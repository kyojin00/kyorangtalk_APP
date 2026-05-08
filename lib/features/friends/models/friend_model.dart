// ═══════════════════════════════════════════════
// 친구 관련 모델
// - FriendModel: 친구 관계 + 친구 프로필 정보
// - SuggestedFriend: 알 수도 있는 친구 (친구의 친구)
//
// 위치: lib/features/friends/models/friend_model.dart
// ═══════════════════════════════════════════════

class FriendModel {
  final String id;
  final String requesterId;
  final String receiverId;
  final String status;
  final String friendId;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;

  FriendModel({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.friendId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
  });
}

class SuggestedFriend {
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;
  final int mutualCount;
  final List<String> mutualNicknames;

  SuggestedFriend({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
    required this.mutualCount,
    required this.mutualNicknames,
  });
}