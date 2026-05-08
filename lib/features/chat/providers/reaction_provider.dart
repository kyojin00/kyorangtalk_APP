import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reaction_model.dart';

final _supabase = Supabase.instance.client;

// ═══════════════════════════════════════════════════
// 자주 쓰는 이모지 (퀵 리액션 6종)
// ═══════════════════════════════════════════════════
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

// ═══════════════════════════════════════════════════
// Provider 키
// ═══════════════════════════════════════════════════
class RoomReactionKey {
  final String roomId;
  final bool isGroup;
  const RoomReactionKey({required this.roomId, required this.isGroup});

  @override
  bool operator ==(Object other) =>
      other is RoomReactionKey &&
      other.roomId == roomId &&
      other.isGroup == isGroup;

  @override
  int get hashCode => Object.hash(roomId, isGroup);
}

// ═══════════════════════════════════════════════════
// 활성 채널 캐시 (subscribe 완료된 채널만 저장)
// toggleReaction이 같은 채널 인스턴스로 broadcast 보내기 위함
// ═══════════════════════════════════════════════════
final Map<String, RealtimeChannel> _activeReactionChannels = {};

// ═══════════════════════════════════════════════════
// 옵티미스틱 업데이트 버스
// (toggleReaction → 내 디바이스의 Provider state로 즉시 반영)
// ═══════════════════════════════════════════════════
class _LocalReactionEvent {
  final String channelName;
  final bool isAdd;
  final ReactionModel? reaction;
  final String? messageId;
  final String? reactionId;

  _LocalReactionEvent.add(this.channelName, ReactionModel r)
      : isAdd = true,
        reaction = r,
        messageId = null,
        reactionId = null;

  _LocalReactionEvent.remove(
      this.channelName, String mid, String rid)
      : isAdd = false,
        reaction = null,
        messageId = mid,
        reactionId = rid;
}

final StreamController<_LocalReactionEvent> _localReactionBus =
    StreamController<_LocalReactionEvent>.broadcast();

