import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════
/// PendingMessage - 전송 대기/실패한 메시지
///
/// 일반 텍스트 메시지만 대상.
/// (이미지/음성/파일/게임/투표는 업로드 단계에서 실패 처리하므로 제외)
/// ═══════════════════════════════════════════════════
class PendingMessage {
  final String id;              // 로컬 ID (UUID)
  final String roomId;
  final bool isGroup;
  final String content;
  final String? replyToId;
  final String? replyToContent;
  final DateTime createdAt;
  final int retryCount;
  final String? errorMessage;

  PendingMessage({
    required this.id,
    required this.roomId,
    required this.isGroup,
    required this.content,
    this.replyToId,
    this.replyToContent,
    required this.createdAt,
    this.retryCount = 0,
    this.errorMessage,
  });

  PendingMessage copyWith({
    int? retryCount,
    String? errorMessage,
  }) {
    return PendingMessage(
      id: id,
      roomId: roomId,
      isGroup: isGroup,
      content: content,
      replyToId: replyToId,
      replyToContent: replyToContent,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'isGroup': isGroup,
        'content': content,
        'replyToId': replyToId,
        'replyToContent': replyToContent,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'errorMessage': errorMessage,
      };

  factory PendingMessage.fromJson(Map<String, dynamic> json) {
    return PendingMessage(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      isGroup: json['isGroup'] as bool,
      content: json['content'] as String,
      replyToId: json['replyToId'] as String?,
      replyToContent: json['replyToContent'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: (json['retryCount'] as int?) ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// ═══════════════════════════════════════════════════
/// PendingMessageStore - 영구 저장소
///
/// SharedPreferences에 JSON 배열로 저장
/// Key: 'kt_pending_messages'
/// ═══════════════════════════════════════════════════
class PendingMessageStore {
  static const String _storageKey = 'kt_pending_messages';
  static const int _maxStored = 50; // 무한정 쌓이는 것 방지

  /// 모든 pending 메시지 조회
  static Future<List<PendingMessage>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];

      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              PendingMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('🔴 [PendingStore] getAll 실패: $e');
      return [];
    }
  }

  /// 특정 방의 pending 메시지만 조회
  static Future<List<PendingMessage>> getForRoom({
    required String roomId,
    required bool isGroup,
  }) async {
    final all = await getAll();
    return all
        .where((m) => m.roomId == roomId && m.isGroup == isGroup)
        .toList();
  }

  /// 추가 (또는 같은 ID면 업데이트)
  static Future<void> upsert(PendingMessage msg) async {
    try {
      final all = await getAll();
      // 같은 ID 제거 (업데이트 케이스)
      all.removeWhere((m) => m.id == msg.id);
      all.add(msg);

      // 최대 개수 초과 시 오래된 것부터 제거
      if (all.length > _maxStored) {
        all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        all.removeRange(0, all.length - _maxStored);
      }

      await _saveAll(all);
    } catch (e) {
      debugPrint('🔴 [PendingStore] upsert 실패: $e');
    }
  }

  /// 삭제 (전송 성공 시 호출)
  static Future<void> remove(String id) async {
    try {
      final all = await getAll();
      all.removeWhere((m) => m.id == id);
      await _saveAll(all);
    } catch (e) {
      debugPrint('🔴 [PendingStore] remove 실패: $e');
    }
  }

  /// 특정 방의 pending 모두 삭제
  static Future<void> clearRoom({
    required String roomId,
    required bool isGroup,
  }) async {
    try {
      final all = await getAll();
      all.removeWhere((m) => m.roomId == roomId && m.isGroup == isGroup);
      await _saveAll(all);
    } catch (e) {
      debugPrint('🔴 [PendingStore] clearRoom 실패: $e');
    }
  }

  /// 전체 삭제 (디버그/리셋용)
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('🔴 [PendingStore] clearAll 실패: $e');
    }
  }

  static Future<void> _saveAll(List<PendingMessage> list) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(list.map((m) => m.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// ═══════════════════════════════════════════════════
  /// 로컬 ID 생성 (UUID v4 간이 버전)
  /// ═══════════════════════════════════════════════════
  static String generateLocalId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now * 2654435761) & 0xFFFFFFFF;
    return 'pending_${now}_$rand';
  }
}