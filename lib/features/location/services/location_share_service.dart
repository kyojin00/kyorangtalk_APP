import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/location_share_model.dart';

// ═══════════════════════════════════════════════════
// 📍 LocationShareService
//
// 위치: lib/features/location/services/location_share_service.dart
//
// 기능
// - 위치 권한 요청
// - 위치 공유 시작 (DB insert + Broadcast 시작)
// - 위치 업데이트 (5초마다 Broadcast, 30초마다 DB)
// - 위치 공유 종료 (DB update + Broadcast 종료)
// - 채팅방 Broadcast 구독 (수신 측)
//
// 싱글톤 — 동시에 여러 방에서 공유 가능
// ═══════════════════════════════════════════════════

class LocationShareService {
  LocationShareService._();
  static final LocationShareService instance = LocationShareService._();

  final _supabase = Supabase.instance.client;

  // 활성 공유들 (shareId → 컨트롤러)
  final Map<String, _ActiveShare> _activeShares = {};

  // 방 구독 (roomId → 채널)
  final Map<String, RealtimeChannel> _roomChannels = {};

  // 방 수신 리스너 (roomId → 콜백 set)
  final Map<String, Set<ValueChanged<LocationUpdateBroadcast>>>
      _roomListeners = {};

  // ─────────────────────────────────────────────
  // 권한
  // ─────────────────────────────────────────────

  /// 위치 권한 요청 + 현재 상태 반환
  Future<LocationPermissionResult> requestPermission() async {
    // 1. 위치 서비스 켜져 있는지
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    // 2. 권한 상태
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionResult.denied;
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }

