import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════
/// DraftStore
///
/// 채팅방 입력창의 임시 메시지 저장 (앱 재시작해도 유지)
/// 카카오톡처럼 다른 화면 갔다 와도 입력 내용 보존
///
/// Key: 'kt_draft_<dm|group>_<roomId>'
/// ═══════════════════════════════════════════════════
class DraftStore {
  static String _keyFor({
    required String roomId,
    required bool isGroup,
  }) {
    final type = isGroup ? 'group' : 'dm';
    return 'kt_draft_${type}_$roomId';
  }

  /// Draft 저장 (빈 문자열이면 삭제)
  static Future<void> save({
    required String roomId,
    required bool isGroup,
    required String text,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyFor(roomId: roomId, isGroup: isGroup);

      if (text.trim().isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, text);
      }
    } catch (e) {
      debugPrint('🔴 [DraftStore] save 실패: $e');
    }
  }

  /// Draft 불러오기
  static Future<String> load({
    required String roomId,
    required bool isGroup,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyFor(roomId: roomId, isGroup: isGroup);
      return prefs.getString(key) ?? '';
    } catch (e) {
      debugPrint('🔴 [DraftStore] load 실패: $e');
      return '';
    }
  }

  /// Draft 삭제 (메시지 전송 성공 시 호출)
  static Future<void> clear({
    required String roomId,
    required bool isGroup,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyFor(roomId: roomId, isGroup: isGroup);
      await prefs.remove(key);
    } catch (e) {
      debugPrint('🔴 [DraftStore] clear 실패: $e');
    }
  }
}