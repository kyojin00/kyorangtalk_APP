import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friend_model.dart';
import '../services/friend_cache_service.dart'; // ⭐ NEW

// ═══════════════════════════════════════════════
// 친구 관련 Provider 모음
//
// 위치: lib/features/friends/providers/friends_provider.dart
// ═══════════════════════════════════════════════

// ⭐ 변경: FutureProvider → StreamProvider
//   카톡식: 캐시 즉시 emit → 백그라운드 fresh fetch → 머지
final myProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;

  final controller = StreamController<Map<String, dynamic>?>();

  if (myId == null) {
    controller.add(null);
    Future.microtask(() => controller.close());
    return controller.stream;
  }

  // ⭐ ① 캐시 즉시 emit (있으면)
  final cached = FriendCacheService.loadProfile(myId);
  if (cached != null) {
    controller.add(cached);
  }

  // ⭐ ② 백그라운드 fresh fetch + 캐시 갱신
  supabase
      .from('kyorangtalk_profiles')
      .select('nickname, avatar_url, status_message')
      .eq('id', myId)
      .maybeSingle()
      .then((data) async {
    if (controller.isClosed) return;
    controller.add(data);
    if (data != null) {
      await FriendCacheService.saveProfile(
          myId, Map<String, dynamic>.from(data));
    }
  }).catchError((e) {
    print('🔴 myProfile fetch 오류: $e');
    if (!controller.isClosed && cached == null) {
      controller.addError(e);
    }
  });

  ref.onDispose(() {
    if (!controller.isClosed) controller.close();
  });

  return controller.stream;
});

// ⭐ 변경: FutureProvider → StreamProvider
//   카톡식: 캐시 즉시 emit → 백그라운드 fresh fetch → 머지
final friendsProvider = StreamProvider<List<FriendModel>>((ref) {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;

  final controller = StreamController<List<FriendModel>>();

  if (myId == null) {
    controller.add([]);
    Future.microtask(() => controller.close());
    return controller.stream;
  }

  // ⭐ ① 캐시 즉시 emit
  final cachedMaps = FriendCacheService.loadFriends(myId);
  if (cachedMaps != null) {
    try {
      final cachedList = cachedMaps.map(_friendFromMap).toList();
      controller.add(cachedList);
    } catch (e) {
      print('🔴 friends 캐시 파싱 오류: $e');
    }
  }

  // ⭐ ② 백그라운드 fresh fetch + 캐시 갱신
  _fetchFriends(supabase, myId).then((friends) async {
    if (controller.isClosed) return;
    controller.add(friends);
    try {
      final maps = friends.map(_friendToMap).toList();
      await FriendCacheService.saveFriends(myId, maps);
    } catch (e) {
      print('🔴 friends 캐시 저장 오류: $e');
    }
  }).catchError((e) {
    print('🔴 friends fetch 오류: $e');
    if (!controller.isClosed && cachedMaps == null) {
      controller.addError(e);
    }
  });

  ref.onDispose(() {
    if (!controller.isClosed) controller.close();
  });

  return controller.stream;
});

// 친구 목록 fetch (병렬화로 더 빠르게)
Future<List<FriendModel>> _fetchFriends(
    SupabaseClient supabase, String myId) async {
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

  // ⭐ 병렬 fetch (직렬 → 병렬: ~3 round-trips → 1 round-trip)
  final results = await Future.wait<dynamic>([
    supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url, status_message')
        .inFilter('id', friendIds),
    supabase
        .from('kyorangtalk_sub_profiles')
        .select('''
          user_id, nickname, avatar_url, status_message,
          kyorangtalk_sub_profile_viewers!inner(viewer_id)
        ''')
        .inFilter('user_id', friendIds)
        .eq('kyorangtalk_sub_profile_viewers.viewer_id', myId),
    supabase
        .from('kyorangtalk_friend_favorites')
        .select('friend_id')
        .eq('user_id', myId),
  ]);

  final profiles = results[0] as List;
  final subProfiles = results[1] as List;
  final favs = results[2] as List;

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  final subProfileMap = <String, Map<String, dynamic>>{};
  for (final sp in subProfiles) {
    subProfileMap[sp['user_id'] as String] =
        sp as Map<String, dynamic>;
  }

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
}

// ⭐ FriendModel ↔ Map 변환 (캐시 직렬화용)
Map<String, dynamic> _friendToMap(FriendModel f) {
  return {
    'id':            f.id,
    'requesterId':   f.requesterId,
    'receiverId':    f.receiverId,
    'status':        f.status,
    'friendId':      f.friendId,
    'nickname':      f.nickname,
    'avatarUrl':     f.avatarUrl,
    'statusMessage': f.statusMessage,
    'isFavorite':    f.isFavorite,
  };
}

FriendModel _friendFromMap(Map<String, dynamic> m) {
  return FriendModel(
    id:            m['id'] as String,
    requesterId:   m['requesterId'] as String,
    receiverId:    m['receiverId'] as String,
    status:        m['status'] as String,
    friendId:      m['friendId'] as String,
    nickname:      m['nickname'] as String,
    avatarUrl:     m['avatarUrl'] as String?,
    statusMessage: m['statusMessage'] as String?,
    isFavorite:    (m['isFavorite'] as bool?) ?? false,
  );
}

// ── 알 수도 있는 친구 (RPC) — 캐싱 안 함 (작은 영역) ──
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

// 즐겨찾기 토글
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

// 신고
Future<void> reportFriend({
  required String reportedUserId,
  required String reason,
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

// 추천 거부
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

// ── 받은 친구 요청 — 캐싱 안 함 (작은 영역, 배지만 표시) ──
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