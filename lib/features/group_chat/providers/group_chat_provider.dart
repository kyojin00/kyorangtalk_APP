import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../chat/services/message_cache_service.dart';
import '../models/group_room_model.dart';
import '../models/group_message_model.dart';

final _supabase = Supabase.instance.client;

String? currentOpenGroupRoomId;

const int kInitialGroupMessageLimit = 50;
const int kMoreGroupMessageLimit = 50;

// ⭐ Prefetch 설정
const int kPrefetchGroupTopN = 7;
const Duration kPrefetchGroupFreshness = Duration(minutes: 1);
final Set<String> _prefetchGroupInFlight = {};

// ⭐ NEW: stale 그룹 캐시 정리 — 세션당 1회만
bool _didCleanupStaleGroup = false;

// ⭐ 채팅방 목록 표시 정책 (재설치 케이스만 정리)
//   - 로컬 캐시에 메시지가 있는 방 = 항상 표시 (사용자가 이미 본 방)
//   - 로컬 캐시 없는 방 = 7일 이내 활동이 있을 때만 표시
//   → 한 기기에서 계속 쓰면 자동 숨김 없음
//   → 재설치 후엔 빈 깡통 방 안 보임
//   → 복원하면 캐시 채워져서 자동으로 다 보임
const Duration kGroupRoomListRetention = Duration(days: 7);

// ═══════════════════════════════════════════════
// 프로필 캐시 (메모리, 방 단위)
// ═══════════════════════════════════════════════
class _ProfileCache {
  final Map<String, Map<String, dynamic>> subProfiles = {};
  final Map<String, Map<String, dynamic>> profiles = {};
}

final Map<String, _ProfileCache> _roomProfileCaches = {};

_ProfileCache _getCache(String roomId) {
  return _roomProfileCaches.putIfAbsent(roomId, () => _ProfileCache());
}

final Map<String, String?> _mySubProfileCache = {};
final Map<String, bool> _mySubProfileResolved = {};

void invalidateMySubProfileCache(String roomId) {
  _mySubProfileCache.remove(roomId);
  _mySubProfileResolved.remove(roomId);
}

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
// ⭐ Prefetch (앱 시작 시 백그라운드 사전 로드)
// ═══════════════════════════════════════════════
void prefetchTopGroupRooms(List<GroupRoomModel> rooms) {
  for (final room in rooms.take(kPrefetchGroupTopN)) {
    _prefetchGroupMessages(room.id);
  }
}

Future<void> _prefetchGroupMessages(String roomId) async {
  if (_prefetchGroupInFlight.contains(roomId)) return;
  if (_activeGroupControllers.containsKey(roomId)) return;

  final existing = MessageCacheService.loadGroup(roomId);
  if (existing != null &&
      DateTime.now().difference(existing.savedAt) <
          kPrefetchGroupFreshness) {
    return;
  }

  _prefetchGroupInFlight.add(roomId);
  try {
    final result =
        await _loadInitialGroupMessages(roomId, kInitialGroupMessageLimit);

    await MessageCacheService.saveGroup(
      roomId: roomId,
      messages: result.messages,
      joinedAt: result.joinedAt,
      hasMore: result.hasMore,
    );
    print('✅ [prefetchGroup] $roomId (${result.messages.length}개)');
  } catch (e) {
    print('🔴 [prefetchGroup] 실패 ($roomId): $e');
  } finally {
    _prefetchGroupInFlight.remove(roomId);
  }
}

// ═══════════════════════════════════════════════
// ⭐ 실시간 캐시 갱신
// 사용자가 그 방을 안 보고 있어도 새 메시지가 오면 캐시에 추가
// ═══════════════════════════════════════════════
Future<void> _appendToGroupCache(
    String roomId, Map<String, dynamic> newRow) async {
  if (_activeGroupControllers.containsKey(roomId)) return;

  final existing = MessageCacheService.loadGroup(roomId);
  if (existing == null) return; // prefetch 안 된 방은 skip

  try {
    final msg = await _enrichSingleMessage(roomId, newRow);
    if (msg == null) return;

    // joined_at 이전 메시지는 skip
    if (existing.joinedAt != null &&
        msg.createdAt.isBefore(existing.joinedAt!)) {
      return;
    }

    if (existing.messages.any((m) => m.id == msg.id)) return;

    final updated = [...existing.messages, msg];
    await MessageCacheService.saveGroup(
      roomId: roomId,
      messages: updated,
      joinedAt: existing.joinedAt,
      hasMore: existing.hasMore,
    );
  } catch (e) {
    print('🔴 [_appendToGroupCache] $roomId: $e');
  }
}