    return LocationPermissionResult.granted;
  }

  /// 현재 위치 한 번만 가져오기
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('🔴 [LocationShare] getCurrentPosition 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 시작
  // ─────────────────────────────────────────────

  /// 위치 공유 시작.
  /// 성공 시 LocationShareModel 반환, 실패 시 null.
  ///
  /// [durationMinutes] — 공유할 시간 (15, 60, 120 등)
  /// [roomType] — 'dm' | 'group'
  Future<LocationShareModel?> startShare({
    required String roomId,
    required String roomType,
    required int durationMinutes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    // 권한 확인
    final perm = await requestPermission();
    if (perm != LocationPermissionResult.granted) {
      debugPrint('🔴 [LocationShare] 권한 거부: $perm');
      return null;
    }

    // 현재 위치
    final pos = await getCurrentPosition();
    if (pos == null) return null;

    final expiresAt = DateTime.now()
        .add(Duration(minutes: durationMinutes))
        .toUtc();

    try {
      // DB insert
      final inserted = await _supabase
          .from('kyorangtalk_location_shares')
          .insert({
            'room_id':    roomId,
            'room_type':  roomType,
            'sender_id':  user.id,
            'latitude':   pos.latitude,
            'longitude':  pos.longitude,
            'expires_at': expiresAt.toIso8601String(),
          })
          .select()
          .single();

      final share = LocationShareModel.fromJson(inserted);
      debugPrint('🟢 [LocationShare] 시작: ${share.id}');

      // 활성 공유 등록 + 위치 스트림 시작
      _startStreaming(share);

      return share;
    } catch (e) {
      debugPrint('🔴 [LocationShare] 시작 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 스트리밍 (시작 후)
  // ─────────────────────────────────────────────

  void _startStreaming(LocationShareModel share) {
    final active = _ActiveShare(share);
    _activeShares[share.id] = active;

    // 위치 스트림 (5미터 이상 이동 시 업데이트)
    active.posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (pos) => _onPosition(active, pos),
      onError: (e) {
        debugPrint('🔴 [LocationShare] 스트림 오류: $e');
      },
    );

    // 만료 자동 종료 타이머
    final remainingMs =
        share.expiresAt.difference(DateTime.now()).inMilliseconds;
    if (remainingMs > 0) {
      active.expireTimer = Timer(Duration(milliseconds: remainingMs), () {
        debugPrint('⏰ [LocationShare] 만료 자동 종료: ${share.id}');
        stopShare(share.id);
      });
    }
  }

  Future<void> _onPosition(_ActiveShare active, Position pos) async {
    final share = active.share;

    // Broadcast (실시간, 매번)
    await _broadcastUpdate(
      roomId:   share.roomId,
      payload: LocationUpdateBroadcast(
        shareId:   share.id,
        senderId:  share.senderId,
        latitude:  pos.latitude,
        longitude: pos.longitude,
        ended:     false,
        timestamp: DateTime.now(),
      ),
    );

    // DB UPDATE (30초마다 한 번)
    final now = DateTime.now();
    if (now.difference(active.lastDbSyncAt).inSeconds >= 30) {
      active.lastDbSyncAt = now;
      try {
        await _supabase
            .from('kyorangtalk_location_shares')
            .update({
              'latitude':         pos.latitude,
              'longitude':        pos.longitude,
              'last_updated_at':  now.toUtc().toIso8601String(),
            })
            .eq('id', share.id);
      } catch (e) {
        debugPrint('🔴 [LocationShare] DB sync 실패: $e');
      }
    }
  }

  // ─────────────────────────────────────────────
  // 종료
  // ─────────────────────────────────────────────

  Future<void> stopShare(String shareId) async {
    final active = _activeShares[shareId];
    if (active == null) return;

    final share = active.share;
    debugPrint('🔵 [LocationShare] 종료: $shareId');

    // 스트림/타이머 정리
    await active.posSub?.cancel();
    active.expireTimer?.cancel();
    _activeShares.remove(shareId);

    // DB UPDATE (ended_at)
    try {
      await _supabase
          .from('kyorangtalk_location_shares')
          .update({'ended_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', shareId);
    } catch (e) {
      debugPrint('🔴 [LocationShare] 종료 DB 실패: $e');
    }

    // 종료 Broadcast
    await _broadcastUpdate(
      roomId: share.roomId,
      payload: LocationUpdateBroadcast(
        shareId:   shareId,
        senderId:  share.senderId,
        latitude:  share.latitude,
        longitude: share.longitude,
        ended:     true,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// 내가 보낸 활성 공유 목록 (방별로 1개만 일반적)
  List<LocationShareModel> getMyActiveShares(String roomId) {
    return _activeShares.values
        .where((a) => a.share.roomId == roomId)
        .map((a) => a.share)
        .toList();
  }

  bool isMySharing(String roomId) {
    return _activeShares.values.any((a) => a.share.roomId == roomId);
  }

  // ─────────────────────────────────────────────
  // Broadcast 송수신
  // ─────────────────────────────────────────────

  static String _channelName(String roomId) => 'location:$roomId';
  static const String _eventName = 'location_update';

  Future<void> _broadcastUpdate({
    required String roomId,
    required LocationUpdateBroadcast payload,
  }) async {
    final ch = _ensureChannel(roomId);
    try {
      await ch.sendBroadcastMessage(
        event:   _eventName,
        payload: payload.toJson(),
      );
    } catch (e) {
      debugPrint('🔴 [LocationShare] broadcast 실패: $e');
    }
  }

  RealtimeChannel _ensureChannel(String roomId) {
    final existing = _roomChannels[roomId];
    if (existing != null) return existing;

    final ch = _supabase
        .channel(_channelName(roomId))
        .onBroadcast(
          event: _eventName,
          callback: (payload) {
            try {
              final update = LocationUpdateBroadcast.fromJson(
                Map<String, dynamic>.from(payload),
              );
              final listeners = _roomListeners[roomId];
              if (listeners != null) {
                for (final fn in listeners) {
                  fn(update);
                }
              }
            } catch (e) {
              debugPrint(
                  '🔴 [LocationShare] broadcast 파싱 실패: $e payload=$payload');
            }
          },
        );

    ch.subscribe();
    _roomChannels[roomId] = ch;
    debugPrint('🟢 [LocationShare] 채널 구독: $roomId');
    return ch;
  }

  /// 방의 위치 업데이트 구독.
  /// 반환된 dispose 함수 호출 시 해제.
  VoidCallback subscribeRoom(
    String roomId,
    ValueChanged<LocationUpdateBroadcast> onUpdate,
  ) {
    _ensureChannel(roomId);
    final listeners = _roomListeners.putIfAbsent(roomId, () => {});
    listeners.add(onUpdate);

    return () {
      listeners.remove(onUpdate);
      if (listeners.isEmpty) {
        _roomListeners.remove(roomId);
        // 채널은 유지 (다른 listener가 다시 붙을 수 있음)
      }
    };
  }

  // ─────────────────────────────────────────────
  // 활성 공유 조회 (채팅방 재진입 시)
  // ─────────────────────────────────────────────

  Future<List<LocationShareModel>> getActiveShares({
    required String roomId,
    required String roomType,
  }) async {
    try {
      final rows = await _supabase
          .from('kyorangtalk_location_shares')
          .select()
          .eq('room_id', roomId)
          .eq('room_type', roomType)
          .filter('ended_at', 'is', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());

      return (rows as List)
          .map((r) => LocationShareModel.fromJson(
              Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('🔴 [LocationShare] getActiveShares 실패: $e');
      return [];
    }
  }

  Future<LocationShareModel?> getShareById(String shareId) async {
    try {
      final row = await _supabase
          .from('kyorangtalk_location_shares')
          .select()
          .eq('id', shareId)
          .maybeSingle();
      if (row == null) return null;
      return LocationShareModel.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('🔴 [LocationShare] getShareById 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 정리
  // ─────────────────────────────────────────────

  /// 채팅방 나갈 때 호출 (해당 방 채널만 정리, 본인 공유는 유지)
  Future<void> unsubscribeRoom(String roomId) async {
    final ch = _roomChannels.remove(roomId);
    if (ch != null) {
      try {
        await _supabase.removeChannel(ch);
      } catch (_) {}
    }
    _roomListeners.remove(roomId);
  }

  /// 전체 정리 (로그아웃 등)
  Future<void> disposeAll() async {
    for (final shareId in _activeShares.keys.toList()) {
      await stopShare(shareId);
    }
    for (final ch in _roomChannels.values.toList()) {
      try {
        await _supabase.removeChannel(ch);
      } catch (_) {}
    }
    _roomChannels.clear();
    _roomListeners.clear();
  }
}

// ═══════════════════════════════════════════════════
// 내부: 활성 공유 트래킹
// ═══════════════════════════════════════════════════

class _ActiveShare {
  LocationShareModel share;
  StreamSubscription<Position>? posSub;
  Timer? expireTimer;
  DateTime lastDbSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  _ActiveShare(this.share);
}

// ═══════════════════════════════════════════════════
// 권한 결과 enum
// ═══════════════════════════════════════════════════

enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}