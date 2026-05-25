import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

// ═══════════════════════════════════════════════════
// 친구 / 프로필 디스크 캐시 (Hive)
//
// - 메시지 캐시와 같은 박스(kt_message_cache)를 재사용
// - ⭐ MessageCacheService가 Box<String>으로 열기 때문에 타입 일치 필수
//   (Box<dynamic>으로 접근하면 HiveError: box is already open and of type Box<String>)
// - 키 prefix: profile_<userId>, friends_<userId>
// ═══════════════════════════════════════════════════
class FriendCacheService {
  static const _boxName = 'kt_message_cache';

  // ⭐ Box<String>으로 타입 명시 — MessageCacheService와 동일하게
  static Box<String> get _box => Hive.box<String>(_boxName);

  // ── 내 프로필 ──
  static Map<String, dynamic>? loadProfile(String userId) {
    try {
      final raw = _box.get('profile_$userId');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      print('🔴 [FriendCache] loadProfile 오류: $e');
      return null;
    }
  }

  static Future<void> saveProfile(
      String userId, Map<String, dynamic> profile) async {
    try {
      await _box.put('profile_$userId', jsonEncode(profile));
    } catch (e) {
      print('🔴 [FriendCache] saveProfile 오류: $e');
    }
  }

  // ── 친구 목록 ──
  static List<Map<String, dynamic>>? loadFriends(String userId) {
    try {
      final raw = _box.get('friends_$userId');
      if (raw == null) return null;
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      print('🔴 [FriendCache] loadFriends 오류: $e');
      return null;
    }
  }

  static Future<void> saveFriends(
      String userId, List<Map<String, dynamic>> friends) async {
    try {
      await _box.put('friends_$userId', jsonEncode(friends));
    } catch (e) {
      print('🔴 [FriendCache] saveFriends 오류: $e');
    }
  }

  // 사용자별 부분 삭제가 필요할 때만 사용
  static Future<void> clearForUser(String userId) async {
    try {
      await _box.delete('profile_$userId');
      await _box.delete('friends_$userId');
    } catch (e) {
      print('🔴 [FriendCache] clearForUser 오류: $e');
    }
  }
}