import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════
// 신고 이유 enum
// ═══════════════════════════════════════════════
enum ReportReason {
  spam('spam', '스팸/광고'),
  inappropriate('inappropriate', '부적절한 내용'),
  sexual('sexual', '음란물'),
  violence('violence', '폭력/위협'),
  fraud('fraud', '사기/사칭'),
  hate('hate', '혐오 발언'),
  harassment('harassment', '괴롭힘'),
  privacy('privacy', '개인정보 침해'),
  other('other', '기타');

  final String value;
  final String label;
  const ReportReason(this.value, this.label);
}

enum ReportType {
  user('user', '사용자'),
  message('message', '메시지'),
  room('room', '채팅방');

  final String value;
  final String label;
  const ReportType(this.value, this.label);
}

// ═══════════════════════════════════════════════
// 신고 서비스
// ═══════════════════════════════════════════════
class ReportService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 사용자 신고
  Future<void> reportUser({
    required String reportedUserId,
    required ReportReason reason,
    String? description,
    String? contentSnapshot,
  }) async {
    final myId = _supabase.auth.currentUser!.id;

    if (reportedUserId == myId) {
      throw Exception('자기 자신은 신고할 수 없어요');
    }

    final existing = await _supabase
        .from('kyorangtalk_reports')
        .select('id')
        .eq('reporter_id', myId)
        .eq('reported_user_id', reportedUserId)
        .eq('report_type', 'user')
        .eq('status', 'pending')
        .gte('created_at',
            DateTime.now().subtract(const Duration(hours: 24)).toIso8601String())
        .maybeSingle();

    if (existing != null) {
      throw Exception('최근 24시간 내에 이미 신고하셨어요');
    }

    await _supabase.from('kyorangtalk_reports').insert({
      'reporter_id': myId,
      'reported_user_id': reportedUserId,
      'report_type': 'user',
      'reason': reason.value,
      'description': description,
      'content_snapshot': contentSnapshot,
    });
  }

  /// 메시지 신고
  Future<void> reportMessage({
    required String messageId,
    required String senderId,
    required String roomId,
    required String messageContent,
    required ReportReason reason,
    String? description,
  }) async {
    final myId = _supabase.auth.currentUser!.id;

    await _supabase.from('kyorangtalk_reports').insert({
      'reporter_id': myId,
      'reported_user_id': senderId,
      'reported_message_id': messageId,
      'reported_room_id': roomId,
      'report_type': 'message',
      'reason': reason.value,
      'description': description,
      'content_snapshot': messageContent,
    });
  }

  /// 채팅방 신고
  Future<void> reportRoom({
    required String roomId,
    required ReportReason reason,
    String? description,
  }) async {
    final myId = _supabase.auth.currentUser!.id;

    await _supabase.from('kyorangtalk_reports').insert({
      'reporter_id': myId,
      'reported_room_id': roomId,
      'report_type': 'room',
      'reason': reason.value,
      'description': description,
    });
  }

  /// ⭐ NEW: 사용자 차단 + 친구 관계 삭제
  Future<void> blockUser(String userId) async {
    final myId = _supabase.auth.currentUser!.id;
    if (userId == myId) return;

    final existing = await _supabase
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', myId)
        .eq('blocked_id', userId)
        .maybeSingle();

    if (existing != null) return;

    await _supabase.from('kyorangtalk_blocks').insert({
      'blocker_id': myId,
      'blocked_id': userId,
    });

    try {
      await _supabase.from('kyorangtalk_friends').delete().or(
          'and(requester_id.eq.$myId,receiver_id.eq.$userId),'
          'and(requester_id.eq.$userId,receiver_id.eq.$myId)');
    } catch (_) {}
  }

  /// ⭐ NEW: 신고 + 자동 차단 (사용자)
  Future<void> reportUserAndBlock({
    required String reportedUserId,
    required ReportReason reason,
    String? description,
    String? contentSnapshot,
    bool alsoBlock = true,
  }) async {
    await reportUser(
      reportedUserId: reportedUserId,
      reason: reason,
      description: description,
      contentSnapshot: contentSnapshot,
    );

    if (alsoBlock) {
      try {
        await blockUser(reportedUserId);
      } catch (_) {}
    }
  }

  /// ⭐ NEW: 신고 + 자동 차단 (메시지)
  Future<void> reportMessageAndBlock({
    required String messageId,
    required String senderId,
    required String roomId,
    required String messageContent,
    required ReportReason reason,
    String? description,
    bool alsoBlock = true,
  }) async {
    await reportMessage(
      messageId: messageId,
      senderId: senderId,
      roomId: roomId,
      messageContent: messageContent,
      reason: reason,
      description: description,
    );

    if (alsoBlock) {
      try {
        await blockUser(senderId);
      } catch (_) {}
    }
  }

  /// 내 신고 내역 조회
  Future<List<Map<String, dynamic>>> getMyReports() async {
    final myId = _supabase.auth.currentUser!.id;

    final data = await _supabase
        .from('kyorangtalk_reports')
        .select('*, reported:reported_user_id(nickname, avatar_url)')
        .eq('reporter_id', myId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  /// ⭐ NEW: 내가 차단한 사용자 ID 목록 조회
  Future<Set<String>> getBlockedUserIds() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return <String>{};

    final data = await _supabase
        .from('kyorangtalk_blocks')
        .select('blocked_id')
        .eq('blocker_id', myId);

    return (data as List)
        .map((row) => row['blocked_id'] as String)
        .toSet();
  }
}

// ═══════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════
final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService();
});

final myReportsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(reportServiceProvider);
  return service.getMyReports();
});

/// ⭐ NEW: 내가 차단한 사용자 ID 목록 (그룹 채팅 + 보이스 룸 필터링용)
///
/// 실시간으로 차단 변경을 감지해서 자동 업데이트.
final blockedUserIdsProvider = StreamProvider<Set<String>>((ref) {
  final supabase = Supabase.instance.client;
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) {
    return Stream.value(<String>{});
  }

  final service = ref.read(reportServiceProvider);
  final controller = StreamController<Set<String>>();

  // 초기 로드
  service.getBlockedUserIds().then((ids) {
    if (!controller.isClosed) controller.add(ids);
  });

  // Realtime 구독
  final channel = supabase
      .channel('blocked_users:$myId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_blocks',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'blocker_id',
          value: myId,
        ),
        callback: (_) async {
          if (controller.isClosed) return;
          final ids = await service.getBlockedUserIds();
          if (!controller.isClosed) controller.add(ids);
        },
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    supabase.removeChannel(channel);
  });

  return controller.stream;
});