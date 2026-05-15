import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

final _supabase = Supabase.instance.client;

String? currentOpenRoomId;

const int kInitialMessageLimit = 50;
const int kMoreMessageLimit = 50;

// 방별 hidden_at 캐시 (메시지 조회 시 필터링용)
final Map<String, DateTime?> _roomHiddenAtCache = {};

class _RoomMessageController {
  final String roomId;
  final StreamController<List<MessageModel>> stream;
  List<MessageModel> messages = [];
  bool hasMore = true;
  bool isLoadingMore = false;
  DateTime? hiddenAt;  // ⭐ 메시지 필터링 기준점

  _RoomMessageController(this.roomId, this.stream);

  void emit() {
    if (!stream.isClosed) {
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      stream.add(List.unmodifiable(messages));
    }
  }
}

final Map<String, _RoomMessageController> _activeControllers = {};

// ⭐ 방별 hidden_at 조회 (메시지 조회 전 호출)
Future<DateTime?> _getHiddenAt(String roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;

  try {
    final state = await _supabase
        .from('kyorangtalk_room_user_state')
        .select('hidden_at, cleared_at')
        .eq('user_id', user.id)
        .eq('room_id', roomId)
        .maybeSingle();

    if (state == null) return null;

    // cleared_at이 있으면 복원됨 → 필터 없음
    if (state['cleared_at'] != null) return null;

    final hiddenAtStr = state['hidden_at'] as String?;
    if (hiddenAtStr == null) return null;
    return DateTime.parse(hiddenAtStr);
  } catch (e) {
    print('🔴 hidden_at 조회 실패: $e');
    return null;
  }
}