// ═══════════════════════════════════════════════
// 내가 참여한 그룹/오픈 채팅 목록 (실시간)
// ═══════════════════════════════════════════════
final groupRoomsProvider = StreamProvider<List<GroupRoomModel>>((ref) {
  final user = _supabase.auth.currentUser!;
  final controller = StreamController<List<GroupRoomModel>>();

  bool didPrefetch = false; // ⭐ NEW

  Future<List<GroupRoomModel>> fetchRooms() async {
    try {
      final members = await _supabase
          .from('kyorangtalk_group_members')
          .select('room_id, role, joined_at')
          .eq('user_id', user.id);

      // ⭐ NEW: 세션당 1회 stale 그룹 캐시 정리
      //   내가 멤버인 방만 유효 집합으로 사용
      //   (멤버 0개여도 청소는 진행 — 빈 set 넘기면 모든 그룹 캐시 삭제됨)
      if (!_didCleanupStaleGroup) {
        _didCleanupStaleGroup = true;
        try {
          final validGroupIds = <String>{
            for (final m in (members as List)) m['room_id'] as String,
          };
          await MessageCacheService.cleanupStaleRooms(
            validDmRoomIds: <String>{}, // DM은 chat_provider에서 처리, 여기선 빈 set이지만…
            validGroupRoomIds: validGroupIds,
          );
        } catch (e) {
          print('🟡 [Cache] stale group 정리 실패: $e');
        }
      }

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

      final parallelResults = await Future.wait<dynamic>([
        _supabase
            .from('kyorangtalk_group_rooms')
            .select('*')
            .inFilter('id', roomIds)
            .order('last_message_at', ascending: false),
        _supabase.rpc('get_group_unread_counts', params: {
          'p_user_id': user.id,
          'p_room_ids': roomIds,
        }),
      ]);

      final rooms = parallelResults[0] as List;
      final unreadList = parallelResults[1] as List;

      final unreadCounts = <String, int>{};
      for (final row in unreadList) {
        final rid = row['room_id'] as String;
        final count = (row['unread_count'] as num).toInt();
        unreadCounts[rid] = count;
      }

      final list = rooms.map((r) {
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
          hasPassword:   r['password_hash'] != null,
        );
      }).toList();

      // ⭐ 로컬 캐시 기반 필터링
      //   기준: 로컬에 메시지가 있으면 = 이미 이 기기에서 본 방 → 표시
      //         로컬에 없으면 = 재설치 또는 못 본 방 → 7일 컷 적용
      //   예외: 안 읽은 메시지 있는 방은 항상 표시
      //   새 방 (메시지 없음): createdAt 기준 7일 유예
      final cutoff = DateTime.now().subtract(kGroupRoomListRetention);
      return list.where((r) {
        if (r.unreadCount > 0) return true;

        // 로컬 캐시에 이 방 메시지가 있으면 항상 표시
        final cached = MessageCacheService.loadGroup(r.id);
        if (cached != null && cached.messages.isNotEmpty) return true;

        // 캐시 없는 방은 7일 컷 적용 (재설치 케이스 정리)
        if (r.lastMessageAt != null) {
          return r.lastMessageAt!.isAfter(cutoff);
        }
        // 메시지가 한 번도 없는 방: createdAt 기준
        final created = DateTime.tryParse(r.createdAt);
        if (created == null) return true; // 파싱 실패는 일단 표시
        return created.isAfter(cutoff);
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

    // ⭐ NEW: 첫 fetch 후 상위 N개 방 백그라운드 사전 로드
    if (!didPrefetch && data.isNotEmpty) {
      didPrefetch = true;
      prefetchTopGroupRooms(data);
    }
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
      .subscribe();

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
      .subscribe();

  final messagesChannel = _supabase
      .channel('provider_messages_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'kyorangtalk_group_messages',
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isNotEmpty) {
            // ⭐ NEW: 화면 안 열려 있는 방의 캐시에 새 메시지 자동 추가
            final roomId = row['room_id'] as String?;
            if (roomId != null) {
              _appendToGroupCache(roomId, row);
            }
          }
          scheduleRefetch('messages INSERT');
        },
      )
      .subscribe();

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
      .subscribe();

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
      hasPassword:   r['password_hash'] != null,
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
      hasPassword:   r['password_hash'] != null,
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
  if (_mySubProfileResolved[roomId] == true) {
    return _mySubProfileCache[roomId];
  }

  final user = _supabase.auth.currentUser;
  if (user == null) return null;

  final data = await _supabase
      .from('kyorangtalk_group_members')
      .select('sub_profile_id')
      .eq('room_id', roomId)
      .eq('user_id', user.id)
      .maybeSingle();

  final id = data?['sub_profile_id'] as String?;
  _mySubProfileCache[roomId] = id;
  _mySubProfileResolved[roomId] = true;
  return id;
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
// 그룹 메시지 목록
// ═══════════════════════════════════════════════
final groupMessagesProvider =
    StreamProvider.family.autoDispose<List<GroupMessageModel>, String>(
        (ref, roomId) {
  final streamController = StreamController<List<GroupMessageModel>>();
  final ctrl = _GroupRoomMessageController(roomId, streamController);
  _activeGroupControllers[roomId] = ctrl;

  // ⭐ ① 디스크 캐시(Hive)에 스냅샷이 있으면 즉시 복원
  final snapshot = MessageCacheService.loadGroup(roomId);
  final hasCachedData = snapshot != null;
  if (hasCachedData) {
    ctrl.messages = List.of(snapshot.messages);
    ctrl.joinedAt = snapshot.joinedAt;
    ctrl.hasMore = snapshot.hasMore;
    ctrl.emit();
    print('⚡ [groupMessages] 스냅샷 복원: $roomId '
        '(${snapshot.messages.length}개, '
        '${DateTime.now().difference(snapshot.savedAt).inSeconds}s 전)');
  }

  // ⭐ ② 백그라운드로 fresh 데이터 fetch + 머지
  _loadInitialGroupMessages(roomId, kInitialGroupMessageLimit)
      .then((result) {
    if (streamController.isClosed) return;

    if (hasCachedData) {
      final existingIds = ctrl.messages.map((m) => m.id).toSet();
      final newOnes = result.messages
          .where((m) => !existingIds.contains(m.id))
          .toList();

      if (newOnes.isNotEmpty) {
        ctrl.messages = [...ctrl.messages, ...newOnes];
        print('⚡ [groupMessages] 머지: $roomId (+${newOnes.length}개)');
      }
      ctrl.joinedAt = result.joinedAt;
      ctrl.emit();
    } else {
      ctrl.messages = result.messages;
      ctrl.joinedAt = result.joinedAt;
      ctrl.hasMore = result.hasMore;
      ctrl.emit();
    }
  }).catchError((e) {
    print('🔴 [groupMessages] 초기 로드 실패: $e');
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

          final msg = await _enrichSingleMessage(roomId, newRow);
          if (msg == null) return;

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
          final transcriptStatus =
              updated['audio_transcript_status'] as String?;
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
                locationShareId:       m.locationShareId,
                scheduleEventId:       m.scheduleEventId,
              );
            }
            return m;
          }).toList();
          ctrl.emit();
        },
      )
      .subscribe();

  ref.onDispose(() {
    MessageCacheService.saveGroup(
      roomId: roomId,
      messages: ctrl.messages,
      joinedAt: ctrl.joinedAt,
      hasMore: ctrl.hasMore,
    );

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

  final results = await Future.wait<dynamic>([
    _supabase
        .from('kyorangtalk_group_members')
        .select('joined_at, sub_profile_id')
        .eq('room_id', roomId)
        .eq('user_id', user.id)
        .maybeSingle(),
    _supabase
        .from('kyorangtalk_group_messages')
        .select('*')
        .eq('room_id', roomId)
        .order('created_at', ascending: false)
        .limit(limit),
  ]);

  final myMember = results[0] as Map<String, dynamic>?;
  var msgs = results[1] as List;

  DateTime? joinedAt;
  if (myMember != null) {
    joinedAt = DateTime.parse(myMember['joined_at'] as String);
    _mySubProfileCache[roomId] =
        myMember['sub_profile_id'] as String?;
    _mySubProfileResolved[roomId] = true;
  }

  if (joinedAt != null) {
    msgs = msgs.where((m) {
      final createdAt = DateTime.parse(m['created_at'] as String);
      return !createdAt.isBefore(joinedAt!);
    }).toList();
  }

  if (joinedAt != null && msgs.length < limit) {
    final refetched = await _supabase
        .from('kyorangtalk_group_messages')
        .select('*')
        .eq('room_id', roomId)
        .gte('created_at', joinedAt.toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    msgs = refetched as List;
  }

  if (msgs.isEmpty) return _InitialLoadResult([], joinedAt, false);

  final hasMore = msgs.length >= limit;
  final enriched = await _enrichMessages(
    roomId,
    msgs.map((m) => m as Map<String, dynamic>).toList(),
  );

  return _InitialLoadResult(enriched, joinedAt, hasMore);
}

Future<List<GroupMessageModel>> _enrichMessages(
    String roomId, List<Map<String, dynamic>> msgs) async {
  if (msgs.isEmpty) return [];

  final cache = _getCache(roomId);

  final subProfileIds = msgs
      .where((m) => m['sub_profile_id'] != null)
      .map((m) => m['sub_profile_id'] as String)
      .toSet()
      .where((id) => !cache.subProfiles.containsKey(id))
      .toList();

  final senderIds = msgs
      .map((m) => m['sender_id'] as String)
      .toSet()
      .where((id) => !cache.profiles.containsKey(id))
      .toList();

  final futures = <Future>[];
  if (subProfileIds.isNotEmpty) {
    futures.add(
      _supabase
          .from('kyorangtalk_sub_profiles')
          .select('id, name, nickname, avatar_url')
          .inFilter('id', subProfileIds),
    );
  } else {
    futures.add(Future.value([]));
  }

  if (senderIds.isNotEmpty) {
    futures.add(
      _supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', senderIds),
    );
  } else {
    futures.add(Future.value([]));
  }

  final results = await Future.wait(futures);
  final newSubProfiles = results[0] as List;
  final newProfiles = results[1] as List;

  for (final p in newSubProfiles) {
    cache.subProfiles[p['id'] as String] = p as Map<String, dynamic>;
  }
  for (final p in newProfiles) {
    cache.profiles[p['id'] as String] = p as Map<String, dynamic>;
  }

  return msgs.map((m) {
    final subProfileId = m['sub_profile_id'] as String?;
    String? nickname;
    String? avatar;

    if (subProfileId != null && cache.subProfiles.containsKey(subProfileId)) {
      final sub = cache.subProfiles[subProfileId]!;
      final subNick = sub['nickname'] as String?;
      final subName = sub['name'] as String?;
      nickname = subNick?.isNotEmpty == true ? subNick : subName;
      avatar = sub['avatar_url'] as String?;
    }

    if (nickname == null) {
      final prof = cache.profiles[m['sender_id']];
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

Future<GroupMessageModel?> _enrichSingleMessage(
    String roomId, Map<String, dynamic> newRow) async {
  try {
    final cache = _getCache(roomId);
    final subProfileId = newRow['sub_profile_id'] as String?;
    final senderId = newRow['sender_id'] as String;

    final futures = <Future>[];
    final needSubProfile =
        subProfileId != null && !cache.subProfiles.containsKey(subProfileId);
    final needProfile = !cache.profiles.containsKey(senderId);

    if (needSubProfile) {
      futures.add(
        _supabase
            .from('kyorangtalk_sub_profiles')
            .select('id, name, nickname, avatar_url')
            .eq('id', subProfileId)
            .maybeSingle(),
      );
    }
    if (needProfile) {
      futures.add(
        _supabase
            .from('kyorangtalk_profiles')
            .select('id, nickname, avatar_url')
            .eq('id', senderId)
            .maybeSingle(),
      );
    }

    if (futures.isNotEmpty) {
      final results = await Future.wait(futures);
      int idx = 0;
      if (needSubProfile) {
        final sub = results[idx++] as Map<String, dynamic>?;
        if (sub != null) cache.subProfiles[subProfileId] = sub;
      }
      if (needProfile) {
        final prof = results[idx++] as Map<String, dynamic>?;
        if (prof != null) cache.profiles[senderId] = prof;
      }
    }

    String? nickname;
    String? avatar;

    if (subProfileId != null && cache.subProfiles.containsKey(subProfileId)) {
      final sub = cache.subProfiles[subProfileId]!;
      final subNick = sub['nickname'] as String?;
      final subName = sub['name'] as String?;
      nickname = subNick?.isNotEmpty == true ? subNick : subName;
      avatar = sub['avatar_url'] as String?;
    }

    if (nickname == null) {
      final prof = cache.profiles[senderId];
      nickname = prof?['nickname'] as String?;
      avatar = prof?['avatar_url'] as String?;
    }

    return GroupMessageModel.fromJson({
      ...newRow,
      'sender_nickname': nickname,
      'sender_avatar':   avatar,
    });
  } catch (e) {
    print('🔴 _enrichSingleMessage 실패: $e');
    return null;
  }
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

    final older = await _enrichMessages(roomId, data);
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
  String? locationShareId,
  String? scheduleEventId,
}) async {
  final subProfileId = await getMySubProfileInRoom(roomId);

  String msgType;
  if (scheduleEventId != null) {
    msgType = 'schedule';
  } else if (locationShareId != null) {
    msgType = 'location_share';
  } else if (fileUrl != null) {
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
    if (subProfileId != null)    'sub_profile_id':    subProfileId,
    if (imageUrl != null)        'image_url':         imageUrl,
    if (imageUrls != null && imageUrls.isNotEmpty)
                                 'image_urls':        imageUrls,
    if (audioUrl != null)        'audio_url':         audioUrl,
    if (audioDuration != null)   'audio_duration':    audioDuration,
    if (replyToId != null)       'reply_to_id':       replyToId,
    if (replyToContent != null)  'reply_to_content':  replyToContent,
    if (gameData != null)        'game_data':         gameData,
    if (pollId != null)          'poll_id':           pollId,
    if (fileUrl != null)         'file_url':          fileUrl,
    if (fileName != null)        'file_name':         fileName,
    if (fileSize != null)        'file_size':         fileSize,
    if (fileType != null)        'file_type':         fileType,
    if (locationShareId != null) 'location_share_id': locationShareId,
    if (scheduleEventId != null) 'schedule_event_id': scheduleEventId,
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
  } else if (imageUrl != null || (imageUrls != null && imageUrls.isNotEmpty)) {
    lastMessageText = '[이미지]';
  } else {
    lastMessageText = content.trim();
  }

  _supabase
      .from('kyorangtalk_group_rooms')
      .update({
        'last_message':    lastMessageText,
        'last_message_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', roomId)
      .then((_) {})
      .catchError((e) {
    print('🔴 group rooms last_message 업데이트 실패: $e');
  });

  markGroupRoomRead(roomId).catchError((e) {
    print('🔴 markGroupRoomRead 실패: $e');
  });
}

// ═══════════════════════════════════════════════
// 비번/가입
// ═══════════════════════════════════════════════
enum JoinResult {
  ok,
  wrongPassword,
  notFound,
  notAuthenticated,
  needsPassword,
  error,
}

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
        if (subProfileId != null) {
          final user = _supabase.auth.currentUser!;
          await _supabase
              .from('kyorangtalk_group_members')
              .update({'sub_profile_id': subProfileId})
              .eq('room_id', roomId)
              .eq('user_id', user.id);
          _mySubProfileCache[roomId] = subProfileId;
          _mySubProfileResolved[roomId] = true;
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

Future<GroupRoomModel?> createGroupRoom({
  required String name,
  required String roomType,
  String? description,
  String category = '일반',
  required List<String> memberIds,
  String? avatarUrl,
  List<String> tags = const [],
  String? password,
}) async {
  final user = _supabase.auth.currentUser!;
  final inviteCode = DateTime.now()
      .millisecondsSinceEpoch
      .toRadixString(16)
      .substring(0, 8);

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
        if (passwordHash != null) 'password_hash': passwordHash,
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
    hasPassword: passwordHash != null,
  );
}

Future<void> leaveGroupRoom(String roomId) async {
  final user = _supabase.auth.currentUser!;
  await _supabase
      .from('kyorangtalk_group_members')
      .delete()
      .eq('room_id', roomId)
      .eq('user_id', user.id);

  MessageCacheService.removeGroup(roomId);
  _roomProfileCaches.remove(roomId);
  invalidateMySubProfileCache(roomId);
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

enum PasswordUpdateResult {
  updated,
  removed,
  notAdmin,
  notMember,
  notAuthenticated,
  error,
}

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