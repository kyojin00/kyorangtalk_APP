import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friend_model.dart';

// ═══════════════════════════════════════════════
// 친구 관련 Provider 모음
//
// 위치: lib/features/friends/providers/friends_provider.dart
//
// - myProfileProvider          : 내 프로필
// - friendsProvider            : 내 친구 목록 (서브 프로필 반영)
// - friendSuggestionsProvider  : 알 수도 있는 친구
// - pendingRequestsProvider    : 받은 친구 요청
// - sentRequestsProvider       : 보낸 친구 요청
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

// ── 내 친구 목록 ──
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

  return data.map((f) {
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
    );
  }).toList();
});

// ── 알 수도 있는 친구 (친구의 친구) ──
final friendSuggestionsProvider =
    FutureProvider<List<SuggestedFriend>>((ref) async {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser!.id;

  final myRelations = await supabase
      .from('kyorangtalk_friends')
      .select('requester_id, receiver_id, status')
      .or('requester_id.eq.$myId,receiver_id.eq.$myId');

  final myFriendIds = <String>{};
  final excludeIds = <String>{myId};

  for (final r in myRelations) {
    final reqId = r['requester_id'] as String;
    final recId = r['receiver_id'] as String;
    final status = r['status'] as String;
    final otherId = reqId == myId ? recId : reqId;

    excludeIds.add(otherId);
    if (status == 'accepted') {
      myFriendIds.add(otherId);
    }
  }

  if (myFriendIds.isEmpty) return [];

  final friendsOfFriends = await supabase
      .from('kyorangtalk_friends')
      .select('requester_id, receiver_id')
      .or(myFriendIds
          .map((fid) =>
              'requester_id.eq.$fid,receiver_id.eq.$fid')
          .join(','))
      .eq('status', 'accepted');

  final candidateMap = <String, Set<String>>{};

  for (final fof in friendsOfFriends) {
    final reqId = fof['requester_id'] as String;
    final recId = fof['receiver_id'] as String;

    String? mutualFriendId;
    String? candidateId;

    if (myFriendIds.contains(reqId) && !excludeIds.contains(recId)) {
      mutualFriendId = reqId;
      candidateId = recId;
    } else if (myFriendIds.contains(recId) &&
        !excludeIds.contains(reqId)) {
      mutualFriendId = recId;
      candidateId = reqId;
    }

    if (candidateId != null && mutualFriendId != null) {
      candidateMap
          .putIfAbsent(candidateId, () => <String>{})
          .add(mutualFriendId);
    }
  }

  if (candidateMap.isEmpty) return [];

  final candidateIds = candidateMap.keys.toList();
  final mutualFriendIds = <String>{};
  for (final mutuals in candidateMap.values) {
    mutualFriendIds.addAll(mutuals);
  }

  final allIds = [...candidateIds, ...mutualFriendIds];

  final profiles = await supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url, status_message')
      .inFilter('id', allIds);

  final profileMap = {for (final p in profiles) p['id'] as String: p};

  final suggestions = candidateMap.entries.map((entry) {
    final candidateId = entry.key;
    final mutuals = entry.value;
    final prof = profileMap[candidateId];

    final mutualNicknames = mutuals
        .map((id) => profileMap[id]?['nickname'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return SuggestedFriend(
      userId:          candidateId,
      nickname:        prof?['nickname'] as String? ?? '알 수 없음',
      avatarUrl:       prof?['avatar_url'] as String?,
      statusMessage:   prof?['status_message'] as String?,
      mutualCount:     mutuals.length,
      mutualNicknames: mutualNicknames,
    );
  }).toList();

  suggestions.sort((a, b) => b.mutualCount.compareTo(a.mutualCount));

  return suggestions.take(10).toList();
});

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