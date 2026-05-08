import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/group_room_model.dart';
import '../models/group_message_model.dart';

final _supabase = Supabase.instance.client;

String? currentOpenGroupRoomId;

// ═══════════════════════════════════════════════
// 페이지네이션 설정
// ═══════════════════════════════════════════════
const int kInitialGroupMessageLimit = 50;
const int kMoreGroupMessageLimit = 50;

// ═══════════════════════════════════════════════
// 페이지네이션 컨트롤러 (그룹용)
// ═══════════════════════════════════════════════
class _GroupRoomMessageController {
  final String roomId;
  final StreamController<List<GroupMessageModel>> stream;
  List<GroupMessageModel> messages = [];
  bool hasMore = true;
  bool isLoadingMore = false;
  DateTime? joinedAt;

  _GroupRoomMessageController(this.roomId, this.stream);

  void emit() {
    if (!stream.isClosed) {
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      stream.add(List.unmodifiable(messages));
    }
  }
}

final Map<String, _GroupRoomMessageController> _activeGroupControllers = {};

// ═══════════════════════════════════════════════
// 내가 참여한 그룹/오픈 채팅 목록 (실시간) — 변경 없음
// ═══════════════════════════════════════════════
final groupRoomsProvider = StreamProvider<List<GroupRoomModel>>((ref) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<List<GroupRoomModel>>();

  Future<List<GroupRoomModel>> fetchRooms() async {
    try {
      final members = await _supabase
          .from('kyorangtalk_group_members')
          .select('room_id, role, joined_at')
          .eq('user_id', user.id);

      if (members.isEmpty) return [];

      final roomIds =
          members.map((m) => m['room_id'] as String).toList();
      final roleMap = {
        for (final m in members)
          m['room_id'] as String: m['role'] as String
      };
      final joinedAtMap = {
        for (final m in members)
          m['room_id'] as String: m['joined_at'] as String
      };

      final rooms = await _supabase
          .from('kyorangtalk_group_rooms')
          .select('*')
          .inFilter('id', roomIds)
          .order('last_message_at', ascending: false);

      final reads = await _supabase
          .from('kyorangtalk_group_reads')
          .select('room_id, last_read_at')
          .eq('user_id', user.id)
          .inFilter('room_id', roomIds);

      final readMap = <String, DateTime>{};
      for (final r in reads) {
        readMap[r['room_id'] as String] =
            DateTime.parse(r['last_read_at'] as String).toLocal();
      }

      final unreadCounts = <String, int>{};
      for (final roomId in roomIds) {
        final lastRead = readMap[roomId];
        final joinedAt = joinedAtMap[roomId];

        final joinTime = DateTime.parse(joinedAt!).toUtc();
        final sinceTime = lastRead != null
            ? (joinTime.isAfter(lastRead.toUtc()) ? joinTime : lastRead.toUtc())
            : joinTime;

        final result = await _supabase
            .from('kyorangtalk_group_messages')
            .select('id')
            .eq('room_id', roomId)
            .neq('sender_id', user.id)
            .gt('created_at', sinceTime.toIso8601String());

        unreadCounts[roomId] = result.length;
      }

      return rooms.map((r) {
        final roomId = r['id'] as String;
        final joinedAt = joinedAtMap[roomId];
        final roomType = r['room_type'] as String? ?? 'group';

        String? lastMessage = r['last_message'] as String?;
        DateTime? lastMessageAt = r['last_message_at'] != null
            ? DateTime.parse(r['last_message_at'] as String).toLocal()
            : null;

        if (joinedAt != null && lastMessageAt != null) {
          final joinTime = DateTime.parse(joinedAt).toLocal();
          if (lastMessageAt.isBefore(joinTime)) {
            lastMessage = null;
            lastMessageAt = joinTime;
          }
        }

        final tagsRaw = r['tags'] as List<dynamic>?;
        final tags = tagsRaw?.map((t) => t as String).toList() ?? [];

        return GroupRoomModel(
          id:            roomId,
          name:          r['name'] as String,
          description:   r['description'] as String?,
          avatarUrl:     r['avatar_url'] as String?,
          createdBy:     r['created_by'] as String,
          inviteCode:    r['invite_code'] as String? ?? '',
          memberCount:   r['member_count'] as int? ?? 0,
          roomType:      roomType,
          lastMessage:   lastMessage,
          lastMessageAt: lastMessageAt,
          category:      r['category'] as String? ?? '일반',
          createdAt:     r['created_at'] as String,
          myRole:        roleMap[roomId] ?? 'member',
          unreadCount:   unreadCounts[roomId] ?? 0,
          likeCount:     r['like_count'] as int? ?? 0,
          tags:          tags,
          // ⭐ NEW: 비번 보호 여부 (해시 자체는 노출 X, bool로만)
          hasPassword:   r['password_hash'] != null,
        );
      }).toList();
    } catch (e, stack) {
      print('❌ fetchRooms 실패: $e');
      print('❌ Stack: $stack');
      return [];
    }
  }

  fetchRooms().then((data) {
    print('✅ 초기 fetchRooms 완료: ${data.length}개 방');
    if (!controller.isClosed) controller.add(data);
  });

  Timer? refetchTimer;
  void scheduleRefetch(String reason) {
    print('🔄 [Provider] $reason → refetch 예약');
    refetchTimer?.cancel();
    refetchTimer = Timer(const Duration(milliseconds: 300), () {
      fetchRooms().then((data) {
        print('✅ [Provider] refetch 완료: ${data.length}개');
        if (!controller.isClosed) controller.add(data);
      });
    });
  }

  final roomsChannel = _supabase
      .channel('provider_rooms_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_group_rooms',
        callback: (_) => scheduleRefetch('rooms UPDATE'),
      )
      .subscribe((status, err) {
        print('📡 [Provider rooms]: $status${err != null ? " ❌$err" : ""}');
      });

  final membersChannel = _supabase
      .channel('provider_members_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (_) => scheduleRefetch('members INSERT'),
      )
      .subscribe((status, err) {
        print('📡 [Provider members]: $status');
      });

  final messagesChannel = _supabase
      .channel('provider_messages_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_group_messages',
        callback: (_) => scheduleRefetch('messages INSERT'),
      )
      .subscribe((status, err) {
        print('📡 [Provider messages]: $status${err != null ? " ❌$err" : ""}');
      });

  final readsChannel = _supabase
      .channel('provider_reads_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_group_reads',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (_) => scheduleRefetch('reads 변경'),
      )
      .subscribe((status, err) {
        print('📡 [Provider reads]: $status');
      });

  ref.onDispose(() {
    refetchTimer?.cancel();
    _supabase.removeChannel(roomsChannel);
    _supabase.removeChannel(membersChannel);
    _supabase.removeChannel(messagesChannel);
    _supabase.removeChannel(readsChannel);
    controller.close();
  });

  return controller.stream;
});

