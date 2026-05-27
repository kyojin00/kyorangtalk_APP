import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message_model.dart';
import '../../group_chat/models/group_message_model.dart';

// ═══════════════════════════════════════════════════
// 💾 MessageCacheService
//
// Hive 기반 메시지 영구 캐시.
//
// ⭐ 정책 v3 기준 (2026.05):
//   - 서버는 무료 사용자 메시지 30일만 보관
//   - 로컬(Hive)은 영구 보관 역할 → 한도 대폭 확장
//   - Pro 사용자만 클라우드 백업으로 기기 이전 가능
//
// 구조:
//   - Hive Box ('kt_message_cache') 하나에 모든 방 저장
//   - 키 형식: 'dm_<roomId>' 또는 'group_<roomId>'
//   - 값: JSON String (messages + 메타데이터)
// ═══════════════════════════════════════════════════
class MessageCacheService {
  static const String _boxName = 'kt_message_cache';

  static const int kMaxMessagesPerRoom = 5000;
  static const int kMaxRooms = 500;

  static Box<String>? _box;
  static bool _initialized = false;

  static final List<String> _lru = [];

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _initialized = true;

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
  // 통계 / 백업용 API
  // ───────────────────────────────────────────────

  /// 캐시된 모든 DM 방 ID
  static List<String> getAllCachedDmRoomIds() {
    final box = _safeBox;
    if (box == null) return [];
    return box.keys
        .cast<String>()
        .where((k) => k.startsWith('dm_'))
        .map((k) => k.substring(3))
        .toList();
  }

  /// 캐시된 모든 그룹 방 ID
  static List<String> getAllCachedGroupRoomIds() {
    final box = _safeBox;
    if (box == null) return [];
    return box.keys
        .cast<String>()
        .where((k) => k.startsWith('group_'))
        .map((k) => k.substring(6))
        .toList();
  }

  /// 캐시된 모든 방 ID (dm + group 통합, 중복 제거)
  static List<String> getAllCachedRoomIds() {
    final ids = <String>{
      ...getAllCachedDmRoomIds(),
      ...getAllCachedGroupRoomIds(),
    };
    return ids.toList();
  }

  /// 전체 캐시 통계
  static CacheStats getStats() {
    final box = _safeBox;
    if (box == null) {
      return CacheStats(
          dmRoomCount: 0,
          groupRoomCount: 0,
          totalMessages: 0,
          totalBytes: 0);
    }

    int dmRooms = 0;
    int grpRooms = 0;
    int totalMsgs = 0;
    int totalBytes = 0;

    for (final key in box.keys.cast<String>()) {
      final raw = box.get(key);
      if (raw == null) continue;

      totalBytes += raw.length;

      if (key.startsWith('dm_')) dmRooms++;
      if (key.startsWith('group_')) grpRooms++;

      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final msgsJson = json['messages'];
        if (msgsJson is List) totalMsgs += msgsJson.length;
      } catch (_) {}
    }

    return CacheStats(
      dmRoomCount: dmRooms,
      groupRoomCount: grpRooms,
      totalMessages: totalMsgs,
      totalBytes: totalBytes,
    );
  }

  static Map<String, CachedDMSnapshot> exportAllDMs() {
    final box = _safeBox;
    if (box == null) return {};

    final result = <String, CachedDMSnapshot>{};
    for (final key in box.keys.cast<String>()) {
      if (!key.startsWith('dm_')) continue;
      final roomId = key.substring(3);
      final snapshot = loadDM(roomId);
      if (snapshot != null) {
        result[roomId] = snapshot;
      }
    }
    return result;
  }

  static Map<String, CachedGroupSnapshot> exportAllGroups() {
    final box = _safeBox;
    if (box == null) return {};

    final result = <String, CachedGroupSnapshot>{};
    for (final key in box.keys.cast<String>()) {
      if (!key.startsWith('group_')) continue;
      final roomId = key.substring(6);
      final snapshot = loadGroup(roomId);
      if (snapshot != null) {
        result[roomId] = snapshot;
      }
    }
    return result;
  }

  // ───────────────────────────────────────────────
  // ⭐ NEW: stale 방 캐시 정리
  //
  // - validDmRoomIds: DM 방 유효 집합. null이면 DM은 건드리지 않음
  // - validGroupRoomIds: 그룹 방 유효 집합. null이면 그룹은 건드리지 않음
  //
  // "나가기"한 방은 서버에 hidden_by 들어가 있지만 여전히 멤버이므로 유지됨
  // (호출자가 hidden 방도 validIds에 포함해서 전달해야 함)
  // ───────────────────────────────────────────────
  static Future<int> cleanupStaleRooms({
    Set<String>? validDmRoomIds,
    Set<String>? validGroupRoomIds,
  }) async {
    final box = _safeBox;
    if (box == null) return 0;

    int removed = 0;

    if (validDmRoomIds != null) {
      final dmKeys = box.keys
          .cast<String>()
          .where((k) => k.startsWith('dm_'))
          .toList();

      for (final key in dmKeys) {
        final roomId = key.substring(3);
        if (!validDmRoomIds.contains(roomId)) {
          await box.delete(key);
          _lru.remove(roomId);
          removed++;
          print('🧹 [Cache] stale DM 캐시 제거: $roomId');
        }
      }
    }

    if (validGroupRoomIds != null) {
      final grpKeys = box.keys
          .cast<String>()
          .where((k) => k.startsWith('group_'))
          .toList();

      for (final key in grpKeys) {
        final roomId = key.substring(6);
        if (!validGroupRoomIds.contains(roomId)) {
          await box.delete(key);
          _lru.remove(roomId);
          removed++;
          print('🧹 [Cache] stale Group 캐시 제거: $roomId');
        }
      }
    }

    if (removed > 0) {
      print('✅ [Cache] stale 캐시 정리 완료: $removed개');
    }

    return removed;
  }

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

  static Future<void> clearAll() async {
    _lru.clear();
    await _safeBox?.clear();
  }

  // ───────────────────────────────────────────────
  // 직렬화 헬퍼
  // ───────────────────────────────────────────────
  static Map<String, dynamic> _messageToMap(MessageModel m) {
    return {
      'id': m.id,
      'sender_id': m.senderId,
      'room_id': m.receiverId,
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
// 스냅샷 / 통계 모델
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

class CacheStats {
  final int dmRoomCount;
  final int groupRoomCount;
  final int totalMessages;
  final int totalBytes;

  CacheStats({
    required this.dmRoomCount,
    required this.groupRoomCount,
    required this.totalMessages,
    required this.totalBytes,
  });

  int get totalRooms => dmRoomCount + groupRoomCount;

  String get formattedSize {
    if (totalBytes < 1024) return '${totalBytes}B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)}KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}