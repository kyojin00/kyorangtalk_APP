import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/poll_model.dart';
import '../models/poll_vote_model.dart';

final _supabase = Supabase.instance.client;

// ═══════════════════════════════════════════════════
// 📊 투표 Provider - 특정 채팅방의 모든 투표
// ═══════════════════════════════════════════════════

/// 채팅방의 투표 목록 (실시간)
final pollsProvider = StreamProvider.autoDispose
    .family<List<PollModel>, String>((ref, roomId) {
  final controller = StreamController<List<PollModel>>();
  
  // ⭐ 마지막 데이터 캐시 (중복 emit 방지)
  String? lastDataHash;

  Future<void> fetchAndEmit() async {
    final data = await _supabase
        .from('kyorangtalk_polls')
        .select('*')
        .eq('room_id', roomId)
        .order('created_at', ascending: false);

    if (data.isEmpty) {
      const emptyHash = 'empty';
      if (lastDataHash != emptyHash) {
        lastDataHash = emptyHash;
        if (!controller.isClosed) controller.add([]);
      }
      return;
    }

    final creatorIds = data.map((p) => p['created_by'] as String).toSet().toList();
    final profiles = await _supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url')
        .inFilter('id', creatorIds);

    final profileMap = {
      for (final p in profiles) p['id'] as String: p
    };

    final polls = data.map((p) {
      final profile = profileMap[p['created_by']];
      return PollModel.fromJson({
        ...p,
        'creator_nickname': profile?['nickname'],
        'creator_avatar':   profile?['avatar_url'],
      });
    }).toList();

    // ⭐ 데이터 해시 비교 - 같으면 emit 안 함!
    final newHash = polls.map((p) => '${p.id}_${p.updatedAt?.millisecondsSinceEpoch ?? 0}').join('|');
    if (newHash != lastDataHash) {
      lastDataHash = newHash;
      if (!controller.isClosed) controller.add(polls);
    }
  }

  fetchAndEmit();

  // 투표 생성/수정/삭제
  final pollsChannel = _supabase
      .channel('polls_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_polls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();

  // ⭐ 투표 기록 변경 - pollsProvider는 더 이상 감지 안 함!
  // (각 투표의 결과는 pollResultProvider가 따로 처리)
  // → votesChannel 제거!

  ref.onDispose(() {
    _supabase.removeChannel(pollsChannel);
    controller.close();
  });

  return controller.stream;
});


// ═══════════════════════════════════════════════════
// 🗳️ 단일 투표 정보 Provider
// ═══════════════════════════════════════════════════

final singlePollProvider = StreamProvider.autoDispose
    .family<PollModel?, String>((ref, pollId) {
  final controller = StreamController<PollModel?>();
  
  // ⭐ 마지막 데이터 해시
  String? lastHash;

  Future<void> fetchAndEmit() async {
    final data = await _supabase
        .from('kyorangtalk_polls')
        .select('*')
        .eq('id', pollId)
        .maybeSingle();

    if (data == null) {
      const nullHash = 'null';
      if (lastHash != nullHash) {
        lastHash = nullHash;
        if (!controller.isClosed) controller.add(null);
      }
      return;
    }

    final profile = await _supabase
        .from('kyorangtalk_profiles')
        .select('nickname, avatar_url')
        .eq('id', data['created_by'] as String)
        .maybeSingle();

    final poll = PollModel.fromJson({
      ...data,
      'creator_nickname': profile?['nickname'],
      'creator_avatar':   profile?['avatar_url'],
    });

    // ⭐ 해시 비교
    final newHash = '${poll.id}_${poll.updatedAt?.millisecondsSinceEpoch ?? 0}_${poll.isClosed}';
    if (newHash != lastHash) {
      lastHash = newHash;
      if (!controller.isClosed) controller.add(poll);
    }
  }

  fetchAndEmit();

  final channel = _supabase
      .channel('poll_$pollId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_polls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: pollId,
        ),
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});


// ═══════════════════════════════════════════════════
// 📈 투표 집계 결과 Provider (실시간)
// ═══════════════════════════════════════════════════

final pollResultProvider = StreamProvider.autoDispose
    .family<PollResult, String>((ref, pollId) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<PollResult>();
  
  // ⭐ 마지막 데이터 해시
  String? lastHash;

  Future<void> fetchAndEmit() async {
    final pollData = await _supabase
        .from('kyorangtalk_polls')
        .select('options, is_anonymous')
        .eq('id', pollId)
        .single();

    final options = (pollData['options'] as List)
        .map((e) => PollOption.fromJson(e as Map<String, dynamic>))
        .toList();
    final isAnonymous = pollData['is_anonymous'] as bool? ?? false;

    final votesData = await _supabase
        .from('kyorangtalk_poll_votes')
        .select('*')
        .eq('poll_id', pollId);

    Map<String, Map<String, dynamic>> profileMap = {};
    if (!isAnonymous && votesData.isNotEmpty) {
      final userIds = votesData.map((v) => v['user_id'] as String).toList();
      final profiles = await _supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', userIds);

      profileMap = {
        for (final p in profiles) p['id'] as String: p
      };
    }

    final votes = votesData.map((v) {
      final profile = profileMap[v['user_id']];
      return PollVoteModel.fromJson({
        ...v,
        'user_nickname': profile?['nickname'],
        'user_avatar':   profile?['avatar_url'],
      });
    }).toList();

    final optionResults = <PollOptionResult>[];
    for (final option in options) {
      final optionVotes = votes
          .where((v) => v.optionIds.contains(option.id))
          .toList();

      optionResults.add(PollOptionResult(
        optionId:   option.id,
        optionText: option.text,
        voteCount:  optionVotes.length,
        voterIds:   optionVotes.map((v) => v.userId).toList(),
        voters:     optionVotes,
      ));
    }

    final totalVoters = votes.length;
    final totalVotes = votes.fold<int>(
      0, (sum, v) => sum + v.optionIds.length);
    
    final myVote = votes.where((v) => v.userId == user.id).firstOrNull;
    final iVoted = myVote != null;
    final myChoices = myVote?.optionIds ?? [];

    final result = PollResult(
      options:     optionResults,
      totalVoters: totalVoters,
      totalVotes:  totalVotes,
      iVoted:      iVoted,
      myChoices:   myChoices,
    );

    // ⭐ 해시 비교 - 결과가 같으면 emit 안 함!
    final newHash = '${optionResults.map((o) => '${o.optionId}:${o.voteCount}').join(',')}|$iVoted|${myChoices.join(',')}';
    if (newHash != lastHash) {
      lastHash = newHash;
      if (!controller.isClosed) controller.add(result);
    }
  }

  fetchAndEmit();

  // ⭐ 이 투표에 대한 voted만 감지 (필터 추가!)
  final votesChannel = _supabase
      .channel('poll_result_$pollId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_poll_votes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'poll_id',
          value: pollId,
        ),
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();

  final pollChannel = _supabase
      .channel('poll_info_$pollId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_polls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: pollId,
        ),
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(votesChannel);
    _supabase.removeChannel(pollChannel);
    controller.close();
  });

  return controller.stream;
});


