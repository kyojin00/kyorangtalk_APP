import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room_model.dart';
import '../models/message_model.dart';

final _supabase = Supabase.instance.client;

String? currentOpenRoomId;

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

// ── 메시지 목록 (실시간) ──
final messagesProvider =
    StreamProvider.autoDispose.family<List<MessageModel>, String>((ref, roomId) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<List<MessageModel>>();
  List<MessageModel> messages = [];

  print('🔵 messagesProvider 시작: $roomId, currentOpenRoomId=$currentOpenRoomId');

  _supabase
      .from('kyorangtalk_messages')
      .select('*')
      .eq('room_id', roomId)
      .order('created_at', ascending: true)
      .then((data) {
    messages = data.map((e) => MessageModel.fromJson(e)).toList();
    if (!controller.isClosed) controller.add(messages);

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
          if (!messages.any((m) => m.id == msg.id)) {
            messages = [...messages, msg];
            if (!controller.isClosed) controller.add(messages);
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
          final id        = updated['id'] as String?;
          final isRead    = updated['is_read'] as bool? ?? false;
          final isDeleted = updated['is_deleted'] as bool? ?? false;
          if (id == null) return;
          messages = messages.map((m) {
            if (m.id == id) {
              return m.copyWith(
                  isRead: isRead, isDeleted: isDeleted);
            }
            return m;
          }).toList();
          if (!controller.isClosed) controller.add(messages);
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
// ── 메시지 전송 (게임 + 투표 + 파일 지원!) ──
// ═══════════════════════════════════════════════
Future<void> sendMessage({
  required String myId,
  required String roomId,
  required String content,
  String? imageUrl,
  String? audioUrl,
  int? audioDuration,
  String? replyToId,
  String? replyToContent,
  Map<String, dynamic>? gameData,  // 🎮
  String? pollId,                  // 📊
  // 📎 파일
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
    if (imageUrl != null)       'image_url':        imageUrl,
    if (audioUrl != null)       'audio_url':        audioUrl,
    if (audioDuration != null)  'audio_duration':   audioDuration,
    if (replyToId != null)      'reply_to_id':      replyToId,
    if (replyToContent != null) 'reply_to_content': replyToContent,
    if (gameData != null)       'game_data':        gameData,
    if (pollId != null)         'poll_id':          pollId,
    // 📎 파일
    if (fileUrl != null)        'file_url':         fileUrl,
    if (fileName != null)       'file_name':        fileName,
    if (fileSize != null)       'file_size':        fileSize,
    if (fileType != null)       'file_type':        fileType,
  });

  // 마지막 메시지 표시
  String lastMessageText;
  if (fileUrl != null) {
    lastMessageText = '📎 ${fileName ?? "파일"}';
  } else if (pollId != null) {
    lastMessageText = '📊 ${content.trim().isEmpty ? "투표" : content.trim()}';
  } else if (gameData != null) {
    lastMessageText = content.trim();
  } else if (audioUrl != null) {
    lastMessageText = '[음성 메시지]';
  } else if (imageUrl != null) {
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