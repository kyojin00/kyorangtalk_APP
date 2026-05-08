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
// 화면이 loadOlderMessages 호출 → 컨트롤러가 캐시에 추가 →
// StreamController에 새 리스트 emit
// ═══════════════════════════════════════════════
class _RoomMessageController {
  final String roomId;
  final StreamController<List<MessageModel>> stream;
  List<MessageModel> messages = [];
  bool hasMore = true;        // 더 가져올 메시지가 있는지
  bool isLoadingMore = false; // 중복 호출 방지

  _RoomMessageController(this.roomId, this.stream);

  void emit() {
    if (!stream.isClosed) {
      // 시간순 정렬 보장
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      stream.add(List.unmodifiable(messages));
    }
  }
}

// 방별 활성 컨트롤러 (provider 살아있는 동안 유지)
final Map<String, _RoomMessageController> _activeControllers = {};

// ── 채팅 목록 (실시간) ──
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

    final profiles = await _supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url')
        .inFilter('id', partnerIds);

    final profileMap = {
      for (final p in profiles) p['id'] as String: p
    };

    final subProfiles = await _supabase
        .from('kyorangtalk_sub_profiles')
        .select('''
          user_id, nickname, avatar_url,
          kyorangtalk_sub_profile_viewers!inner(viewer_id)
        ''')
        .inFilter('user_id', partnerIds)
        .eq('kyorangtalk_sub_profile_viewers.viewer_id', user.id);

    final subProfileMap = <String, Map<String, dynamic>>{};
    for (final sp in subProfiles) {
      subProfileMap[sp['user_id'] as String] = sp;
    }

    final unreadList = await _supabase
        .from('kyorangtalk_messages')
        .select('room_id')
        .inFilter('room_id',
            visibleRooms.map((r) => r['id'] as String).toList())
        .eq('is_read', false)
        .neq('sender_id', user.id);

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
      final subProf = subProfileMap[partnerId];

      final nickname = subProf != null
          ? (subProf['nickname'] as String? ?? mainProf?['nickname'] as String? ?? '알 수 없음')
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

  fetchRooms().then((data) {
    if (!controller.isClosed) controller.add(data);
  });

  final channel = _supabase
      .channel('chat_rooms_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_rooms',
        callback: (_) {
          fetchRooms().then((data) {
            if (!controller.isClosed) controller.add(data);
          });
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_rooms',
        callback: (_) {
          fetchRooms().then((data) {
            if (!controller.isClosed) controller.add(data);
          });
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_messages',
        callback: (_) {
          fetchRooms().then((data) {
            if (!controller.isClosed) controller.add(data);
          });
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_messages',
        callback: (_) {
          fetchRooms().then((data) {
            if (!controller.isClosed) controller.add(data);
          });
        },
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ═══════════════════════════════════════════════
// 메시지 목록 (페이지네이션 + 실시간)
// 처음에 최근 50개만 로드 → 위로 스크롤 시 loadOlderMessages 호출
// ═══════════════════════════════════════════════
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, roomId) {
  final user = _supabase.auth.currentUser!;
  final streamController = StreamController<List<MessageModel>>();

  // 컨트롤러 등록
  final ctrl = _RoomMessageController(roomId, streamController);
  _activeControllers[roomId] = ctrl;

  print('🔵 messagesProvider 시작: $roomId, currentOpenRoomId=$currentOpenRoomId');

  // ─────────────────────────────────────────
  // 1. 초기 로드: 최근 N개만
  // ─────────────────────────────────────────
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

  // ─────────────────────────────────────────
  // 2. 실시간 구독
  // ─────────────────────────────────────────
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
          final transcriptStatus = updated['audio_transcript_status'] as String?;
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
//
// Returns:
//   - true: 더 가져왔음 (UI에서 스크롤 위치 유지 등 처리)
//   - false: 더 이상 없음, 또는 이미 로드 중, 또는 컨트롤러 없음
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
    // 시간순 정렬되어 있으니 첫 메시지가 가장 오래된 것
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

    // 중복 제거 + 합치기
    final existingIds = ctrl.messages.map((m) => m.id).toSet();
    final newOnes = older.where((m) => !existingIds.contains(m.id)).toList();

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
// 메시지 전송 (⭐ imageUrls 파라미터 추가)
// ═══════════════════════════════════════════════
Future<void> sendMessage({
  required String myId,
  required String roomId,
  required String content,
  String? imageUrl,
  List<String>? imageUrls,             // ⭐ NEW: 다중 이미지
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
                                        'image_urls':       imageUrls,   // ⭐ NEW
    if (audioUrl != null)               'audio_url':        audioUrl,
    if (audioDuration != null)          'audio_duration':   audioDuration,
    if (replyToId != null)              'reply_to_id':      replyToId,
    if (replyToContent != null)         'reply_to_content': replyToContent,
    if (gameData != null)               'game_data':        gameData,
    if (pollId != null)                 'poll_id':          pollId,
    if (fileUrl != null)                'file_url':         fileUrl,
    if (fileName != null)               'file_name':        fileName,
    if (fileSize != null)               'file_size':        fileSize,
    if (fileType != null)               'file_type':        fileType,
  });

  // ⭐ 마지막 메시지 텍스트 (다중 이미지 케이스 추가)
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
    lastMessageText = '[사진 ${imageUrls.length}장]';   // ⭐ NEW
  } else if (imageUrl != null || (imageUrls != null && imageUrls.isNotEmpty)) {
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