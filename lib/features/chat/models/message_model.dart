class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final bool isRead;
  final bool isDeleted;
  final DateTime createdAt;
  final String? imageUrl;
  final String? replyToId;
  final String? replyToContent;
  
  // ✨ 음성 메시지 필드
  final String? audioUrl;
  final int? audioDuration;

  // ✨ 🎮 게임 데이터 필드
  final Map<String, dynamic>? gameData;

  // ✨ 📊 투표 ID
  final String? pollId;

  // ✨ 📎 파일 필드
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;      // 바이트
  final String? fileType;   // MIME 타입

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.isRead,
    required this.isDeleted,
    required this.createdAt,
    this.imageUrl,
    this.replyToId,
    this.replyToContent,
    this.audioUrl,
    this.audioDuration,
    this.gameData,
    this.pollId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileType,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id:             json['id'] as String,
      senderId:       json['sender_id'] as String,
      receiverId:     json['room_id'] as String,
      content:        json['content'] as String? ?? '',
      isRead:         json['is_read'] as bool? ?? false,
      isDeleted:      json['is_deleted'] as bool? ?? false,
      createdAt:      DateTime.parse(json['created_at'] as String).toLocal(),
      imageUrl:       json['image_url'] as String?,
      replyToId:      json['reply_to_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      audioUrl:       json['audio_url'] as String?,
      audioDuration:  json['audio_duration'] as int?,
      gameData:       json['game_data'] as Map<String, dynamic>?,
      pollId:         json['poll_id'] as String?,
      fileUrl:        json['file_url'] as String?,
      fileName:       json['file_name'] as String?,
      fileSize:       json['file_size'] as int?,
      fileType:       json['file_type'] as String?,
    );
  }

  MessageModel copyWith({bool? isRead, bool? isDeleted}) {
    return MessageModel(
      id:             id,
      senderId:       senderId,
      receiverId:     receiverId,
      content:        content,
      isRead:         isRead ?? this.isRead,
      isDeleted:      isDeleted ?? this.isDeleted,
      createdAt:      createdAt,
      imageUrl:       imageUrl,
      replyToId:      replyToId,
      replyToContent: replyToContent,
      audioUrl:       audioUrl,
      audioDuration:  audioDuration,
      gameData:       gameData,
      pollId:         pollId,
      fileUrl:        fileUrl,
      fileName:       fileName,
      fileSize:       fileSize,
      fileType:       fileType,
    );
  }

  // ✨ 유용한 getter
  bool get isVoiceMessage => audioUrl != null;
  bool get isImageMessage => imageUrl != null;
  bool get isGameMessage  => gameData != null;
  bool get isPollMessage  => pollId != null;
  bool get isFileMessage  => fileUrl != null;
}