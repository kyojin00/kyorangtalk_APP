class GroupMessageModel {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final bool isDeleted;
  final DateTime createdAt;
  final String? imageUrl;
  final List<String>? imageUrls;       // ⭐ NEW: 다중 이미지
  final String? replyToId;
  final String? replyToContent;
  final String? senderNickname;
  final String? senderAvatar;
  final String msgType;

  // ✨ 음성 메시지
  final String? audioUrl;
  final int? audioDuration;

  // ⭐ STT 변환
  final String? audioTranscript;
  final String? audioTranscriptStatus;

  // ✨ 🎮 게임 데이터
  final Map<String, dynamic>? gameData;

  // ✨ 📊 투표
  final String? pollId;

  // ✨ 📎 파일
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileType;

  // 📍 위치 공유 ID
  final String? locationShareId;

  // 📅 일정 잡기 ID
  final String? scheduleEventId;

  GroupMessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.isDeleted,
    required this.createdAt,
    this.imageUrl,
    this.imageUrls,                    // ⭐ NEW
    this.replyToId,
    this.replyToContent,
    this.senderNickname,
    this.senderAvatar,
    this.msgType = 'text',
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
    this.locationShareId,              // 📍
    this.scheduleEventId,              // 📅
  });

  factory GroupMessageModel.fromJson(Map<String, dynamic> json) {
    // ⭐ image_urls 파싱
    List<String>? parsedImageUrls;
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      parsedImageUrls = rawUrls.map((e) => e.toString()).toList();
      if (parsedImageUrls.isEmpty) parsedImageUrls = null;
    }

    return GroupMessageModel(
      id:                    json['id'] as String,
      roomId:                json['room_id'] as String,
      senderId:              json['sender_id'] as String,
      content:               json['content'] as String? ?? '',
      isDeleted:             json['is_deleted'] as bool? ?? false,
      createdAt:             DateTime.parse(json['created_at'] as String).toLocal(),
      imageUrl:              json['image_url'] as String?,
      imageUrls:             parsedImageUrls,                           // ⭐ NEW
      replyToId:             json['reply_to_id'] as String?,
      replyToContent:        json['reply_to_content'] as String?,
      senderNickname:        json['sender_nickname'] as String?,
      senderAvatar:          json['sender_avatar'] as String?,
      msgType:               json['msg_type'] as String? ?? 'text',
      audioUrl:              json['audio_url'] as String?,
      audioDuration:         json['audio_duration'] as int?,
      audioTranscript:       json['audio_transcript'] as String?,
      audioTranscriptStatus: json['audio_transcript_status'] as String?,
      gameData:              json['game_data'] as Map<String, dynamic>?,
      pollId:                json['poll_id'] as String?,
      fileUrl:               json['file_url'] as String?,
      fileName:              json['file_name'] as String?,
      fileSize:              json['file_size'] as int?,
      fileType:              json['file_type'] as String?,
      locationShareId:       json['location_share_id'] as String?,      // 📍
      scheduleEventId:       json['schedule_event_id'] as String?,      // 📅
    );
  }

  // ✨ getter
  bool get isVoiceMessage => audioUrl != null;
  bool get isImageMessage => imageUrl != null || (imageUrls != null && imageUrls!.isNotEmpty);
  bool get isMultiImageMessage => imageUrls != null && imageUrls!.length >= 2;  // ⭐ NEW
  bool get isGameMessage  => gameData != null;
  bool get isPollMessage  => pollId != null;
  bool get isFileMessage  => fileUrl != null;
  bool get isLocationShareMessage => locationShareId != null;           // 📍
  bool get isScheduleMessage => scheduleEventId != null;                // 📅

  /// ⭐ 모든 이미지를 단일 리스트로
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