// ═══════════════════════════════════════════════════
// 🎯 투표 생성/수정/삭제 함수들
// ═══════════════════════════════════════════════════

Future<String> createPoll({
  required String roomId,
  required String roomType,
  required String question,
  required List<String> options,
  bool allowMultiple = false,
  bool isAnonymous = false,
  Duration? duration,
}) async {
  final user = _supabase.auth.currentUser!;

  final optionsWithId = <Map<String, dynamic>>[];
  for (int i = 0; i < options.length; i++) {
    optionsWithId.add({
      'id':   i + 1,
      'text': options[i].trim(),
    });
  }

  final expiresAt = duration != null
      ? DateTime.now().toUtc().add(duration).toIso8601String()
      : null;

  final data = await _supabase.from('kyorangtalk_polls').insert({
    'room_id':        roomId,
    'room_type':      roomType,
    'created_by':     user.id,
    'question':       question.trim(),
    'options':        optionsWithId,
    'allow_multiple': allowMultiple,
    'is_anonymous':   isAnonymous,
    if (expiresAt != null) 'expires_at': expiresAt,
    'is_closed':      false,
  }).select('id').single();

  return data['id'] as String;
}


Future<void> vote({
  required String pollId,
  required List<int> optionIds,
}) async {
  final user = _supabase.auth.currentUser!;

  if (optionIds.isEmpty) {
    throw Exception('옵션을 1개 이상 선택해주세요');
  }

  await _supabase.from('kyorangtalk_poll_votes').upsert({
    'poll_id':    pollId,
    'user_id':    user.id,
    'option_ids': optionIds,
    'voted_at':   DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'poll_id,user_id');
}


Future<void> cancelVote(String pollId) async {
  final user = _supabase.auth.currentUser!;

  await _supabase
      .from('kyorangtalk_poll_votes')
      .delete()
      .eq('poll_id', pollId)
      .eq('user_id', user.id);
}


Future<void> closePoll(String pollId) async {
  await _supabase
      .from('kyorangtalk_polls')
      .update({
        'is_closed':  true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', pollId);
}


Future<void> deletePoll(String pollId) async {
  await _supabase
      .from('kyorangtalk_polls')
      .delete()
      .eq('id', pollId);
}