// ════════════════════════════════════════════════════════════════
// 📞 OngoingCall Providers
//
// ⭐ 수정 (받기 누른 사람 배너 안 보임 fix):
//   - inFilter('status', [...]) 제거 → 코드에서 종료 상태만 제외
//   - cStatus == 'active'면 participant status 무관 표시 (accept_call RPC가
//     'joined' 등 다른 status로 변경해도 잡힘)
//   - 2초 polling fallback (Supabase RLS + postgres_changes 이슈 우회)
//   - 첫 emit 보장 (emittedOnce 플래그)
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';

final _sb = Supabase.instance.client;

final isOnActiveCallScreenProvider = StateProvider<bool>((ref) => false);

// ════════════════════════════════════════════════════════════════
// 📞 myOngoingCallProvider
// ════════════════════════════════════════════════════════════════

final myOngoingCallProvider = StreamProvider<CallModel?>((ref) {
  final user = _sb.auth.currentUser;
  if (user == null) return Stream.value(null);

  final controller = StreamController<CallModel?>();
  String? lastEmittedSignature;
  bool emittedOnce = false;

  // 종료된 participant 상태 — 이거면 통화 진행 중이 아님
  const finishedParticipantStatuses = {'left', 'declined', 'missed'};

  Future<void> fetch() async {
    try {
      // ⭐ inFilter 제거 — 모든 참가 row 가져온 후 코드에서 필터링
      final rows = await _sb
          .from('kyorangtalk_call_participants')
          .select('status, kyorangtalk_calls!inner(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);

      Map<String, dynamic>? active;
      Map<String, dynamic>? ringing;

      for (final row in rows) {
        final call = row['kyorangtalk_calls'] as Map<String, dynamic>?;
        final pStatus = row['status'] as String?;
        if (call == null) continue;
        final cStatus = call['status'] as String?;

        // 내가 떠난/거절한/놓친 상태면 skip
        if (pStatus != null &&
            finishedParticipantStatuses.contains(pStatus)) {
          continue;
        }

        // ⭐ active call이고 내가 떠나지 않았으면 표시
        // (accepted / joined / in_call 등 모든 진행 status 허용)
        if (cStatus == 'active') {
          active = call;
          break;
        }
        // ringing은 invited 상태만 (내가 응답 전)
        if (cStatus == 'ringing' && pStatus == 'invited') {
          ringing ??= call;
        }
      }

      final picked = active ?? ringing;

      if (picked == null) {
        if (!emittedOnce || lastEmittedSignature != null) {
          lastEmittedSignature = null;
          emittedOnce = true;
          if (!controller.isClosed) controller.add(null);
        }
        return;
      }

      final model = CallModel.fromJson(picked);
      final sig = '${model.id}_${model.status.name}';
      if (!emittedOnce || sig != lastEmittedSignature) {
        lastEmittedSignature = sig;
        emittedOnce = true;
        if (!controller.isClosed) controller.add(model);
      }
    } catch (e) {
      print('🔴 [myOngoingCall] fetch 오류: $e');
    }
  }

  fetch();

  final pCh = _sb
      .channel('my_ongoing_participants_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_call_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  final cCh = _sb
      .channel('my_ongoing_calls_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_calls',
        callback: (_) => fetch(),
      )
      .subscribe();

  // ⭐ Polling fallback — Supabase RLS + postgres_changes 이슈 우회
  final pollTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => fetch(),
  );

  ref.onDispose(() {
    pollTimer.cancel();
    _sb.removeChannel(pCh);
    _sb.removeChannel(cCh);
    controller.close();
  });

  return controller.stream;
});

// ════════════════════════════════════════════════════════════════
// 🏠 roomActiveCallProvider
// ════════════════════════════════════════════════════════════════

final roomActiveCallProvider =
    StreamProvider.family.autoDispose<CallModel?, String>((ref, roomId) {
  if (roomId.isEmpty) return Stream.value(null);

  final controller = StreamController<CallModel?>();
  String? lastEmittedSignature;
  bool emittedOnce = false;

  Future<void> fetch() async {
    try {
      final rows = await _sb
          .from('kyorangtalk_calls')
          .select('*')
          .eq('source_room_id', roomId)
          .inFilter('status', ['ringing', 'active'])
          .order('started_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) {
        if (!emittedOnce || lastEmittedSignature != null) {
          lastEmittedSignature = null;
          emittedOnce = true;
          if (!controller.isClosed) controller.add(null);
        }
        return;
      }

      final model = CallModel.fromJson(rows.first as Map<String, dynamic>);
      final sig = '${model.id}_${model.status.name}';
      if (!emittedOnce || sig != lastEmittedSignature) {
        lastEmittedSignature = sig;
        emittedOnce = true;
        if (!controller.isClosed) controller.add(model);
      }
    } catch (e) {
      print('🔴 [roomActiveCall] fetch 오류: $e');
    }
  }

  fetch();

  final channel = _sb
      .channel('room_active_call_$roomId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'source_room_id',
          value: roomId,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  final pollTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => fetch(),
  );

  ref.onDispose(() {
    pollTimer.cancel();
    _sb.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ════════════════════════════════════════════════════════════════
// 👤 myParticipantStatusProvider
// ════════════════════════════════════════════════════════════════

final myParticipantStatusProvider =
    StreamProvider.family.autoDispose<CallParticipantStatus?, String>(
        (ref, callId) {
  final user = _sb.auth.currentUser;
  if (user == null || callId.isEmpty) return Stream.value(null);

  final controller = StreamController<CallParticipantStatus?>();
  CallParticipantStatus? lastEmitted;
  bool emittedOnce = false;

  Future<void> fetch() async {
    try {
      final row = await _sb
          .from('kyorangtalk_call_participants')
          .select('status')
          .eq('call_id', callId)
          .eq('user_id', user.id)
          .maybeSingle();

      final status = row == null
          ? null
          : CallParticipantStatus.fromString(row['status'] as String);

      if (!emittedOnce || status != lastEmitted) {
        emittedOnce = true;
        lastEmitted = status;
        if (!controller.isClosed) controller.add(status);
      }
    } catch (e) {
      print('🔴 [myParticipantStatus] fetch 오류: $e');
    }
  }

  fetch();

  final channel = _sb
      .channel('my_participant_${callId}_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_call_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  final pollTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => fetch(),
  );

  ref.onDispose(() {
    pollTimer.cancel();
    _sb.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});