// ═══════════════════════════════════════════════
// 채팅 목록 (실시간)
//
// ⭐ 성능 패치 (2026-05):
//   1) sub_profiles !inner join → RPC get_visible_sub_profiles
//   2) unread row 통째로 받기 → RPC get_unread_counts_for_rooms
//   3) scheduleRefetch debounce 300ms → 500ms
// ═══════════════════════════════════════════════
final chatRoomsProvider = StreamProvider<List<ChatRoomModel>>((ref) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<List<ChatRoomModel>>();

  Future<List<ChatRoomModel>> fetchRooms() async {
    final rooms = await _supabase
        .from('kyorangtalk_rooms')
        .select('*')
        .or('user1_id.eq.${user.id},user2_id.eq.${user.id}')
        .order('last_message_at', ascending: false);

    if (rooms.isEmpty) return [];

    final visibleRooms = rooms.where((r) {
      final hiddenBy = (r['hidden_by'] as List?) ?? [];
      return !hiddenBy.contains(user.id);
    }).toList();

    if (visibleRooms.isEmpty) return [];

    final partnerIds = visibleRooms.map((r) {
      return r['user1_id'] == user.id
          ? r['user2_id'] as String
          : r['user1_id'] as String;
    }).toList();

    final roomIds =
        visibleRooms.map((r) => r['id'] as String).toList();

    final results = await Future.wait([
      _supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', partnerIds),
      _supabase.rpc('get_visible_sub_profiles', params: {
        'p_viewer_id': user.id,
        'p_user_ids': partnerIds,
      }),
      _supabase.rpc('get_unread_counts_for_rooms', params: {
        'p_user_id': user.id,
        'p_room_ids': roomIds,
      }),
      _supabase
          .from('kyorangtalk_room_user_state')
          .select('room_id, hidden_at, cleared_at')
          .eq('user_id', user.id)
          .inFilter('room_id', roomIds),
    ]);

    final profiles    = results[0] as List;
    final subProfiles = results[1] as List;
    final unreadList  = results[2] as List;
    final stateList   = results[3] as List;

    final profileMap = {
      for (final p in profiles) p['id'] as String: p
    };

    final subProfileMap = <String, Map<String, dynamic>>{};
    for (final sp in subProfiles) {
      subProfileMap[sp['user_id'] as String] =
          sp as Map<String, dynamic>;
    }

    final hiddenAtMap = <String, DateTime>{};
    for (final s in stateList) {
      if (s['cleared_at'] != null) continue;
      final rid = s['room_id'] as String;
      final hiddenAtStr = s['hidden_at'] as String?;
      if (hiddenAtStr != null) {
        hiddenAtMap[rid] = DateTime.parse(hiddenAtStr);
      }
    }
    _roomHiddenAtCache.clear();
    for (final entry in hiddenAtMap.entries) {
      _roomHiddenAtCache[entry.key] = entry.value;
    }

    final unreadMap = <String, int>{};
    for (final m in unreadList) {
      final rid = m['room_id'] as String;
      final count = (m['unread_count'] as num).toInt();
      unreadMap[rid] = count;
    }

    final list = visibleRooms.map((r) {
      final partnerId = r['user1_id'] == user.id
          ? r['user2_id'] as String
          : r['user1_id'] as String;
      final mainProf = profileMap[partnerId];
      final subProf  = subProfileMap[partnerId];

      final nickname = subProf != null
          ? (subProf['nickname'] as String? ??
              mainProf?['nickname'] as String? ??
              '알 수 없음')
          : (mainProf?['nickname'] as String? ?? '알 수 없음');

      final avatarUrl = subProf != null
          ? subProf['avatar_url'] as String?
          : mainProf?['avatar_url'] as String?;

      final pinnedBy = (r['pinned_by'] as List?) ?? [];
      final isPinned = pinnedBy.contains(user.id);

      return ChatRoomModel(
        partnerId:       partnerId,
        partnerUsername: nickname,
        partnerName:     nickname,
        partnerAvatar:   avatarUrl,
        lastMessage:     r['last_message'] as String? ?? '',
        lastTime:        DateTime.parse(
            r['last_message_at'] as String? ??
                r['created_at'] as String),
        unreadCount:     unreadMap[r['id']] ?? 0,
        isSent:          false,
        roomId:          r['id'] as String,
        pinnedMessage:   r['pinned_message'] as String?,
        isPinned:        isPinned,
      );
    }).toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastTime.compareTo(a.lastTime);
    });

    return list;
  }

  Timer? refetchTimer;
  void scheduleRefetch() {
    refetchTimer?.cancel();
    refetchTimer = Timer(const Duration(milliseconds: 500), () {
      fetchRooms().then((data) {
        if (!controller.isClosed) controller.add(data);
      }).catchError((e) {
        print('🔴 chatRooms refetch 실패: $e');
      });
    });
  }

  fetchRooms().then((data) {
    if (!controller.isClosed) controller.add(data);
  }).catchError((e) {
    print('🔴 chatRooms 초기 로드 실패: $e');
  });

  final roomsChannel = _supabase
      .channel('chat_rooms_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_rooms',
        callback: (_) => scheduleRefetch(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_rooms',
        callback: (_) => scheduleRefetch(),
      )
      .subscribe();

  final messagesChannel = _supabase
      .channel('chat_rooms_messages_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_messages',
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final senderId = row['sender_id'] as String?;
          if (senderId == user.id) return;
          scheduleRefetch();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_messages',
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final senderId = row['sender_id'] as String?;
          final isRead = row['is_read'] as bool? ?? false;
          if (senderId == user.id) return;
          if (!isRead) return;
          scheduleRefetch();
        },
      )
      .subscribe();

  final stateChannel = _supabase
      .channel('chat_rooms_state_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_room_user_state',
        callback: (_) => scheduleRefetch(),
      )
      .subscribe();

  ref.onDispose(() {
    refetchTimer?.cancel();
    _supabase.removeChannel(roomsChannel);
    _supabase.removeChannel(messagesChannel);
    _supabase.removeChannel(stateChannel);
    controller.close();
  });

  return controller.stream;
});

