import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 친구 관련 Provider 모음
//
// 위치: lib/features/friends/providers/friends_provider.dart
// ═══════════════════════════════════════════════

// ── 내 프로필 ──
final myProfileProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;
  return await supabase
      .from('kyorangtalk_profiles')
      .select('nickname, avatar_url, status_message')
      .eq('id', myId)
      .maybeSingle();
});

// ── 내 친구 목록 (즐겨찾기 포함, 즐겨찾기 우선 정렬) ──
final friendsProvider = FutureProvider<List<FriendModel>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .or('requester_id.eq.$myId,receiver_id.eq.$myId')
      .eq('status', 'accepted')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final friendIds = data.map((f) {
    return f['requester_id'] == myId
        ? f['receiver_id'] as String
        : f['requester_id'] as String;
  }).toList();

  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .inFilter('id', friendIds);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  final subProfiles = await supabase
      .from('kyorangtalk_sub_profiles')
      .select('''
        user_id, nickname, avatar_url, status_message,
        kyorangtalk_sub_profile_viewers!inner(viewer_id)
      ''')
      .inFilter('user_id', friendIds)
      .eq('kyorangtalk_sub_profile_viewers.viewer_id', myId);

  final subProfileMap = <String, Map<String, dynamic>>{};
  for (final sp in subProfiles) {
    subProfileMap[sp['user_id'] as String] = sp;
  }

  // ⭐ 즐겨찾기 ID Set 조회
  final favs = await supabase
      .from('kyorangtalk_friend_favorites')
      .select('friend_id')
      .eq('user_id', myId);
  final favoriteIds = <String>{
    for (final f in favs) f['friend_id'] as String,
  };

  final result = data.map((f) {
    final friendId = f['requester_id'] == myId
        ? f['receiver_id'] as String
        : f['requester_id'] as String;
    final mainProf = profileMap[friendId];
    final subProf = subProfileMap[friendId];

    final nickname = subProf != null
        ? (subProf['nickname'] as String? ??
            mainProf?['nickname'] as String? ??
            '알 수 없음')
        : (mainProf?['nickname'] as String? ?? '알 수 없음');

    final avatarUrl = subProf != null
        ? subProf['avatar_url'] as String?
        : mainProf?['avatar_url'] as String?;

    final statusMessage = subProf != null
        ? subProf['status_message'] as String?
        : mainProf?['status_message'] as String?;

    return FriendModel(
      id:            f['id'] as String,
      requesterId:   f['requester_id'] as String,
      receiverId:    f['receiver_id'] as String,
      status:        f['status'] as String,
      friendId:      friendId,
      nickname:      nickname,
      avatarUrl:     avatarUrl,
      statusMessage: statusMessage,
      isFavorite:    favoriteIds.contains(friendId),
    );
  }).toList();

  // 즐겨찾기 우선, 그 안에서 닉네임 가나다순
  result.sort((a, b) {
    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
    return a.nickname.compareTo(b.nickname);
  });

  return result;
});

// ── 알 수도 있는 친구 (RPC) ──
final friendSuggestionsProvider =
    FutureProvider<List<SuggestedFriend>>((ref) async {
  final supabase = Supabase.instance.client;

  try {
    final response = await supabase.rpc(
      'kyorangtalk_get_friend_suggestions',
      params: {'p_limit': 20},
    );

    if (response == null) return [];

    return (response as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final rawNames = map['out_mutual_nicknames'];
      final mutualNicknames = rawNames is List
          ? rawNames.whereType<String>().toList()
          : <String>[];

      return SuggestedFriend(
        userId:           map['out_user_id'] as String,
        nickname:         (map['out_nickname'] as String?) ?? '알 수 없음',
        avatarUrl:        map['out_avatar_url'] as String?,
        statusMessage:    map['out_status_message'] as String?,
        mutualCount:      (map['out_mutual_friends'] as num?)?.toInt() ?? 0,
        mutualNicknames:  mutualNicknames,
        mutualGroupCount: (map['out_mutual_groups'] as num?)?.toInt() ?? 0,
        isNewUser:        (map['out_is_new_user'] as bool?) ?? false,
      );
    }).toList();
  } catch (e) {
    print('🔴 친구 추천 로드 오류: $e');
    return [];
  }
});

// ⭐ 즐겨찾기 토글
Future<bool> toggleFriendFavorite(String friendId) async {
  try {
    final result = await Supabase.instance.client.rpc(
      'kyorangtalk_toggle_favorite',
      params: {'p_friend_id': friendId},
    );
    return result as bool;
  } catch (e) {
    print('🔴 즐겨찾기 토글 실패: $e');
    rethrow;
  }
}

// ⭐ 신고 (기존 kyorangtalk_reports 테이블 활용)
Future<void> reportFriend({
  required String reportedUserId,
  required String reason,        // 'spam', 'harassment', 'inappropriate', 'fake', 'other'
  String? description,
}) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) throw Exception('로그인 필요');

  await supabase.from('kyorangtalk_reports').insert({
    'reporter_id':      myId,
    'reported_user_id': reportedUserId,
    'report_type':      'user',
    'reason':           reason,
    'description':      description,
    'status':           'pending',
  });
}

// "관심 없음" — 추천 거부
Future<void> dismissFriendSuggestion(String userId) async {
  try {
    await Supabase.instance.client.rpc(
      'kyorangtalk_dismiss_friend_suggestion',
      params: {'p_dismissed_id': userId},
    );
  } catch (e) {
    print('🔴 추천 거부 실패: $e');
  }
}

// ── 받은 친구 요청 ──
final pendingRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .eq('receiver_id', myId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final ids = data.map((r) => r['requester_id'] as String).toList();
  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url')
      .inFilter('id', ids);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  return data.map((r) {
    final prof = profileMap[r['requester_id']];
    return {
      ...r,
      'nickname':   prof?['nickname'] ?? '알 수 없음',
      'avatar_url': prof?['avatar_url'],
    };
  }).toList();
});

// ── 보낸 친구 요청 ──
final sentRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final data = await supabase
      .from('kyorangtalk_friends')
      .select('*')
      .eq('requester_id', myId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);

  if (data.isEmpty) return [];

  final ids = data.map((r) => r['receiver_id'] as String).toList();
  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url')
      .inFilter('id', ids);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  return data.map((r) {
    final prof = profileMap[r['receiver_id']];
    return {
      ...r,
      'nickname':   prof?['nickname'] ?? '알 수 없음',
      'avatar_url': prof?['avatar_url'],
    };
  }).toList();
});