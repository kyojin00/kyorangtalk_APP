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