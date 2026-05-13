class ChatRoomModel {
  final String partnerId;
  final String partnerUsername;
  final String partnerName;
  final String? partnerAvatar;
  final String lastMessage;
  final DateTime lastTime;
  final int unreadCount;
  final bool isSent;
  final String roomId;
  final String? pinnedMessage;
  final bool isPinned;        // ⭐ NEW — 상단 고정 여부

  ChatRoomModel({
    required this.partnerId,
    required this.partnerUsername,
    required this.partnerName,
    this.partnerAvatar,
    required this.lastMessage,
    required this.lastTime,
    required this.unreadCount,
    required this.isSent,
    required this.roomId,
    this.pinnedMessage,
    this.isPinned = false,
  });
}