// ═══════════════════════════════════════════════
// 메시지 목록 (페이지네이션 + 실시간)
// ⭐ hidden_at 이후 메시지만 표시
// ═══════════════════════════════════════════════
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, roomId) {
  final user = _supabase.auth.currentUser!;
  final streamController = StreamController<List<MessageModel>>();

  final ctrl = _RoomMessageController(roomId, streamController);
  _activeControllers[roomId] = ctrl;

  () async {
    final hiddenAt = await _getHiddenAt(roomId);
    ctrl.hiddenAt = hiddenAt;

    var query = _supabase
        .from('kyorangtalk_messages')
        .select('*')
        .eq('room_id', roomId);

    if (hiddenAt != null) {
      query = query.gte('created_at', hiddenAt.toIso8601String());
    }

    final data = await query
        .order('created_at', ascending: false)
        .limit(kInitialMessageLimit);

    final initial = data.map((e) => MessageModel.fromJson(e)).toList();
    ctrl.messages = initial;
    ctrl.hasMore = initial.length >= kInitialMessageLimit;
    ctrl.emit();

    if (currentOpenRoomId == roomId) {
      _supabase
          .from('kyorangtalk_messages')
          .update({'is_read': true})
          .eq('room_id', roomId)
          .neq('sender_id', user.id)
          .eq('is_read', false)
          .then((_) {});
    }
  }();

  final channel = _supabase
      .channel('messages_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) {
          final newRow = payload.newRecord;
          if (newRow.isEmpty) return;
          final msg = MessageModel.fromJson(newRow);
          if (ctrl.hiddenAt != null &&
              msg.createdAt.isBefore(ctrl.hiddenAt!)) {
            return;
          }
          if (!ctrl.messages.any((m) => m.id == msg.id)) {
            ctrl.messages = [...ctrl.messages, msg];
            ctrl.emit();
          }
          if (msg.senderId != user.id &&
              currentOpenRoomId == roomId) {
            _supabase
                .from('kyorangtalk_messages')
                .update({'is_read': true})
                .eq('id', msg.id)
                .then((_) {});
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) {
          final updated = payload.newRecord;
          if (updated.isEmpty) return;
          final id = updated['id'] as String?;
          final isRead = updated['is_read'] as bool? ?? false;
          final isDeleted = updated['is_deleted'] as bool? ?? false;
          final content = updated['content'] as String?;      // ⭐ NEW
          final transcript = updated['audio_transcript'] as String?;
          final transcriptStatus =
              updated['audio_transcript_status'] as String?;
          if (id == null) return;
          ctrl.messages = ctrl.messages.map((m) {
            if (m.id == id) {
              return m.copyWith(
                content: content,                              // ⭐ NEW
                isRead: isRead,
                isDeleted: isDeleted,
                audioTranscript: transcript,
                audioTranscriptStatus: transcriptStatus,
              );
            }
            return m;
          }).toList();
          ctrl.emit();
        },
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    streamController.close();
    _activeControllers.remove(roomId);
  });

  return streamController.stream;
});

// ═══════════════════════════════════════════════
// 더 오래된 메시지 가져오기
// ═══════════════════════════════════════════════
Future<bool> loadOlderMessages(String roomId) async {
  final ctrl = _activeControllers[roomId];
  if (ctrl == null) return false;
  if (!ctrl.hasMore) return false;
  if (ctrl.isLoadingMore) return false;
  if (ctrl.messages.isEmpty) return false;

  ctrl.isLoadingMore = true;
  try {
    final oldestTime = ctrl.messages.first.createdAt;

    var query = _supabase
        .from('kyorangtalk_messages')
        .select('*')
        .eq('room_id', roomId)
        .lt('created_at', oldestTime.toIso8601String());

    if (ctrl.hiddenAt != null) {
      query = query.gte('created_at', ctrl.hiddenAt!.toIso8601String());
    }

    final data = await query
        .order('created_at', ascending: false)
        .limit(kMoreMessageLimit);

    final older = data.map((e) => MessageModel.fromJson(e)).toList();

    if (older.isEmpty) {
      ctrl.hasMore = false;
      return false;
    }

    final existingIds = ctrl.messages.map((m) => m.id).toSet();
    final newOnes =
        older.where((m) => !existingIds.contains(m.id)).toList();

    ctrl.messages = [...newOnes, ...ctrl.messages];
    ctrl.hasMore = older.length >= kMoreMessageLimit;
    ctrl.emit();
    return true;
  } catch (e) {
    print('🔴 [Pagination] 실패: $e');
    return false;
  } finally {
    ctrl.isLoadingMore = false;
  }
}

bool hasMoreMessages(String roomId) {
  return _activeControllers[roomId]?.hasMore ?? false;
}