// ═══════════════════════════════════════════════
// 오픈 채팅 목록
// ═══════════════════════════════════════════════
final openRoomsProvider =
    FutureProvider<List<GroupRoomModel>>((ref) async {
  final rooms = await _supabase
      .from('kyorangtalk_group_rooms')
      .select('*')
      .eq('room_type', 'open')
      .order('like_count', ascending: false);

  return rooms.map((r) {
    final tagsRaw = r['tags'] as List<dynamic>?;
    final tags = tagsRaw?.map((t) => t as String).toList() ?? [];

    return GroupRoomModel(
      id:            r['id'] as String,
      name:          r['name'] as String,
      description:   r['description'] as String?,
      avatarUrl:     r['avatar_url'] as String?,
      createdBy:     r['created_by'] as String,
      inviteCode:    r['invite_code'] as String? ?? '',
      memberCount:   r['member_count'] as int? ?? 0,
      roomType:      r['room_type'] as String? ?? 'open',
      lastMessage:   r['last_message'] as String?,
      lastMessageAt: r['last_message_at'] != null
          ? DateTime.parse(r['last_message_at'] as String).toLocal()
          : null,
      category:      r['category'] as String? ?? '일반',
      createdAt:     r['created_at'] as String,
      myRole:        'member',
      likeCount:     r['like_count'] as int? ?? 0,
      tags:          tags,
      hasPassword:   r['password_hash'] != null,                    // ⭐ NEW
    );
  }).toList();
});

