import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════
// 🛠 MyProfileService — Supabase 데이터 fetch + 액션 로직
// 메인 화면 코드 단순화를 위해 분리
//
// 사용법:
//   final service = MyProfileService(myId: _myId!);
//   final profile = await service.loadProfile();
//   await service.changeAvatar(file, ext, photosLength);
// ═══════════════════════════════════════════════════

class MyProfileService {
  final String myId;
  final SupabaseClient _supabase = Supabase.instance.client;

  MyProfileService({required this.myId});

  // ───────────────────────────────────────────────────
  // 데이터 로딩
  // ───────────────────────────────────────────────────
  Future<Map<String, dynamic>?> loadProfile() async {
    return await _supabase
        .from('kyorangtalk_profiles')
        .select('*')
        .eq('id', myId)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> loadStickers() async {
    final data = await _supabase
        .from('kyorangtalk_profile_stickers')
        .select('*')
        .eq('user_id', myId);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<int> loadSubProfilesCount() async {
    final data = await _supabase
        .from('kyorangtalk_sub_profiles')
        .select('id')
        .eq('user_id', myId);
    return data.length;
  }

  Future<List<Map<String, dynamic>>> loadPhotos() async {
    final data = await _supabase
        .from('kyorangtalk_profile_photos')
        .select('id, photo_url, visibility, position, created_at')
        .eq('user_id', myId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  // ───────────────────────────────────────────────────
  // 헬퍼
  // ───────────────────────────────────────────────────
  String getContentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  int _maxPosition(List<Map<String, dynamic>> photos) {
    if (photos.isEmpty) return 0;
    return photos
            .map((p) => (p['position'] as int?) ?? 0)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  // ───────────────────────────────────────────────────
  // 아바타 변경 — 갤러리에도 추가
  // ───────────────────────────────────────────────────
  Future<String> changeAvatar({
    required File file,
    required String ext,
    required List<Map<String, dynamic>> currentPhotos,
  }) async {
    final path =
        'avatars/$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('kyorangtalk').upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: getContentType(ext),
          ),
        );

    final url = _supabase.storage.from('kyorangtalk').getPublicUrl(path);

    // 프로필 사진 업데이트
    await _supabase
        .from('kyorangtalk_profiles')
        .update({'avatar_url': url})
        .eq('id', myId);

    // 갤러리에도 추가
    final maxPos = _maxPosition(currentPhotos);
    await _supabase.from('kyorangtalk_profile_photos').insert({
      'user_id': myId,
      'photo_url': url,
      'visibility': 'friends',
      'position': maxPos,
    });

    return url;
  }

  // ───────────────────────────────────────────────────
  // 배경 변경
  // ───────────────────────────────────────────────────
  Future<String> changeBackground({
    required File file,
    required String ext,
  }) async {
    final path =
        'backgrounds/$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('kyorangtalk').upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: getContentType(ext),
            cacheControl: '3600',
          ),
        );

    final url = _supabase.storage.from('kyorangtalk').getPublicUrl(path);

    await _supabase
        .from('kyorangtalk_profiles')
        .update({'background_url': url})
        .eq('id', myId);

    return url;
  }

  Future<void> removeBackground() async {
    await _supabase
        .from('kyorangtalk_profiles')
        .update({'background_url': null})
        .eq('id', myId);
  }

  // ───────────────────────────────────────────────────
  // 갤러리 사진 액션
  // ───────────────────────────────────────────────────
  Future<String> addGalleryPhoto({
    required File file,
    required String ext,
    required List<Map<String, dynamic>> currentPhotos,
  }) async {
    final path =
        'profile-photos/$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('kyorangtalk').upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: getContentType(ext),
            cacheControl: '3600',
          ),
        );

    final url = _supabase.storage.from('kyorangtalk').getPublicUrl(path);

    final maxPos = _maxPosition(currentPhotos);
    await _supabase.from('kyorangtalk_profile_photos').insert({
      'user_id': myId,
      'photo_url': url,
      'visibility': 'friends',
      'position': maxPos,
    });

    return url;
  }

  Future<void> deleteGalleryPhoto(String photoId) async {
    await _supabase
        .from('kyorangtalk_profile_photos')
        .delete()
        .eq('id', photoId);
  }

  Future<void> setPhotoAsAvatar(String url) async {
    await _supabase
        .from('kyorangtalk_profiles')
        .update({'avatar_url': url})
        .eq('id', myId);
  }

  // ───────────────────────────────────────────────────
  // 스티커 액션
  // ───────────────────────────────────────────────────
  Future<void> addSticker(String emoji) async {
    await _supabase.from('kyorangtalk_profile_stickers').insert({
      'user_id': myId,
      'emoji': emoji,
      'pos_x': 0.5,
      'pos_y': 0.4,
      'scale': 1.0,
      'rotation': 0.0,
    });
  }

  Future<void> updateStickerPosition(
      String id, double x, double y) async {
    await _supabase
        .from('kyorangtalk_profile_stickers')
        .update({'pos_x': x, 'pos_y': y})
        .eq('id', id);
  }

  Future<void> deleteSticker(String id) async {
    await _supabase
        .from('kyorangtalk_profile_stickers')
        .delete()
        .eq('id', id);
  }

  Future<void> updateStickerScale(String id, double scale) async {
    await _supabase
        .from('kyorangtalk_profile_stickers')
        .update({'scale': scale})
        .eq('id', id);
  }

  // ───────────────────────────────────────────────────
  // 프로필 저장 (닉네임, 상태 메시지)
  // ───────────────────────────────────────────────────
  Future<void> saveProfile({
    required String nickname,
    String? statusMessage,
  }) async {
    await _supabase.from('kyorangtalk_profiles').upsert({
      'id': myId,
      'nickname': nickname,
      'status_message':
          (statusMessage == null || statusMessage.isEmpty)
              ? null
              : statusMessage,
    });
  }
}