// ═══════════════════════════════════════════════
// 메시지 전송
// ═══════════════════════════════════════════════
Future<void> sendMessage({
  required String myId,
  required String roomId,
  required String content,
  String? imageUrl,
  List<String>? imageUrls,
  String? audioUrl,
  int? audioDuration,
  String? replyToId,
  String? replyToContent,
  Map<String, dynamic>? gameData,
  String? pollId,
  String? fileUrl,
  String? fileName,
  int? fileSize,
  String? fileType,
  String? locationShareId,            // 📍
  String? scheduleEventId,            // 📅
}) async {
  await _supabase.from('kyorangtalk_messages').insert({
    'room_id':    roomId,
    'sender_id':  myId,
    'content':    content.trim(),
    'is_read':    false,
    'is_deleted': false,
    if (imageUrl != null)               'image_url':         imageUrl,
    if (imageUrls != null && imageUrls.isNotEmpty)
                                        'image_urls':        imageUrls,
    if (audioUrl != null)               'audio_url':         audioUrl,
    if (audioDuration != null)          'audio_duration':    audioDuration,
    if (replyToId != null)              'reply_to_id':       replyToId,
    if (replyToContent != null)         'reply_to_content':  replyToContent,
    if (gameData != null)               'game_data':         gameData,
    if (pollId != null)                 'poll_id':           pollId,
    if (fileUrl != null)                'file_url':          fileUrl,
    if (fileName != null)               'file_name':         fileName,
    if (fileSize != null)               'file_size':         fileSize,
    if (fileType != null)               'file_type':         fileType,
    if (locationShareId != null)        'location_share_id': locationShareId,   // 📍
    if (scheduleEventId != null)        'schedule_event_id': scheduleEventId,   // 📅
  });

  String lastMessageText;
  if (scheduleEventId != null) {
    lastMessageText = '📅 일정을 잡고 있어요';
  } else if (locationShareId != null) {
    lastMessageText = '📍 실시간 위치를 공유했어요';
  } else if (fileUrl != null) {
    lastMessageText = '📎 ${fileName ?? "파일"}';
  } else if (pollId != null) {
    lastMessageText = '📊 ${content.trim().isEmpty ? "투표" : content.trim()}';
  } else if (gameData != null) {
    lastMessageText = content.trim();
  } else if (audioUrl != null) {
    lastMessageText = '[음성 메시지]';
  } else if (imageUrls != null && imageUrls.length >= 2) {
    lastMessageText = '[사진 ${imageUrls.length}장]';
  } else if (imageUrl != null ||
      (imageUrls != null && imageUrls.isNotEmpty)) {
    lastMessageText = '[이미지]';
  } else {
    lastMessageText = content.trim();
  }

  _supabase
    .rpc('kyorangtalk_update_room_on_message', params: {
      'p_room_id': roomId,
      'p_last_message': lastMessageText,
    })
    .then((_) {})
    .catchError((e) {
  print('🔴 rooms 업데이트 실패: $e');
});
}

// ── 고정 메시지 ──
Future<void> setPinnedMessage(String roomId, String? message) async {
  await _supabase
      .from('kyorangtalk_rooms')
      .update({'pinned_message': message})
      .eq('id', roomId);
}

// ── 채팅방 나가기 ──
Future<void> hideChatRoom(String roomId) async {
  try {
    await _supabase.rpc(
      'kyorangtalk_leave_room',
      params: {'p_room_id': roomId},
    );
  } catch (e) {
    print('🔴 채팅방 나가기 실패: $e');
    rethrow;
  }
}

// ── 복원 ──
Future<void> restoreChatRoom(String roomId) async {
  try {
    await _supabase.rpc(
      'kyorangtalk_restore_room',
      params: {'p_room_id': roomId},
    );
  } catch (e) {
    print('🔴 채팅방 복원 실패: $e');
    rethrow;
  }
}

// ── 핀 토글 ──
Future<bool> togglePinRoom(String roomId) async {
  try {
    final result = await _supabase.rpc(
      'kyorangtalk_toggle_pin',
      params: {'p_room_id': roomId},
    );
    return result as bool;
  } catch (e) {
    print('🔴 핀 토글 실패: $e');
    rethrow;
  }
}