// ════════════════════════════════════════════════════════════════
// 📞 KyorangTalk Call Providers (Riverpod)
//
// - incomingCallProvider: 수신 중인 통화 listen (전역)
// - activeCallProvider: 현재 참여 중인 통화 상세
// - callHistoryProvider: 통화 기록 목록
//
// ⭐ 디버그 로그 추가 — 웹 통화 수신 진단용
// ════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/call_model.dart';

final _sb = Supabase.instance.client;

// ════════════════════════════════════════════════════════════════
// 🔔 incomingCallProvider
//
// 내가 참가자로 등록되어 있고 status='ringing'인 통화를 listen.
// 앱이 열려 있는 동안 들어오는 통화를 실시간 감지.
// ════════════════════════════════════════════════════════════════

final incomingCallProvider = StreamProvider<CallModel?>((ref) {
  final user = _sb.auth.currentUser;
  if (user == null) {
    print('🟡 [incomingCall] user 없음 — 스트림 시작 불가');
    return Stream.value(null);
  }

  print('🔵 [incomingCall] Provider 초기화 (user=${user.id})');

  final controller = StreamController<CallModel?>();
  String? lastEmittedId;

  Future<void> checkIncoming() async {
    try {
      print('🔵 [incomingCall] checkIncoming 호출 (user=${user.id})');

      // 내가 invited 상태인 ringing 통화 찾기
      final data = await _sb
          .from('kyorangtalk_call_participants')
          .select('call_id, status, kyorangtalk_calls!inner(*)')
          .eq('user_id', user.id)
          .eq('status', 'invited')
          .order('created_at', ascending: false)
          .limit(5);

      print('🔵 [incomingCall] participants 쿼리 결과: ${data.length}개');
      for (final row in data) {
        final call = row['kyorangtalk_calls'] as Map<String, dynamic>?;
        print('  - call=${call?['id']} status=${call?['status']}');
      }

      // 그 중에서 ringing 상태인 통화만
      Map<String, dynamic>? incoming;
      for (final row in data) {
        final call = row['kyorangtalk_calls'] as Map<String, dynamic>?;
        if (call == null) continue;
        if (call['status'] == 'ringing') {
          incoming = call;
          break;
        }
      }

      if (incoming == null) {
        print('🟡 [incomingCall] ringing 통화 없음');
        if (lastEmittedId != null) {
          lastEmittedId = null;
          if (!controller.isClosed) controller.add(null);
        }
        return;
      }

      print('🟢 [incomingCall] 수신 통화 감지: ${incoming['id']}');

      final model = CallModel.fromJson(incoming);
      if (lastEmittedId != model.id) {
        lastEmittedId = model.id;
        print('🟢 [incomingCall] 스트림에 emit: ${model.id}');
        if (!controller.isClosed) controller.add(model);
      } else {
        print('🟡 [incomingCall] 이미 emit한 통화: ${model.id}');
      }
    } catch (e) {
      print('🔴 [incomingCall] checkIncoming 오류: $e');
    }
  }

  // 초기 체크
  checkIncoming();

  // 실시간: 내 participants 행 변경 감지
  final participantsChannel = _sb
      .channel('incoming_call_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'kyorangtalk_call_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (payload) {
          print('🔔 [incomingCall] participants 변경 감지: ${payload.eventType}');
          checkIncoming();
        },
      )
      .subscribe((status, error) {
        print('🔵 [incomingCall] participants 채널 상태: $status, error=$error');
      });

  // calls 테이블 status 변경도 감지 (수락/거절 등 동기화용)
  final callsChannel = _sb
      .channel('incoming_calls_status_${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_calls',
        callback: (payload) {
          print('🔔 [incomingCall] calls UPDATE 감지');
          checkIncoming();
        },
      )
      .subscribe((status, error) {
        print('🔵 [incomingCall] calls 채널 상태: $status, error=$error');
      });

  ref.onDispose(() {
    print('🔵 [incomingCall] dispose');
    _sb.removeChannel(participantsChannel);
    _sb.removeChannel(callsChannel);
    controller.close();
  });

  return controller.stream;
});

