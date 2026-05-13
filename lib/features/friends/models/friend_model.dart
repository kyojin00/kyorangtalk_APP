// ═══════════════════════════════════════════════
// 친구 관련 모델
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
  final bool isFavorite;        // ⭐ NEW

  FriendModel({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.friendId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
    this.isFavorite = false,
  });

  FriendModel copyWith({bool? isFavorite}) {
    return FriendModel(
      id:            id,
      requesterId:   requesterId,
      receiverId:    receiverId,
      status:        status,
      friendId:      friendId,
      nickname:      nickname,
      avatarUrl:     avatarUrl,
      statusMessage: statusMessage,
      isFavorite:    isFavorite ?? this.isFavorite,
    );
  }
}

class SuggestedFriend {
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final String? statusMessage;
  final int mutualCount;
  final List<String> mutualNicknames;
  final int mutualGroupCount;
  final bool isNewUser;

  SuggestedFriend({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.statusMessage,
    required this.mutualCount,
    required this.mutualNicknames,
    this.mutualGroupCount = 0,
    this.isNewUser = false,
  });

  String get reasonText {
    final parts = <String>[];
    if (mutualCount > 0) parts.add('공통 친구 $mutualCount명');
    if (mutualGroupCount > 0) parts.add('같은 채팅방 $mutualGroupCount개');
    if (parts.isEmpty && isNewUser) return '신규 가입';
    if (parts.isEmpty) return '추천';
    return parts.join(' · ');
  }
}