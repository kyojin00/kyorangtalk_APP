import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_model.dart';

// PlanModel을 같이 export → 사용처에서 plan_service.dart만 import하면 됨
export '../models/plan_model.dart';

/// ═══════════════════════════════════════════════════
/// 약속 자동 정리 (Plan Extractor) 서비스
/// ═══════════════════════════════════════════════════
class PlanService {
  static final _supabase = Supabase.instance.client;

  /// 메시지에서 약속 자동 추출 (Edge Function 호출)
  ///
  /// 한도 초과 시 null 반환 (자동 트리거라 모달 안 띄움 - 조용히 실패)
  /// 정말로 한도 초과인지 알고 싶으면 PlanExtractResult 반환하는 버전 쓸 것
  static Future<PlanModel?> extractFromMessage({
    required String roomId,
    required bool isGroup,
    required String messageId,
    required String messageText,
    required String senderName,
    List<String>? context,
  }) async {
    final result = await extractFromMessageWithResult(
      roomId: roomId,
      isGroup: isGroup,
      messageId: messageId,
      messageText: messageText,
      senderName: senderName,
      context: context,
    );
    return result.plan;
  }

  /// ⭐ 한도 초과 여부도 함께 반환하는 버전
  /// (자동 트리거 외에 명시적으로 요청하는 케이스용)
  static Future<PlanExtractResult> extractFromMessageWithResult({
    required String roomId,
    required bool isGroup,
    required String messageId,
    required String messageText,
    required String senderName,
    List<String>? context,
  }) async {
    print('📅 [Plan] extract: msgId=$messageId');

    try {
      final response = await _supabase.functions.invoke(
        'plan-extract',
        body: {
          'roomId': roomId,
          'roomType': isGroup ? 'group' : 'dm',
          'messageId': messageId,
          'messageText': messageText,
          'senderName': senderName,
          if (context != null && context.isNotEmpty) 'context': context,
        },
      );

      final data = response.data;
      if (data is! Map) return PlanExtractResult.empty();

      // ⭐ 한도 초과 체크
      if (data['error'] == 'quota_exceeded') {
        print('⛔ [Plan] 한도 초과');
        return PlanExtractResult.quotaExceeded();
      }

      if (data['error'] != null) {
        print('🔴 [Plan] 서버 에러: ${data['error']}');
        return PlanExtractResult.empty();
      }

      final plan = data['plan'];
      if (plan == null) {
        print('📅 [Plan] 약속 없음');
        return PlanExtractResult.empty();
      }

      final planId = data['planId'] as String?;
      if (planId == null) return PlanExtractResult.empty();

      final fetched = await fetchById(planId);
      return PlanExtractResult(plan: fetched);
    } catch (e) {
      // ⭐ FunctionException에서 429 잡기
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('quota_exceeded') || errStr.contains('429')) {
        print('⛔ [Plan] 한도 초과 (catch)');
        return PlanExtractResult.quotaExceeded();
      }

      print('🔴 [Plan] 예외: $e');
      return PlanExtractResult.empty();
    }
  }

  /// ID로 약속 조회
  static Future<PlanModel?> fetchById(String planId) async {
    try {
      final data = await _supabase
          .from('kyorangtalk_plans')
          .select()
          .eq('id', planId)
          .maybeSingle();
      if (data == null) return null;
      return PlanModel.fromJson(data);
    } catch (e) {
      print('🔴 [Plan] fetchById 실패: $e');
      return null;
    }
  }

  /// 메시지 ID로 약속 조회
  static Future<PlanModel?> fetchByMessageId(String messageId) async {
    try {
      final data = await _supabase
          .from('kyorangtalk_plans')
          .select()
          .eq('source_message_id', messageId)
          .maybeSingle();
      if (data == null) return null;
      return PlanModel.fromJson(data);
    } catch (e) {
      print('🔴 [Plan] fetchByMessageId 실패: $e');
      return null;
    }
  }

  /// 특정 방의 모든 약속
  static Future<List<PlanModel>> fetchByRoom({
    required String roomId,
    required bool isGroup,
    bool includeDismissed = false,
  }) async {
    try {
      var query = _supabase
          .from('kyorangtalk_plans')
          .select()
          .eq('room_id', roomId)
          .eq('room_type', isGroup ? 'group' : 'dm');

      if (!includeDismissed) {
        query = query.eq('is_dismissed', false);
      }

      final data = await query.order('scheduled_at', ascending: false);
      return (data as List)
          .map((e) => PlanModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('🔴 [Plan] fetchByRoom 실패: $e');
      return [];
    }
  }

  /// 내가 만든 다가오는 약속들
  static Future<List<PlanModel>> fetchMyUpcoming() async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) return [];

      final data = await _supabase
          .from('kyorangtalk_plans')
          .select()
          .eq('created_by', me)
          .eq('status', 'upcoming')
          .eq('is_dismissed', false)
          .gte('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at', ascending: true);

      return (data as List)
          .map((e) => PlanModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('🔴 [Plan] fetchMyUpcoming 실패: $e');
      return [];
    }
  }

  /// 내가 만든 지난 약속들
  static Future<List<PlanModel>> fetchMyPast({int limit = 50}) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) return [];

      final data = await _supabase
          .from('kyorangtalk_plans')
          .select()
          .eq('created_by', me)
          .eq('is_dismissed', false)
          .lt('scheduled_at', DateTime.now().toIso8601String())
          .order('scheduled_at', ascending: false)
          .limit(limit);

      return (data as List)
          .map((e) => PlanModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('🔴 [Plan] fetchMyPast 실패: $e');
      return [];
    }
  }

  /// 약속 dismiss
  static Future<bool> dismissPlan(String planId) async {
    try {
      await _supabase
          .from('kyorangtalk_plans')
          .update({'is_dismissed': true})
          .eq('id', planId);
      return true;
    } catch (e) {
      print('🔴 [Plan] dismissPlan 실패: $e');
      return false;
    }
  }

  /// 상태 변경
  static Future<bool> updateStatus({
    required String planId,
    required String status,
  }) async {
    try {
      await _supabase
          .from('kyorangtalk_plans')
          .update({'status': status})
          .eq('id', planId);
      return true;
    } catch (e) {
      print('🔴 [Plan] updateStatus 실패: $e');
      return false;
    }
  }

  /// 약속 정보 수정
  static Future<bool> updatePlan({
    required String planId,
    String? title,
    DateTime? scheduledAt,
    String? location,
    List<String>? attendees,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (scheduledAt != null) {
        updates['scheduled_at'] = scheduledAt.toUtc().toIso8601String();
      }
      if (location != null) updates['location'] = location;
      if (attendees != null) updates['attendees'] = attendees;
      if (notes != null) updates['notes'] = notes;

      if (updates.isEmpty) return true;

      await _supabase
          .from('kyorangtalk_plans')
          .update(updates)
          .eq('id', planId);
      return true;
    } catch (e) {
      print('🔴 [Plan] updatePlan 실패: $e');
      return false;
    }
  }

  /// 약속 삭제
  static Future<bool> deletePlan(String planId) async {
    try {
      await _supabase.from('kyorangtalk_plans').delete().eq('id', planId);
      return true;
    } catch (e) {
      print('🔴 [Plan] deletePlan 실패: $e');
      return false;
    }
  }
}

/// ═══════════════════════════════════════════════════
/// 약속 추출 결과 (한도 초과 정보 포함)
/// ═══════════════════════════════════════════════════
class PlanExtractResult {
  final PlanModel? plan;
  final bool isQuotaExceeded;

  PlanExtractResult({
    this.plan,
    this.isQuotaExceeded = false,
  });

  factory PlanExtractResult.empty() {
    return PlanExtractResult();
  }

  factory PlanExtractResult.quotaExceeded() {
    return PlanExtractResult(isQuotaExceeded: true);
  }
}