// ═══════════════════════════════════════════════════
// 방 단위 반응 Provider
// ═══════════════════════════════════════════════════
final roomReactionsProvider = StreamProvider.autoDispose
    .family<Map<String, List<ReactionModel>>, RoomReactionKey>((ref, key) {
  final controller =
      StreamController<Map<String, List<ReactionModel>>>();
  final reactions = <String, List<ReactionModel>>{};

  final tableName = key.isGroup
      ? 'kyorangtalk_group_message_reactions'
      : 'kyorangtalk_message_reactions';
  final messagesTable = key.isGroup
      ? 'kyorangtalk_group_messages'
      : 'kyorangtalk_messages';
  final channelName = key.isGroup
      ? 'reactions-group-${key.roomId}'
      : 'reactions-dm-${key.roomId}';

  void emit() {
    if (!controller.isClosed) {
      controller.add(Map.of(reactions));
    }
  }

  void addReaction(ReactionModel r) {
    final list = reactions.putIfAbsent(r.messageId, () => []);
    if (!list.any((x) => x.id == r.id)) {
      list.add(r);
      emit();
    }
  }

  void removeReaction(String messageId, String reactionId) {
    final list = reactions[messageId];
    if (list == null) return;
    final before = list.length;
    list.removeWhere((r) => r.id == reactionId);
    if (list.isEmpty) reactions.remove(messageId);
    if (list.length != before) emit();
  }

  // ─────────────────────────────────────────────
  // 1) 초기 fetch
  // ─────────────────────────────────────────────
  Future<void> fetchInitial() async {
    try {
      final messages = await _supabase
          .from(messagesTable)
          .select('id')
          .eq('room_id', key.roomId);

      final messageIds =
          (messages as List).map((m) => m['id'] as String).toList();

      if (messageIds.isEmpty) {
        emit();
        return;
      }

      final data = await _supabase
          .from(tableName)
          .select('*')
          .inFilter('message_id', messageIds);

      reactions.clear();
      for (final r in data) {
        final reaction = ReactionModel.fromJson(r);
        reactions
            .putIfAbsent(reaction.messageId, () => [])
            .add(reaction);
      }
      emit();
    } catch (e) {
      print('🔴 초기 반응 fetch 실패: $e');
      emit();
    }
  }

  fetchInitial();

  // ─────────────────────────────────────────────
  // 2) 옵티미스틱 버스 구독 (내 디바이스 즉시 반영)
  // ─────────────────────────────────────────────
  final localSub = _localReactionBus.stream.listen((evt) {
    if (evt.channelName != channelName) return;
    if (evt.isAdd && evt.reaction != null) {
      addReaction(evt.reaction!);
    } else if (!evt.isAdd &&
        evt.messageId != null &&
        evt.reactionId != null) {
      removeReaction(evt.messageId!, evt.reactionId!);
    }
  });

  // ─────────────────────────────────────────────
  // 3) Broadcast 구독 (다른 디바이스 변경 수신)
  // self는 옵티미스틱으로 처리하므로 false
  // ─────────────────────────────────────────────
  final channel = _supabase.channel(
    channelName,
    opts: const RealtimeChannelConfig(self: false),
  );

  channel
      .onBroadcast(
        event: 'reaction_added',
        callback: (payload) {
          try {
            final data = payload['reaction'] as Map<String, dynamic>?;
            if (data == null) return;
            addReaction(ReactionModel.fromJson(data));
          } catch (e) {
            print('🔴 reaction_added 처리 실패: $e');
          }
        },
      )
      .onBroadcast(
        event: 'reaction_removed',
        callback: (payload) {
          try {
            final messageId = payload['message_id'] as String?;
            final reactionId = payload['reaction_id'] as String?;
            if (messageId == null || reactionId == null) return;
            removeReaction(messageId, reactionId);
          } catch (e) {
            print('🔴 reaction_removed 처리 실패: $e');
          }
        },
      )
      .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _activeReactionChannels[channelName] = channel;
          print('🟢 반응 채널 구독 성공: $channelName');
        } else if (error != null) {
          print('🔴 반응 채널 오류 ($channelName): $error');
        }
      });

  ref.onDispose(() {
    localSub.cancel();
    _activeReactionChannels.remove(channelName);
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ═══════════════════════════════════════════════════
// 반응 토글 (옵티미스틱 → DB → Broadcast)
// ═══════════════════════════════════════════════════
Future<void> toggleReaction({
  required String messageId,
  required String roomId,
  required String emoji,
  required bool isGroup,
}) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return;

  final tableName = isGroup
      ? 'kyorangtalk_group_message_reactions'
      : 'kyorangtalk_message_reactions';
  final channelName = isGroup
      ? 'reactions-group-$roomId'
      : 'reactions-dm-$roomId';

  // 기존 반응 확인
  final existing = await _supabase
      .from(tableName)
      .select('id')
      .eq('message_id', messageId)
      .eq('user_id', user.id)
      .eq('emoji', emoji)
      .maybeSingle();

  if (existing != null) {
    // ─── 제거 ───
    final reactionId = existing['id'] as String;

    // 1) 옵티미스틱: 내 화면 즉시 반영
    _localReactionBus.add(
      _LocalReactionEvent.remove(channelName, messageId, reactionId),
    );

    // 2) DB 삭제
    try {
      await _supabase.from(tableName).delete().eq('id', reactionId);
    } catch (e) {
      print('🔴 반응 삭제 실패: $e');
      return;
    }

    // 3) 다른 디바이스에 broadcast (subscribe된 채널 재사용)
    final channel = _activeReactionChannels[channelName];
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'reaction_removed',
          payload: {
            'message_id': messageId,
            'reaction_id': reactionId,
          },
        );
      } catch (e) {
        print('🔴 reaction_removed broadcast 실패: $e');
      }
    } else {
      print('⚠️ 채널이 아직 subscribe 안 됐음 — broadcast 스킵');
    }
  } else {
    // ─── 추가 ───
    try {
      final inserted = await _supabase
          .from(tableName)
          .insert({
            'message_id': messageId,
            'user_id': user.id,
            'emoji': emoji,
          })
          .select()
          .single();

      final reaction = ReactionModel.fromJson(inserted);

      // 1) 옵티미스틱: 내 화면 즉시 반영
      _localReactionBus.add(
        _LocalReactionEvent.add(channelName, reaction),
      );

      // 2) 다른 디바이스에 broadcast
      final channel = _activeReactionChannels[channelName];
      if (channel != null) {
        try {
          await channel.sendBroadcastMessage(
            event: 'reaction_added',
            payload: {'reaction': reaction.toJson()},
          );
        } catch (e) {
          print('🔴 reaction_added broadcast 실패: $e');
        }
      } else {
        print('⚠️ 채널이 아직 subscribe 안 됐음 — broadcast 스킵');
      }
    } catch (e) {
      print('🔴 반응 추가 실패: $e');
    }
  }
}

// ═══════════════════════════════════════════════════
// Helper: 메시지의 반응을 emoji 단위로 그룹핑
// ═══════════════════════════════════════════════════
List<ReactionGroup> groupReactions(
    List<ReactionModel> reactions, String myUserId) {
  final map = <String, List<ReactionModel>>{};
  for (final r in reactions) {
    map.putIfAbsent(r.emoji, () => []).add(r);
  }

  final groups = map.entries.map((e) {
    final list = e.value;
    return ReactionGroup(
      emoji:       e.key,
      count:       list.length,
      reactedByMe: list.any((r) => r.userId == myUserId),
      userIds:     list.map((r) => r.userId).toList(),
    );
  }).toList();

  groups.sort((a, b) => b.count.compareTo(a.count));
  return groups;
}