class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final bool isRead;
  final bool isDeleted;
  final DateTime createdAt;
  final String? imageUrl;
  final List<String>? imageUrls;       // ⭐ NEW: 다중 이미지
  final String? replyToId;
  final String? replyToContent;

  // ✨ 음성 메시지 필드
  final String? audioUrl;
  final int? audioDuration;

  // ⭐ STT 변환
  final String? audioTranscript;
  final String? audioTranscriptStatus; // null | 'processing' | 'done' | 'failed'

  // ✨ 🎮 게임 데이터 필드
  final Map<String, dynamic>? gameData;

  // ✨ 📊 투표 ID
  final String? pollId;

  // ✨ 📎 파일 필드
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileType;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.isRead,
    required this.isDeleted,
    required this.createdAt,
    this.imageUrl,
    this.imageUrls,                    // ⭐ NEW
    this.replyToId,
    this.replyToContent,
    this.audioUrl,
    this.audioDuration,
    this.audioTranscript,
    this.audioTranscriptStatus,
    this.gameData,
    this.pollId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileType,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    // ⭐ image_urls 파싱 (Postgres text[] → List<String>)
    List<String>? parsedImageUrls;
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      parsedImageUrls = rawUrls.map((e) => e.toString()).toList();
      if (parsedImageUrls.isEmpty) parsedImageUrls = null;
    }

    return MessageModel(
      id:                     json['id'] as String,
      senderId:               json['sender_id'] as String,
      receiverId:             json['room_id'] as String,
      content:                json['content'] as String? ?? '',
      isRead:                 json['is_read'] as bool? ?? false,
      isDeleted:              json['is_deleted'] as bool? ?? false,
      createdAt:              DateTime.parse(json['created_at'] as String).toLocal(),
      imageUrl:               json['image_url'] as String?,
      imageUrls:              parsedImageUrls,                          // ⭐ NEW
      replyToId:              json['reply_to_id'] as String?,
      replyToContent:         json['reply_to_content'] as String?,
      audioUrl:               json['audio_url'] as String?,
      audioDuration:          json['audio_duration'] as int?,
      audioTranscript:        json['audio_transcript'] as String?,
      audioTranscriptStatus:  json['audio_transcript_status'] as String?,
      gameData:               json['game_data'] as Map<String, dynamic>?,
      pollId:                 json['poll_id'] as String?,
      fileUrl:                json['file_url'] as String?,
      fileName:               json['file_name'] as String?,
      fileSize:               json['file_size'] as int?,
      fileType:               json['file_type'] as String?,
    );
  }

  MessageModel copyWith({
    bool? isRead,
    bool? isDeleted,
    String? audioTranscript,
    String? audioTranscriptStatus,
  }) {
    return MessageModel(
      id:                    id,
      senderId:              senderId,
      receiverId:            receiverId,
      content:               content,
      isRead:                isRead ?? this.isRead,
      isDeleted:             isDeleted ?? this.isDeleted,
      createdAt:             createdAt,
      imageUrl:              imageUrl,
      imageUrls:             imageUrls,                                 // ⭐ NEW
      replyToId:             replyToId,
      replyToContent:        replyToContent,
      audioUrl:              audioUrl,
      audioDuration:         audioDuration,
      audioTranscript:       audioTranscript ?? this.audioTranscript,
      audioTranscriptStatus: audioTranscriptStatus ?? this.audioTranscriptStatus,
      gameData:              gameData,
      pollId:                pollId,
      fileUrl:               fileUrl,
      fileName:              fileName,
      fileSize:              fileSize,
      fileType:              fileType,
    );
  }

  // ✨ 유용한 getter
  bool get isVoiceMessage => audioUrl != null;
  bool get isImageMessage => imageUrl != null || (imageUrls != null && imageUrls!.isNotEmpty);
  bool get isMultiImageMessage => imageUrls != null && imageUrls!.length >= 2;  // ⭐ NEW
  bool get isGameMessage  => gameData != null;
  bool get isPollMessage  => pollId != null;
  bool get isFileMessage  => fileUrl != null;

  /// ⭐ 모든 이미지를 단일 리스트로 (단일 + 다중 통합 - 뷰어/그리드에서 사용)
  List<String> get allImageUrls {
    final result = <String>[];
    if (imageUrls != null && imageUrls!.isNotEmpty) {
      result.addAll(imageUrls!);
    } else if (imageUrl != null) {
      result.add(imageUrl!);
    }
    return result;
  }
}