// ════════════════════════════════════════════════════════════════
// 📞 activeCallProvider
//
// call_id로 통화 상세를 실시간 listen.
// 통화 중 화면에서 사용.
// ════════════════════════════════════════════════════════════════

final activeCallProvider =
    StreamProvider.family.autoDispose<CallModel?, String>((ref, callId) {
  final controller = StreamController<CallModel?>();

  Future<void> fetch() async {
    try {
      final data = await _sb
          .from('kyorangtalk_calls')
          .select('*')
          .eq('id', callId)
          .maybeSingle();
      if (!controller.isClosed) {
        controller.add(data != null ? CallModel.fromJson(data) : null);
      }
    } catch (e) {
      print('🔴 activeCallProvider fetch 오류: $e');
    }
  }

  fetch();

  final channel = _sb
      .channel('active_call_$callId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'kyorangtalk_calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (_) => fetch(),
      )
      .subscribe();

  ref.onDispose(() {
    _sb.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ════════════════════════════════════════════════════════════════
// 👥 callParticipantsProvider
//
// call_id의 참가자 목록을 실시간 listen.
// 그룹 통화 UI에서 누가 입장/퇴장했는지 표시할 때 사용.
// ════════════════════════════════════════════════════════════════

final callParticipantsProvider =
    StreamProvider.family.autoDispose<List<CallParticipantModel>, String>(
        (ref, callId) {
  final controller = StreamController<List<CallParticipantModel>>();

  Future<void> fetch() async {
    try {
      // 참가자 + 프로필 조인
      final data = await _sb
          .from('kyorangtalk_call_participants')
          .select('''
            *,
            kyorangtalk_profiles!inner(nickname, avatar_url)
          ''')
          .eq('call_id', callId);

      final list = (data as List).map((row) {
        final r = row as Map<String, dynamic>;
        final prof = r['kyorangtalk_profiles'] as Map<String, dynamic>?;
        return CallParticipantModel.fromJson({
          ...r,
          'nickname':   prof?['nickname'],
          'avatar_url': prof?['avatar_url'],
        });
      }).toList();

      if (!controller.isClosed) controller.add(list);
    } catch (e) {
      print('🔴 callParticipantsProvider fetch 오류: $e');
    }
  }

  fetch();

  final channel = _sb
      .channel('call_participants_$callId')
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

  ref.onDispose(() {
    _sb.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ════════════════════════════════════════════════════════════════
// 📋 callHistoryProvider
//
// 내 통화 기록 (최근 50개).
// ════════════════════════════════════════════════════════════════

final callHistoryProvider =
    FutureProvider.autoDispose<List<CallModel>>((ref) async {
  final user = _sb.auth.currentUser;
  if (user == null) return [];

  // 내가 참가한 통화 (initiator 또는 participants에 있는)
  final myCallIds = await _sb
      .from('kyorangtalk_call_participants')
      .select('call_id')
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(50);

  if (myCallIds.isEmpty) return [];

  final ids = myCallIds.map((r) => r['call_id'] as String).toList();
  final calls = await _sb
      .from('kyorangtalk_calls')
      .select('*')
      .inFilter('id', ids)
      .order('started_at', ascending: false)
      .limit(50);

  return (calls as List)
      .map((r) => CallModel.fromJson(r as Map<String, dynamic>))
      .toList();
});

// ════════════════════════════════════════════════════════════════
// 🎮 currentCallStateProvider
//
// 로컬 통화 상태 (CallService와 동기화).
// UI에서 현재 통화 ID와 미디어 상태를 가져올 때 사용.
// ════════════════════════════════════════════════════════════════

class CurrentCallState {
  final String? callId;
  final bool inCall;

  const CurrentCallState({this.callId, required this.inCall});

  factory CurrentCallState.empty() =>
      const CurrentCallState(callId: null, inCall: false);
}

final currentCallStateProvider =
    StateProvider<CurrentCallState>((ref) => CurrentCallState.empty());