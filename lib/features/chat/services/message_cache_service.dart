import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message_model.dart';
import '../../group_chat/models/group_message_model.dart';

// ═══════════════════════════════════════════════════
// 💾 MessageCacheService
//
// Hive 기반 메시지 영구 캐시.
// 앱 재시작 후에도 메시지가 즉시 표시되도록 디스크에 저장.
//
// 구조:
//   - Hive Box ('kt_message_cache') 하나에 모든 방 저장
//   - 키 형식: 'dm_<roomId>' 또는 'group_<roomId>'
//   - 값: JSON String (messages + 메타데이터)
//   - 방당 최근 200개 메시지, 총 30개 방 유지 (LRU)
//
// 동기/비동기:
//   - load: 동기 (Hive 메모리 캐시 활용, ~수 ms)
//   - save / remove: 비동기 (fire-and-forget으로 호출)
// ═══════════════════════════════════════════════════
class MessageCacheService {
  static const String _boxName = 'kt_message_cache';
  static const int kMaxMessagesPerRoom = 200;
  static const int kMaxRooms = 30;

  static Box<String>? _box;
  static bool _initialized = false;

  // LRU 추적 (방 ID 순서)
  static final List<String> _lru = [];

  // ───────────────────────────────────────────────
  // 초기화
  // ───────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _initialized = true;

    // 기존 키들로 LRU 초기화 (마지막 저장 순서 알 수 없어 임의 순서)
    final keys = _box!.keys.cast<String>().toList();
    _lru.clear();
    _lru.addAll(keys
        .map((k) => k.startsWith('dm_')
            ? k.substring(3)
            : k.startsWith('group_')
                ? k.substring(6)
                : null)
        .whereType<String>()
        .toSet()
        .toList());

