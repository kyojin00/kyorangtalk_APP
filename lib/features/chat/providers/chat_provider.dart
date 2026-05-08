import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

final _supabase = Supabase.instance.client;

String? currentOpenRoomId;

// ═══════════════════════════════════════════════
// 페이지네이션 설정
// ═══════════════════════════════════════════════
const int kInitialMessageLimit = 50;  // 처음 로드할 메시지 수
const int kMoreMessageLimit = 50;     // "더 불러오기" 시 가져올 수

// ═══════════════════════════════════════════════
// 페이지네이션 컨트롤러 (방별로 메시지 캐시 + 갱신)
// ═══════════════════════════════════════════════
class _RoomMessageController {
  final String roomId;
  final StreamController<List<MessageModel>> stream;
  List<MessageModel> messages = [];
  bool hasMore = true;
  bool isLoadingMore = false;

  _RoomMessageController(this.roomId, this.stream);

  void emit() {
    if (!stream.isClosed) {
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      stream.add(List.unmodifiable(messages));
    }
  }
}

final Map<String, _RoomMessageController> _activeControllers = {};

// ═══════════════════════════════════════════════
// 채팅 목록 (실시간) ⭐ 최적화
// ═══════════════════════════════════════════════
final chatRoomsProvider = StreamProvider<List<ChatRoomModel>>((ref) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<List<ChatRoomModel>>();

  Future<List<ChatRoomModel>> fetchRooms() async {
    // 1) rooms 먼저 (partnerIds, roomIds를 알아야 다음 쿼리 가능)
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

    // 2) ⭐ 3개 쿼리 병렬 실행 (profiles, subProfiles, unread)
    final results = await Future.wait([
      _supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', partnerIds),
      _supabase
          .from('kyorangtalk_sub_profiles')
          .select('''
            user_id, nickname, avatar_url,
            kyorangtalk_sub_profile_viewers!inner(viewer_id)
          ''')
          .inFilter('user_id', partnerIds)
          .eq('kyorangtalk_sub_profile_viewers.viewer_id', user.id),
      _supabase
          .from('kyorangtalk_messages')
          .select('room_id')
          .inFilter('room_id', roomIds)
          .eq('is_read', false)
          .neq('sender_id', user.id),
    ]);

    final profiles    = results[0] as List;
    final subProfiles = results[1] as List;
    final unreadList  = results[2] as List;

    final profileMap = {
      for (final p in profiles) p['id'] as String: p
    };

    final subProfileMap = <String, Map<String, dynamic>>{};
    for (final sp in subProfiles) {
      subProfileMap[sp['user_id'] as String] =
          sp as Map<String, dynamic>;
    }

    final unreadMap = <String, int>{};
    for (final m in unreadList) {
      final rid = m['room_id'] as String;
      unreadMap[rid] = (unreadMap[rid] ?? 0) + 1;
    }

    return visibleRooms.map((r) {
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
      );
    }).toList();
  }

  // ⭐ debounce: 짧은 시간 내 여러 트리거를 한 번으로 합침
  Timer? refetchTimer;
  void scheduleRefetch() {
    refetchTimer?.cancel();
    refetchTimer = Timer(const Duration(milliseconds: 300), () {
      fetchRooms().then((data) {
        if (!controller.isClosed) controller.add(data);
      }).catchError((e) {
        print('🔴 chatRooms refetch 실패: $e');
      });
    });
  }

  // 초기 로드
  fetchRooms().then((data) {
    if (!controller.isClosed) controller.add(data);
  }).catchError((e) {
    print('🔴 chatRooms 초기 로드 실패: $e');
  });

  // ⭐ rooms 테이블만 구독
  // (sendMessage가 항상 rooms.last_message_at을 갱신하므로
  //  messages 구독 없이도 새 메시지 도착이 잡힘)
  final channel = _supabase
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

  ref.onDispose(() {
    refetchTimer?.cancel();
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ═══════════════════════════════════════════════
// 메시지 목록 (페이지네이션 + 실시간)
// ═══════════════════════════════════════════════
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, roomId) {
  final user = _supabase.auth.currentUser!;
  final streamController = StreamController<List<MessageModel>>();

  final ctrl = _RoomMessageController(roomId, streamController);
  _activeControllers[roomId] = ctrl;

  print('🔵 messagesProvider 시작: $roomId, currentOpenRoomId=$currentOpenRoomId');

  // 1. 초기 로드: 최근 N개만
  _supabase
      .from('kyorangtalk_messages')
      .select('*')
      .eq('room_id', roomId)
      .order('created_at', ascending: false)
      .limit(kInitialMessageLimit)
      .then((data) {
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
  });

  // 2. 실시간 구독 (room_id 필터로 해당 방 메시지만)
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
          final transcript = updated['audio_transcript'] as String?;
          final transcriptStatus =
              updated['audio_transcript_status'] as String?;
          if (id == null) return;
          ctrl.messages = ctrl.messages.map((m) {
            if (m.id == id) {
              return m.copyWith(
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
// 더 오래된 메시지 가져오기 (페이지네이션)
// ═══════════════════════════════════════════════
Future<bool> loadOlderMessages(String roomId) async {
  final ctrl = _activeControllers[roomId];
  if (ctrl == null) {
    print('🟡 [Pagination] 컨트롤러 없음: $roomId');
    return false;
  }
  if (!ctrl.hasMore) {
    print('🟡 [Pagination] 더 이상 없음: $roomId');
    return false;
  }
  if (ctrl.isLoadingMore) {
    print('🟡 [Pagination] 이미 로딩 중: $roomId');
    return false;
  }
  if (ctrl.messages.isEmpty) {
    print('🟡 [Pagination] 메시지 없음: $roomId');
    return false;
  }

  ctrl.isLoadingMore = true;
  try {
    final oldestTime = ctrl.messages.first.createdAt;
    print('🔵 [Pagination] 로드: roomId=$roomId, before=$oldestTime');

    final data = await _supabase
        .from('kyorangtalk_messages')
        .select('*')
        .eq('room_id', roomId)
        .lt('created_at', oldestTime.toIso8601String())
        .order('created_at', ascending: false)
        .limit(kMoreMessageLimit);

    final older = data.map((e) => MessageModel.fromJson(e)).toList();
    print('🟢 [Pagination] 로드 완료: ${older.length}개');

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

/// 더 로드할 메시지가 있는지 (UI 인디케이터용)
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
}) async {
  await _supabase.from('kyorangtalk_messages').insert({
    'room_id':    roomId,
    'sender_id':  myId,
    'content':    content.trim(),
    'is_read':    false,
    'is_deleted': false,
    if (imageUrl != null)               'image_url':        imageUrl,
    if (imageUrls != null && imageUrls.isNotEmpty)
                                        'image_urls':       imageUrls,
    if (audioUrl != null)               'audio_url':        audioUrl,
    if (audioDuration != null)          'audio_duration':   audioDuration,
    if (replyToId != null)               'reply_to_id':      replyToId,
    if (replyToContent != null)         'reply_to_content': replyToContent,
    if (gameData != null)               'game_data':        gameData,
    if (pollId != null)                 'poll_id':          pollId,
    if (fileUrl != null)                'file_url':         fileUrl,
    if (fileName != null)               'file_name':        fileName,
    if (fileSize != null)               'file_size':        fileSize,
    if (fileType != null)               'file_type':        fileType,
  });

  String lastMessageText;
  if (fileUrl != null) {
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

  await _supabase
      .from('kyorangtalk_rooms')
      .update({
        'last_message':    lastMessageText,
        'last_message_at': DateTime.now().toUtc().toIso8601String(),
        'hidden_by':       [],
      })
      .eq('id', roomId);
}

// ── 고정 메시지 ──
Future<void> setPinnedMessage(String roomId, String? message) async {
  await _supabase
      .from('kyorangtalk_rooms')
      .update({'pinned_message': message})
      .eq('id', roomId);
}

// ── 채팅방 숨기기 ──
Future<void> hideChatRoom(String roomId) async {
  final user = _supabase.auth.currentUser!;

  final room = await _supabase
      .from('kyorangtalk_rooms')
      .select('hidden_by')
      .eq('id', roomId)
      .single();

  final current = (room['hidden_by'] as List?)?.cast<String>() ?? [];
  if (!current.contains(user.id)) {
    current.add(user.id);
    await _supabase
        .from('kyorangtalk_rooms')
        .update({'hidden_by': current})
        .eq('id', roomId);
  }
}