// ═══════════════════════════════════════════════
// 방 상세 정보
// ═══════════════════════════════════════════════
final roomDetailProvider =
    StreamProvider.family.autoDispose<GroupRoomModel?, String>((ref, roomId) {
  final controller = StreamController<GroupRoomModel?>();

  Future<void> fetch() async {
    final r = await _supabase
        .from('kyorangtalk_group_rooms')
        .select('*')
        .eq('id', roomId)
        .maybeSingle();

    if (r == null) {
      if (!controller.isClosed) controller.add(null);
      return;
    }

    final tagsRaw = r['tags'] as List<dynamic>?;
    final tags = tagsRaw?.map((t) => t as String).toList() ?? [];

    final room = GroupRoomModel(
      id:            r['id'] as String,
      name:          r['name'] as String,
      description:   r['description'] as String?,
      avatarUrl:     r['avatar_url'] as String?,
      createdBy:     r['created_by'] as String,
      inviteCode:    r['invite_code'] as String? ?? '',
      memberCount:   r['member_count'] as int? ?? 0,
      roomType:      r['room_type'] as String? ?? 'open',
      lastMessage:   r['last_message'] as String?,
      lastMessageAt: r['last_message_at'] != null
          ? DateTime.parse(r['last_message_at'] as String).toLocal()
          : null,
      category:      r['category'] as String? ?? '일반',
      createdAt:     r['created_at'] as String,
      myRole:        'member',
      likeCount:     r['like_count'] as int? ?? 0,
      tags:          tags,
      hasPassword:   r['password_hash'] != null,                    // ⭐ NEW
    );

    if (!controller.isClosed) controller.add(room);
  }

  fetch();

  final channel = _supabase
      .channel('room_detail_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_group_rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: roomId,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

final hasRoomAdminProvider =
    StreamProvider.family.autoDispose<bool, String>((ref, roomId) {
  final controller = StreamController<bool>();

  Future<void> check() async {
    final data = await _supabase
        .from('kyorangtalk_group_members')
        .select('id')
        .eq('room_id', roomId)
        .eq('role', 'admin')
        .limit(1);

    if (!controller.isClosed) controller.add(data.isNotEmpty);
  }

  check();

  final channel = _supabase
      .channel('room_admin_check_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (_) => check(),
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

final isRoomMemberProvider =
    StreamProvider.family.autoDispose<bool, String>((ref, roomId) {
  final user = _supabase.auth.currentUser;
  if (user == null) return Stream.value(false);

  final controller = StreamController<bool>();

  Future<void> check() async {
    final data = await _supabase
        .from('kyorangtalk_group_members')
        .select('id')
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (!controller.isClosed) controller.add(data != null);
  }

  check();

  final channel = _supabase
      .channel('room_membership_${roomId}_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (_) => check(),
      )
      .subscribe();

  ref.onDispose(() {
    _supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

final isLikedProvider =
    FutureProvider.family.autoDispose<bool, String>((ref, roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return false;

  final result = await _supabase
      .from('kyorangtalk_group_likes')
      .select('id')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  return result != null;
});

Future<bool> toggleRoomLike(String roomId) async {
  final user = _supabase.auth.currentUser!;

  final existing = await _supabase
      .from('kyorangtalk_group_likes')
      .select('id')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  if (existing != null) {
    await _supabase
        .from('kyorangtalk_group_likes')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', user.id);
    return false;
  } else {
    await _supabase.from('kyorangtalk_group_likes').insert({
      'room_id': roomId,
      'user_id': user.id,
    });
    return true;
  }
}

Future<String?> getMySubProfileInRoom(String roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;

  final data = await _supabase
      .from('kyorangtalk_group_members')
      .select('sub_profile_id')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  return data?['sub_profile_id'] as String?;
}

Future<bool> checkIsRoomMember(String roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return false;

  final data = await _supabase
      .from('kyorangtalk_group_members')
      .select('id')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  return data != null;
}

Future<bool> checkHasRoomAdmin(String roomId) async {
  final data = await _supabase
      .from('kyorangtalk_group_members')
      .select('id')
      .eq('role', 'admin')
      .eq('room_id', roomId)
      .limit(1);

  return data.isNotEmpty;
}

// ═══════════════════════════════════════════════
// 그룹 메시지 목록 (페이지네이션 + 실시간)
// ═══════════════════════════════════════════════
final groupMessagesProvider =
    StreamProvider.family.autoDispose<List<GroupMessageModel>, String>(
        (ref, roomId) {
  final streamController = StreamController<List<GroupMessageModel>>();
  final ctrl = _GroupRoomMessageController(roomId, streamController);
  _activeGroupControllers[roomId] = ctrl;

  _loadInitialGroupMessages(roomId, kInitialGroupMessageLimit).then((result) {
    ctrl.messages = result.messages;
    ctrl.joinedAt = result.joinedAt;
    ctrl.hasMore = result.hasMore;
    ctrl.emit();
  });

  final channel = _supabase
      .channel('group_messages_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) async {
          final newRow = payload.newRecord;
          if (newRow.isEmpty) return;

          final subProfileId = newRow['sub_profile_id'] as String?;
          Map<String, dynamic>? displayInfo;

          if (subProfileId != null) {
            final sub = await _supabase
                .from('kyorangtalk_sub_profiles')
                .select('name, nickname, avatar_url')
                .eq('id', subProfileId)
                .maybeSingle();

            if (sub != null) {
              final subNick = sub['nickname'] as String?;
              final subName = sub['name'] as String?;
              displayInfo = {
                'nickname': (subNick?.isNotEmpty == true ? subNick : subName),
                'avatar_url': sub['avatar_url'],
              };
            }
          }

          if (displayInfo == null) {
            final profile = await _supabase
                .from('kyorangtalk_profiles')
                .select('nickname, avatar_url')
                .eq('id', newRow['sender_id'])
                .maybeSingle();

            displayInfo = {
              'nickname': profile?['nickname'],
              'avatar_url': profile?['avatar_url'],
            };
          }

          final msg = GroupMessageModel.fromJson({
            ...newRow,
            'sender_nickname': displayInfo['nickname'],
            'sender_avatar':   displayInfo['avatar_url'],
          });

          if (!ctrl.messages.any((m) => m.id == msg.id)) {
            ctrl.messages = [...ctrl.messages, msg];
            ctrl.emit();
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) {
          final updated = payload.newRecord;
          if (updated.isEmpty) return;
          final id = updated['id'] as String?;
          final isDeleted = updated['is_deleted'] as bool? ?? false;
          final transcript = updated['audio_transcript'] as String?;
          final transcriptStatus = updated['audio_transcript_status'] as String?;
          if (id == null) return;
          ctrl.messages = ctrl.messages.map((m) {
            if (m.id == id) {
              return GroupMessageModel(
                id:                    m.id,
                roomId:                m.roomId,
                senderId:              m.senderId,
                content:               updated['content'] as String? ?? m.content,
                msgType:               m.msgType,
                imageUrl:              m.imageUrl,
                imageUrls:             m.imageUrls,
                replyToId:             m.replyToId,
                replyToContent:        m.replyToContent,
                isDeleted:             isDeleted,
                createdAt:             m.createdAt,
                senderNickname:        m.senderNickname,
                senderAvatar:          m.senderAvatar,
                audioUrl:              m.audioUrl,
                audioDuration:         m.audioDuration,
                audioTranscript:       transcript ?? m.audioTranscript,
                audioTranscriptStatus: transcriptStatus ?? m.audioTranscriptStatus,
                gameData:              m.gameData,
                pollId:                m.pollId,
                fileUrl:               m.fileUrl,
                fileName:              m.fileName,
                fileSize:              m.fileSize,
                fileType:              m.fileType,
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
    _activeGroupControllers.remove(roomId);
  });

  return streamController.stream;
});

class _InitialLoadResult {
  final List<GroupMessageModel> messages;
  final DateTime? joinedAt;
  final bool hasMore;
  _InitialLoadResult(this.messages, this.joinedAt, this.hasMore);
}

Future<_InitialLoadResult> _loadInitialGroupMessages(
    String roomId, int limit) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return _InitialLoadResult([], null, false);

  final myMember = await _supabase
      .from('kyorangtalk_group_members')
      .select('joined_at')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  DateTime? joinedAt;
  if (myMember != null) {
    joinedAt = DateTime.parse(myMember['joined_at'] as String);
  }

  var query = _supabase
      .from('kyorangtalk_group_messages')
      .select('*')
      .eq('room_id', roomId);

  if (joinedAt != null) {
    query = query.gte('created_at', joinedAt.toIso8601String());
  }

  final msgs = await query
      .order('created_at', ascending: false)
      .limit(limit);

  if (msgs.isEmpty) return _InitialLoadResult([], joinedAt, false);

  final hasMore = msgs.length >= limit;
  final enriched = await _enrichMessages(msgs);

  return _InitialLoadResult(enriched, joinedAt, hasMore);
}

Future<List<GroupMessageModel>> _enrichMessages(
    List<Map<String, dynamic>> msgs) async {
  if (msgs.isEmpty) return [];

  final subProfileIds = msgs
      .where((m) => m['sub_profile_id'] != null)
      .map((m) => m['sub_profile_id'] as String)
      .toSet()
      .toList();

  Map<String, Map<String, dynamic>> subProfileMap = {};
  if (subProfileIds.isNotEmpty) {
    final subProfiles = await _supabase
        .from('kyorangtalk_sub_profiles')
        .select('id, name, nickname, avatar_url')
        .inFilter('id', subProfileIds);

    subProfileMap = {
      for (final p in subProfiles) p['id'] as String: p
    };
  }

  final senderIds =
      msgs.map((m) => m['sender_id'] as String).toSet().toList();
  final profiles = await _supabase
      .from('kyorangtalk_profiles')
      .select('id, nickname, avatar_url')
      .inFilter('id', senderIds);

  final profileMap = {
    for (final p in profiles) p['id'] as String: p
  };

  return msgs.map((m) {
    final subProfileId = m['sub_profile_id'] as String?;
    String? nickname;
    String? avatar;

    if (subProfileId != null && subProfileMap.containsKey(subProfileId)) {
      final sub = subProfileMap[subProfileId]!;
      final subNick = sub['nickname'] as String?;
      final subName = sub['name'] as String?;
      nickname = subNick?.isNotEmpty == true ? subNick : subName;
      avatar = sub['avatar_url'] as String?;
    }

    if (nickname == null) {
      final prof = profileMap[m['sender_id']];
      nickname = prof?['nickname'] as String?;
      avatar = prof?['avatar_url'] as String?;
    }

    return GroupMessageModel.fromJson({
      ...m,
      'sender_nickname': nickname,
      'sender_avatar':   avatar,
    });
  }).toList();
}

Future<bool> loadOlderGroupMessages(String roomId) async {
  final ctrl = _activeGroupControllers[roomId];
  if (ctrl == null) return false;
  if (!ctrl.hasMore) return false;
  if (ctrl.isLoadingMore) return false;
  if (ctrl.messages.isEmpty) return false;

  ctrl.isLoadingMore = true;
  try {
    final oldestTime = ctrl.messages.first.createdAt;

    var query = _supabase
        .from('kyorangtalk_group_messages')
        .select('*')
        .eq('room_id', roomId)
        .lt('created_at', oldestTime.toIso8601String());

    if (ctrl.joinedAt != null) {
      query = query.gte('created_at', ctrl.joinedAt!.toIso8601String());
    }

    final data = await query
        .order('created_at', ascending: false)
        .limit(kMoreGroupMessageLimit);

    if (data.isEmpty) {
      ctrl.hasMore = false;
      return false;
    }

    final older = await _enrichMessages(data);
    final existingIds = ctrl.messages.map((m) => m.id).toSet();
    final newOnes = older.where((m) => !existingIds.contains(m.id)).toList();

    ctrl.messages = [...newOnes, ...ctrl.messages];
    ctrl.hasMore = data.length >= kMoreGroupMessageLimit;
    ctrl.emit();
    return true;
  } catch (e) {
    print('🔴 [Group Pagination] 실패: $e');
    return false;
  } finally {
    ctrl.isLoadingMore = false;
  }
}

bool hasMoreGroupMessages(String roomId) {
  return _activeGroupControllers[roomId]?.hasMore ?? false;
}

Future<void> markGroupRoomRead(String roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return;

  try {
    await _supabase.from('kyorangtalk_group_reads').upsert({
      'room_id': roomId,
      'user_id': user.id,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'room_id,user_id');
  } catch (e) {
    print('markGroupRoomRead 오류: $e');
  }
}

// ═══════════════════════════════════════════════
// 그룹 메시지 전송
// ═══════════════════════════════════════════════
Future<void> sendGroupMessage({
    required String roomId,
    required String senderId,
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
    final hasAdmin = await checkHasRoomAdmin(roomId);
    if (!hasAdmin) {
      throw Exception('방장이 나가서 더 이상 대화할 수 없어요');
    }

    final subProfileId = await getMySubProfileInRoom(roomId);

    String msgType;
    if (fileUrl != null) {
      msgType = 'file';
    } else if (pollId != null) {
      msgType = 'poll';
    } else if (gameData != null) {
      msgType = 'game';
    } else if (audioUrl != null) {
      msgType = 'audio';
    } else if ((imageUrls != null && imageUrls.isNotEmpty) || imageUrl != null) {
      msgType = 'image';
    } else {
      msgType = 'message';
    }

    await _supabase.from('kyorangtalk_group_messages').insert({
      'room_id':          roomId,
      'sender_id':        senderId,
      'content':          content.trim(),
      'msg_type':         msgType,
      'is_deleted':       false,
      if (subProfileId != null)   'sub_profile_id':   subProfileId,
      if (imageUrl != null)       'image_url':        imageUrl,
      if (imageUrls != null && imageUrls.isNotEmpty)
                                  'image_urls':       imageUrls,
      if (audioUrl != null)       'audio_url':        audioUrl,
      if (audioDuration != null)  'audio_duration':   audioDuration,
      if (replyToId != null)      'reply_to_id':      replyToId,
      if (replyToContent != null) 'reply_to_content': replyToContent,
      if (gameData != null)       'game_data':        gameData,
      if (pollId != null)         'poll_id':          pollId,
      if (fileUrl != null)        'file_url':         fileUrl,
      if (fileName != null)       'file_name':        fileName,
      if (fileSize != null)       'file_size':        fileSize,
      if (fileType != null)       'file_type':        fileType,
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
    } else if (imageUrl != null || (imageUrls != null && imageUrls.isNotEmpty)) {
      lastMessageText = '[이미지]';
    } else {
      lastMessageText = content.trim();
    }

    await _supabase
        .from('kyorangtalk_group_rooms')
        .update({
          'last_message':    lastMessageText,
          'last_message_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', roomId);

    await markGroupRoomRead(roomId);
  }

// ═══════════════════════════════════════════════
// ⭐⭐⭐ 비번 검증 결과 enum
// ═══════════════════════════════════════════════
enum JoinResult {
  ok,
  wrongPassword,
  notFound,
  notAuthenticated,
  needsPassword,                              // 클라 측에서 사전 체크용
  error,
}

// ═══════════════════════════════════════════════
// ⭐ 방의 비번 보호 여부 (입장 전 체크)
// ═══════════════════════════════════════════════
Future<bool> roomRequiresPassword(String roomId) async {
  try {
    final result = await _supabase.rpc(
      'kyorangtalk_room_requires_password',
      params: {'p_room_id': roomId},
    );
    return result == true;
  } catch (e) {
    print('roomRequiresPassword 오류: $e');
    return false;
  }
}

// ═══════════════════════════════════════════════
// ⭐ 비번 포함 입장 (오픈 채팅용)
// ═══════════════════════════════════════════════
/// password가 null이면 비번 없는 방으로 가정.
/// 서버에서 검증 후 결과 반환.
Future<JoinResult> joinRoomWithPassword({
  required String roomId,
  String? password,
  String? subProfileId,
}) async {
  try {
    final result = await _supabase.rpc(
      'kyorangtalk_join_room_with_password',
      params: {
        'p_room_id': roomId,
        'p_password': password ?? '',
      },
    );

    final code = result as String?;
    switch (code) {
      case 'ok':
        // sub_profile_id가 있으면 별도로 update (RPC는 단순 INSERT만 함)
        if (subProfileId != null) {
          final user = _supabase.auth.currentUser!;
          await _supabase
              .from('kyorangtalk_group_members')
              .update({'sub_profile_id': subProfileId})
              .eq('room_id', roomId)
              .eq('user_id', user.id);
        }
        return JoinResult.ok;
      case 'wrong_password':
        return JoinResult.wrongPassword;
      case 'not_found':
        return JoinResult.notFound;
      case 'not_authenticated':
        return JoinResult.notAuthenticated;
      default:
        return JoinResult.error;
    }
  } catch (e) {
    print('joinRoomWithPassword 오류: $e');
    return JoinResult.error;
  }
}

// ═══════════════════════════════════════════════
// ⭐ 초대코드 + 비번으로 입장
// ═══════════════════════════════════════════════
Future<JoinResult> joinByCodeWithPassword({
  required String inviteCode,
  String? password,
}) async {
  try {
    final result = await _supabase.rpc(
      'kyorangtalk_join_by_code_with_password',
      params: {
        'p_invite_code': inviteCode.trim(),
        'p_password': password ?? '',
      },
    );
    final code = result as String?;
    switch (code) {
      case 'ok':
        return JoinResult.ok;
      case 'wrong_password':
        return JoinResult.wrongPassword;
      case 'not_found':
        return JoinResult.notFound;
      case 'not_authenticated':
        return JoinResult.notAuthenticated;
      default:
        return JoinResult.error;
    }
  } catch (e) {
    print('joinByCodeWithPassword 오류: $e');
    return JoinResult.error;
  }
}

/// 초대코드 입장 시 비번 보호 여부 사전 확인
Future<bool> codeRequiresPassword(String inviteCode) async {
  try {
    final r = await _supabase
        .from('kyorangtalk_group_rooms')
        .select('password_hash')
        .eq('invite_code', inviteCode.trim())
        .maybeSingle();
    if (r == null) return false;
    return r['password_hash'] != null;
  } catch (e) {
    return false;
  }
}

// ═══════════════════════════════════════════════
// 레거시: 비번 없이 입장 (비번 없는 방용 - 기존 호출처 호환)
// ═══════════════════════════════════════════════
Future<bool> joinGroupByCode(String inviteCode) async {
  final result = await joinByCodeWithPassword(
    inviteCode: inviteCode,
    password: null,
  );
  return result == JoinResult.ok;
}

Future<void> joinOpenRoom(String roomId, {String? subProfileId}) async {
  await joinRoomWithPassword(
    roomId: roomId,
    password: null,
    subProfileId: subProfileId,
  );
}

Future<String?> uploadRoomImage(File file) async {
  try {
    final user = _supabase.auth.currentUser!;
    final ext = file.path.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'room-avatars/${user.id}_$timestamp.$ext';

    await _supabase.storage
        .from('kyorangtalk')
        .upload(path, file,
            fileOptions: const FileOptions(upsert: true));

    final url = _supabase.storage
        .from('kyorangtalk')
        .getPublicUrl(path);

    return url;
  } catch (e) {
    print('방 이미지 업로드 실패: $e');
    return null;
  }
}

// ═══════════════════════════════════════════════
// ⭐⭐⭐ 방 생성 (password 인자 추가)
// ═══════════════════════════════════════════════
Future<GroupRoomModel?> createGroupRoom({
  required String name,
  required String roomType,
  String? description,
  String category = '일반',
  required List<String> memberIds,
  String? avatarUrl,
  List<String> tags = const [],
  String? password,                                          // ⭐ NEW
}) async {
  final user = _supabase.auth.currentUser!;
  final inviteCode = DateTime.now()
      .millisecondsSinceEpoch
      .toRadixString(16)
      .substring(0, 8);

  // ⭐ 비번이 있으면 서버에서 해싱
  String? passwordHash;
  if (password != null && password.trim().isNotEmpty) {
    try {
      final hashed = await _supabase.rpc(
        'kyorangtalk_hash_password',
        params: {'p_password': password.trim()},
      );
      passwordHash = hashed as String?;
    } catch (e) {
      print('비번 해싱 실패: $e');
      // 해싱 실패 시 방 생성도 중단
      return null;
    }
  }

  final room = await _supabase
      .from('kyorangtalk_group_rooms')
      .insert({
        'name':         name.trim(),
        'description':  description?.trim(),
        'created_by':   user.id,
        'invite_code':  inviteCode,
        'room_type':    roomType,
        'category':     category,
        'member_count': 0,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (tags.isNotEmpty) 'tags': tags,
        if (passwordHash != null) 'password_hash': passwordHash,    // ⭐ NEW
      })
      .select()
      .single();

  await _supabase.from('kyorangtalk_group_members').insert({
    'room_id': room['id'],
    'user_id': user.id,
    'role':    'admin',
  });

  final uniqueMemberIds = memberIds.toSet().toList();
  for (final memberId in uniqueMemberIds) {
    if (memberId == user.id) continue;
    try {
      await _supabase.from('kyorangtalk_group_members').insert({
        'room_id': room['id'],
        'user_id': memberId,
        'role':    'member',
      });
    } catch (e) {
      print('멤버 추가 실패 ($memberId): $e');
    }
  }

  return GroupRoomModel(
    id:          room['id'] as String,
    name:        room['name'] as String,
    description: room['description'] as String?,
    avatarUrl:   avatarUrl,
    createdBy:   user.id,
    inviteCode:  inviteCode,
    memberCount: 1 + uniqueMemberIds.where((id) => id != user.id).length,
    roomType:    roomType,
    category:    category,
    createdAt:   room['created_at'] as String,
    myRole:      'admin',
    tags:        tags,
    hasPassword: passwordHash != null,                              // ⭐ NEW
  );
}

Future<void> leaveGroupRoom(String roomId) async {
  final user = _supabase.auth.currentUser!;
  await _supabase
      .from('kyorangtalk_group_members')
      .delete()
      .eq('room_id', roomId)
      .eq('user_id', user.id);
}

Future<void> promoteToModerator({
  required String roomId,
  required String userId,
}) async {
  await _supabase
      .from('kyorangtalk_group_members')
      .update({'role': 'moderator'})
      .eq('room_id', roomId)
      .eq('user_id', userId);
}

Future<void> demoteToMember({
  required String roomId,
  required String userId,
}) async {
  await _supabase
      .from('kyorangtalk_group_members')
      .update({'role': 'member'})
      .eq('room_id', roomId)
      .eq('user_id', userId);
}

Future<void> kickMember({
  required String roomId,
  required String userId,
}) async {
  await _supabase
      .from('kyorangtalk_group_members')
      .delete()
      .eq('room_id', roomId)
      .eq('user_id', userId);
}

Future<String?> getMyRoleInRoom(String roomId) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return null;

  final data = await _supabase
      .from('kyorangtalk_group_members')
      .select('role')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  return data?['role'] as String?;
}

// ═══════════════════════════════════════════════════
// ⭐ 비밀번호 변경/제거 결과
// ═══════════════════════════════════════════════════
// (이 코드를 group_chat_provider.dart 파일 끝에 추가하세요)

enum PasswordUpdateResult {
  updated,           // 비번 변경/설정 성공
  removed,           // 비번 제거 성공
  notAdmin,          // 방장 아님
  notMember,         // 멤버 아님
  notAuthenticated,  // 미로그인
  error,             // 기타 오류
}

/// 방 비밀번호 변경/제거 (방장만 가능)
///
/// [newPassword]가 null 또는 빈 문자열이면 비번 제거.
/// 그 외엔 새 비번으로 설정.
Future<PasswordUpdateResult> updateRoomPassword({
  required String roomId,
  String? newPassword,
}) async {
  try {
    final result = await _supabase.rpc(
      'kyorangtalk_update_room_password',
      params: {
        'p_room_id': roomId,
        'p_new_password': (newPassword == null || newPassword.isEmpty)
            ? ''
            : newPassword,
      },
    );

    final code = result as String?;
    switch (code) {
      case 'updated':           return PasswordUpdateResult.updated;
      case 'removed':           return PasswordUpdateResult.removed;
      case 'not_admin':         return PasswordUpdateResult.notAdmin;
      case 'not_member':        return PasswordUpdateResult.notMember;
      case 'not_authenticated': return PasswordUpdateResult.notAuthenticated;
      default:                  return PasswordUpdateResult.error;
    }
  } catch (e) {
    print('updateRoomPassword 오류: $e');
    return PasswordUpdateResult.error;
  }
}