class GroupRoomModel {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String createdBy;
  final String inviteCode;
  final int memberCount;
  final String roomType;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String category;
  final String createdAt;
  final String myRole;
  final int unreadCount;
  final int likeCount;
  final List<String> tags;
  final bool hasPassword;                                       // ⭐ NEW

  GroupRoomModel({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.createdBy,
    required this.inviteCode,
    required this.memberCount,
    required this.roomType,
    this.lastMessage,
    this.lastMessageAt,
    required this.category,
    required this.createdAt,
    required this.myRole,
    this.unreadCount = 0,
    this.likeCount = 0,
    this.tags = const [],
    this.hasPassword = false,                                   // ⭐ NEW
  });

  bool get isOpen => roomType == 'open';

  // ✨ 권한 체크 getter
  bool get isAdmin => myRole == 'admin';
  bool get isModerator => myRole == 'moderator';
  bool get isMember => myRole == 'member';

  // ✨ 강퇴 가능 여부 (방장 OR 관리자)
  bool get canModerate => isAdmin || isModerator;

  // ✨ 관리자 임명/해임 가능 여부 (방장만)
  bool get canManageRoles => isAdmin;
}