    print('✅ MessageCacheService 초기화 완료 '
        '(entries: ${_box?.length ?? 0}, rooms: ${_lru.length})');
  }

  static Box<String>? get _safeBox => _initialized ? _box : null;

  static String _dmKey(String roomId) => 'dm_$roomId';
  static String _groupKey(String roomId) => 'group_$roomId';

  // ───────────────────────────────────────────────
  // DM 캐시
  // ───────────────────────────────────────────────
  static CachedDMSnapshot? loadDM(String roomId) {
    final box = _safeBox;
    if (box == null) return null;

    final raw = box.get(_dmKey(roomId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msgsJson = (json['messages'] as List).cast<dynamic>();
      final messages = msgsJson
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .toList();

      final hiddenAtStr = json['hiddenAt'] as String?;
      final hasMore = json['hasMore'] as bool? ?? false;
      final savedAtStr = json['savedAt'] as String;

      _touchLRU(roomId);

      return CachedDMSnapshot(
        messages: messages,
        hiddenAt:
            hiddenAtStr != null ? DateTime.parse(hiddenAtStr).toLocal() : null,
        hasMore: hasMore,
        savedAt: DateTime.parse(savedAtStr),
      );
    } catch (e) {
      print('🔴 [MessageCache] DM 로드 실패: $e');
      // 망가진 데이터 제거
      box.delete(_dmKey(roomId));
      return null;
    }
  }

  static Future<void> saveDM({
    required String roomId,
    required List<MessageModel> messages,
    required DateTime? hiddenAt,
    required bool hasMore,
  }) async {
    final box = _safeBox;
    if (box == null) return;

    var msgs = messages;
    var capped = hasMore;
    if (msgs.length > kMaxMessagesPerRoom) {
      msgs = msgs.sublist(msgs.length - kMaxMessagesPerRoom);
      capped = true;
    }

    try {
      final json = {
        'messages': msgs.map(_messageToMap).toList(),
        'hiddenAt': hiddenAt?.toUtc().toIso8601String(),
        'hasMore': capped,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await box.put(_dmKey(roomId), jsonEncode(json));
      _touchLRU(roomId);
    } catch (e) {
      print('🔴 [MessageCache] DM 저장 실패: $e');
    }
  }

  static Future<void> removeDM(String roomId) async {
    _lru.remove(roomId);
    await _safeBox?.delete(_dmKey(roomId));
  }

  // ───────────────────────────────────────────────
  // 그룹 캐시
  // ───────────────────────────────────────────────
  static CachedGroupSnapshot? loadGroup(String roomId) {
    final box = _safeBox;
    if (box == null) return null;

    final raw = box.get(_groupKey(roomId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msgsJson = (json['messages'] as List).cast<dynamic>();
      final messages = msgsJson
          .map((m) =>
              GroupMessageModel.fromJson(m as Map<String, dynamic>))
          .toList();

      final joinedAtStr = json['joinedAt'] as String?;
      final hasMore = json['hasMore'] as bool? ?? false;
      final savedAtStr = json['savedAt'] as String;

      _touchLRU(roomId);

      return CachedGroupSnapshot(
        messages: messages,
        joinedAt:
            joinedAtStr != null ? DateTime.parse(joinedAtStr).toLocal() : null,
        hasMore: hasMore,
        savedAt: DateTime.parse(savedAtStr),
      );
    } catch (e) {
      print('🔴 [MessageCache] Group 로드 실패: $e');
      box.delete(_groupKey(roomId));
      return null;
    }
  }

  static Future<void> saveGroup({
    required String roomId,
    required List<GroupMessageModel> messages,
    required DateTime? joinedAt,
    required bool hasMore,
  }) async {
    final box = _safeBox;
    if (box == null) return;

    var msgs = messages;
    var capped = hasMore;
    if (msgs.length > kMaxMessagesPerRoom) {
      msgs = msgs.sublist(msgs.length - kMaxMessagesPerRoom);
      capped = true;
    }

    try {
      final json = {
        'messages': msgs.map(_groupMessageToMap).toList(),
        'joinedAt': joinedAt?.toUtc().toIso8601String(),
        'hasMore': capped,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await box.put(_groupKey(roomId), jsonEncode(json));
      _touchLRU(roomId);
    } catch (e) {
      print('🔴 [MessageCache] Group 저장 실패: $e');
    }
  }

  static Future<void> removeGroup(String roomId) async {
    _lru.remove(roomId);
    await _safeBox?.delete(_groupKey(roomId));
  }

  // ───────────────────────────────────────────────
  // LRU
  // ───────────────────────────────────────────────
  static void _touchLRU(String roomId) {
    _lru.remove(roomId);
    _lru.add(roomId);

    while (_lru.length > kMaxRooms) {
      final evicted = _lru.removeAt(0);
      _safeBox?.delete(_dmKey(evicted));
      _safeBox?.delete(_groupKey(evicted));
    }
  }

  // ───────────────────────────────────────────────
  // 전체 삭제 (로그아웃 등)
  // ───────────────────────────────────────────────
  static Future<void> clearAll() async {
    _lru.clear();
    await _safeBox?.clear();
  }

  // ───────────────────────────────────────────────
  // 직렬화 헬퍼 (모델 파일 안 건드림)
  // ───────────────────────────────────────────────
  static Map<String, dynamic> _messageToMap(MessageModel m) {
    return {
      'id': m.id,
      'sender_id': m.senderId,
      'room_id': m.receiverId, // MessageModel.receiverId는 사실 room_id
      'content': m.content,
      'is_read': m.isRead,
      'is_deleted': m.isDeleted,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      if (m.imageUrl != null) 'image_url': m.imageUrl,
      if (m.imageUrls != null) 'image_urls': m.imageUrls,
      if (m.replyToId != null) 'reply_to_id': m.replyToId,
      if (m.replyToContent != null) 'reply_to_content': m.replyToContent,
      if (m.audioUrl != null) 'audio_url': m.audioUrl,
      if (m.audioDuration != null) 'audio_duration': m.audioDuration,
      if (m.audioTranscript != null)
        'audio_transcript': m.audioTranscript,
      if (m.audioTranscriptStatus != null)
        'audio_transcript_status': m.audioTranscriptStatus,
      if (m.gameData != null) 'game_data': m.gameData,
      if (m.pollId != null) 'poll_id': m.pollId,
      if (m.fileUrl != null) 'file_url': m.fileUrl,
      if (m.fileName != null) 'file_name': m.fileName,
      if (m.fileSize != null) 'file_size': m.fileSize,
      if (m.fileType != null) 'file_type': m.fileType,
      if (m.locationShareId != null)
        'location_share_id': m.locationShareId,
      if (m.scheduleEventId != null)
        'schedule_event_id': m.scheduleEventId,
    };
  }

  static Map<String, dynamic> _groupMessageToMap(GroupMessageModel m) {
    return {
      'id': m.id,
      'room_id': m.roomId,
      'sender_id': m.senderId,
      'content': m.content,
      'is_deleted': m.isDeleted,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      'msg_type': m.msgType,
      if (m.imageUrl != null) 'image_url': m.imageUrl,
      if (m.imageUrls != null) 'image_urls': m.imageUrls,
      if (m.replyToId != null) 'reply_to_id': m.replyToId,
      if (m.replyToContent != null) 'reply_to_content': m.replyToContent,
      if (m.senderNickname != null) 'sender_nickname': m.senderNickname,
      if (m.senderAvatar != null) 'sender_avatar': m.senderAvatar,
      if (m.audioUrl != null) 'audio_url': m.audioUrl,
      if (m.audioDuration != null) 'audio_duration': m.audioDuration,
      if (m.audioTranscript != null)
        'audio_transcript': m.audioTranscript,
      if (m.audioTranscriptStatus != null)
        'audio_transcript_status': m.audioTranscriptStatus,
      if (m.gameData != null) 'game_data': m.gameData,
      if (m.pollId != null) 'poll_id': m.pollId,
      if (m.fileUrl != null) 'file_url': m.fileUrl,
      if (m.fileName != null) 'file_name': m.fileName,
      if (m.fileSize != null) 'file_size': m.fileSize,
      if (m.fileType != null) 'file_type': m.fileType,
      if (m.locationShareId != null)
        'location_share_id': m.locationShareId,
      if (m.scheduleEventId != null)
        'schedule_event_id': m.scheduleEventId,
    };
  }
}

// ═══════════════════════════════════════════════════
// 스냅샷 모델 (provider에서 import해서 사용)
// ═══════════════════════════════════════════════════
class CachedDMSnapshot {
  final List<MessageModel> messages;
  final DateTime? hiddenAt;
  final bool hasMore;
  final DateTime savedAt;

  CachedDMSnapshot({
    required this.messages,
    required this.hiddenAt,
    required this.hasMore,
    required this.savedAt,
  });
}

class CachedGroupSnapshot {
  final List<GroupMessageModel> messages;
  final DateTime? joinedAt;
  final bool hasMore;
  final DateTime savedAt;

  CachedGroupSnapshot({
    required this.messages,
    required this.joinedAt,
    required this.hasMore,
    required this.savedAt,
  });
}