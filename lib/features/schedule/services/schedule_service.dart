import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/schedule_models.dart';

// ═══════════════════════════════════════════════════
// 📅 ScheduleService
//
// 위치: lib/features/schedule/services/schedule_service.dart
//
// 기능
// - 일정 생성 (DB row insert)
// - 응답 일괄 저장 (RPC)
// - 이벤트/히트맵/참가자 통합 조회
// - 확정 (만든 사람만)
// - 삭제 (만든 사람만)
//
// 싱글톤
// ═══════════════════════════════════════════════════

class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  final _supabase = Supabase.instance.client;

  // ─────────────────────────────────────────────
  // 생성
  // ─────────────────────────────────────────────

  /// 일정 이벤트 생성.
  /// 성공 시 ScheduleEvent 반환, 실패 시 null.
  Future<ScheduleEvent?> createEvent({
    required String roomId,
    required String roomType,
    required String title,
    String? description,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String timeFrom,   // "HH:mm"
    required String timeTo,     // "HH:mm"
    required int slotMinutes,   // 30 or 60
    Duration? expiresIn,        // 기본: dateTo + 1일
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final expiresAt = expiresIn != null
        ? DateTime.now().add(expiresIn)
        : DateTime(dateTo.year, dateTo.month, dateTo.day).add(
            const Duration(days: 1),
          );

    final draft = ScheduleEvent(
      id:          '',
      roomId:      roomId,
      roomType:    roomType,
      creatorId:   user.id,
      title:       title.trim(),
      description: description?.trim(),
      dateFrom:    DateTime(dateFrom.year, dateFrom.month, dateFrom.day),
      dateTo:      DateTime(dateTo.year,   dateTo.month,   dateTo.day),
      timeFrom:    timeFrom,
      timeTo:      timeTo,
      slotMinutes: slotMinutes,
      createdAt:   DateTime.now(),
      expiresAt:   expiresAt,
    );

    try {
      final inserted = await _supabase
          .from('kyorangtalk_schedule_events')
          .insert(draft.toInsertJson())
          .select()
          .single();

      final event = ScheduleEvent.fromJson(inserted);
      debugPrint('🟢 [Schedule] 이벤트 생성: ${event.id}');
      return event;
    } catch (e) {
      debugPrint('🔴 [Schedule] 이벤트 생성 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 응답 (슬롯 일괄 저장)
  // ─────────────────────────────────────────────

  /// 사용자의 응답을 통째로 저장.
  /// 기존 응답은 삭제되고 [selectedSlots] 가 새 응답이 됨.
  /// (빈 배열도 OK — "응답함 + 가능한 시간 없음" 의미)
  Future<bool> submitResponse({
    required String eventId,
    required Set<DateTime> selectedSlots,
  }) async {
    try {
      final slotsList = selectedSlots
          .map((dt) => dt.toUtc().toIso8601String())
          .toList();

      await _supabase.rpc('submit_schedule_response', params: {
        'p_event_id': eventId,
        'p_slots':    slotsList,
      });
      debugPrint('🟢 [Schedule] 응답 저장: $eventId (${slotsList.length}개)');
      return true;
    } catch (e) {
      debugPrint('🔴 [Schedule] 응답 저장 실패: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // 조회
  // ─────────────────────────────────────────────

  /// 단일 이벤트 조회
  Future<ScheduleEvent?> getEvent(String eventId) async {
    try {
      final row = await _supabase
          .from('kyorangtalk_schedule_events')
          .select()
          .eq('id', eventId)
          .maybeSingle();
      if (row == null) return null;
      return ScheduleEvent.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('🔴 [Schedule] getEvent 실패: $e');
      return null;
    }
  }

  /// 히트맵 데이터 조회 (시간별 응답자 수)
  Future<List<ScheduleHeatmapEntry>> getHeatmap(String eventId) async {
    try {
      final rows = await _supabase.rpc(
        'get_schedule_heatmap',
        params: {'p_event_id': eventId},
      );
      return (rows as List)
          .map((r) => ScheduleHeatmapEntry.fromJson(
              Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('🔴 [Schedule] getHeatmap 실패: $e');
      return [];
    }
  }

  /// 응답한 참가자 목록 (프로필 join)
  Future<List<ScheduleParticipant>> getParticipants(
      String eventId) async {
    try {
      final rows = await _supabase
          .from('kyorangtalk_schedule_participants')
          .select('id, event_id, user_id, responded_at')
          .eq('event_id', eventId);

      if (rows.isEmpty) return [];

      // 프로필 join
      final userIds =
          (rows as List).map((r) => r['user_id'] as String).toSet().toList();
      final profiles = await _supabase
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', userIds);

      final profileMap = <String, Map<String, dynamic>>{
        for (final p in (profiles as List))
          p['id'] as String: Map<String, dynamic>.from(p)
      };

      return rows.map((r) {
        final map = Map<String, dynamic>.from(r);
        final p = profileMap[map['user_id']];
        return ScheduleParticipant.fromJson({
          ...map,
          'nickname':  p?['nickname'],
          'avatar_url': p?['avatar_url'],
        });
      }).toList();
    } catch (e) {
      debugPrint('🔴 [Schedule] getParticipants 실패: $e');
      return [];
    }
  }

  /// 내가 선택한 슬롯들
  Future<Set<DateTime>> getMySlots(String eventId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return {};

    try {
      final rows = await _supabase
          .from('kyorangtalk_schedule_slots')
          .select('slot_start')
          .eq('event_id', eventId)
          .eq('user_id', user.id);

      return (rows as List)
          .map((r) => DateTime.parse(r['slot_start'] as String).toLocal())
          .toSet();
    } catch (e) {
      debugPrint('🔴 [Schedule] getMySlots 실패: $e');
      return {};
    }
  }

  /// 특정 슬롯에 응답한 사용자 목록 (히트맵 셀 탭 시)
  Future<List<Map<String, dynamic>>> getSlotUsers({
    required String eventId,
    required DateTime slotStart,
  }) async {
    try {
      final rows = await _supabase.rpc(
        'get_schedule_slot_users',
        params: {
          'p_event_id':   eventId,
          'p_slot_start': slotStart.toUtc().toIso8601String(),
        },
      );
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (e) {
      debugPrint('🔴 [Schedule] getSlotUsers 실패: $e');
      return [];
    }
  }

  /// 화면용 통합 데이터 한 번에
  Future<ScheduleSummary?> getSummary(String eventId) async {
    try {
      final results = await Future.wait([
        getEvent(eventId),
        getHeatmap(eventId),
        getParticipants(eventId),
        getMySlots(eventId),
      ]);

      final event = results[0] as ScheduleEvent?;
      if (event == null) return null;

      return ScheduleSummary(
        event:        event,
        heatmap:      results[1] as List<ScheduleHeatmapEntry>,
        participants: results[2] as List<ScheduleParticipant>,
        mySlots:      results[3] as Set<DateTime>,
      );
    } catch (e) {
      debugPrint('🔴 [Schedule] getSummary 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 확정 / 삭제 (만든 사람만)
  // ─────────────────────────────────────────────

  /// 일정 확정 — 최종 시간 지정
  Future<bool> confirmSchedule({
    required String eventId,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      await _supabase
          .from('kyorangtalk_schedule_events')
          .update({
            'confirmed_start': start.toUtc().toIso8601String(),
            'confirmed_end':   end.toUtc().toIso8601String(),
            'confirmed_at':    DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId);
      debugPrint('🟢 [Schedule] 확정: $eventId');
      return true;
    } catch (e) {
      debugPrint('🔴 [Schedule] 확정 실패: $e');
      return false;
    }
  }

  /// 확정 해제 (만든 사람만)
  Future<bool> unconfirmSchedule(String eventId) async {
    try {
      await _supabase
          .from('kyorangtalk_schedule_events')
          .update({
            'confirmed_start': null,
            'confirmed_end':   null,
            'confirmed_at':    null,
          })
          .eq('id', eventId);
      return true;
    } catch (e) {
      debugPrint('🔴 [Schedule] 확정 해제 실패: $e');
      return false;
    }
  }

  /// 일정 삭제 (만든 사람만)
  Future<bool> deleteEvent(String eventId) async {
    try {
      await _supabase
          .from('kyorangtalk_schedule_events')
          .delete()
          .eq('id', eventId);
      debugPrint('🟢 [Schedule] 삭제: $eventId');
      return true;
    } catch (e) {
      debugPrint('🔴 [Schedule] 삭제 실패: $e');
      return false;
    }
  }
}