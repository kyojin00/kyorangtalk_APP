import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/location_share_model.dart';
import '../services/location_share_service.dart';

// ═══════════════════════════════════════════════════
// 🗺️ LocationShareMapScreen
//
// 위치: lib/features/location/screens/location_share_map_screen.dart
//
// 한 채팅방의 모든 활성 위치 공유를 한 지도에 표시.
// 1:1 / 그룹 모두 지원 (그룹은 여러 마커).
//
// 사용
//   Navigator.push(
//     context,
//     MaterialPageRoute(
//       builder: (_) => LocationShareMapScreen(
//         roomId: 'xxx',
//         roomType: 'dm',  // or 'group'
//       ),
//     ),
//   );
// ═══════════════════════════════════════════════════

class LocationShareMapScreen extends StatefulWidget {
  final String roomId;
  final String roomType;

  /// 진입 시 포커스할 share id (선택)
  final String? focusShareId;

  const LocationShareMapScreen({
    super.key,
    required this.roomId,
    required this.roomType,
    this.focusShareId,
  });

  @override
  State<LocationShareMapScreen> createState() =>
      _LocationShareMapScreenState();
}

class _LocationShareMapScreenState
    extends State<LocationShareMapScreen> {
  final _mapController = MapController();

  /// shareId → 공유 정보
  final Map<String, LocationShareModel> _shares = {};

  /// senderId → 프로필 (avatar_url, nickname)
  final Map<String, _ProfileLite> _profiles = {};

  Position? _myPos;
  StreamSubscription<Position>? _myPosSub;
  VoidCallback? _unsubscribe;
  Timer? _ticker;
  bool _loading = true;

  String get _myId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1) 활성 공유 로드
    final shares = await LocationShareService.instance.getActiveShares(
      roomId:   widget.roomId,
      roomType: widget.roomType,
    );
    for (final s in shares) {
      _shares[s.id] = s;
    }

    // 2) 프로필 로드
    await _loadProfiles(shares.map((s) => s.senderId).toSet());

    // 3) Broadcast 구독
    _unsubscribe = LocationShareService.instance.subscribeRoom(
      widget.roomId,
      _onBroadcast,
    );

    // 4) 내 위치 가져오기
    await _initMyLocation();

    // 5) 1초마다 남은 시간 갱신
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    if (!mounted) return;
    setState(() => _loading = false);

    // 6) 초기 카메라 위치
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
  }

  Future<void> _loadProfiles(Set<String> userIds) async {
    if (userIds.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('kyorangtalk_profiles')
          .select('id, nickname, avatar_url')
          .inFilter('id', userIds.toList());

      for (final r in (rows as List)) {
        final map = Map<String, dynamic>.from(r);
        _profiles[map['id'] as String] = _ProfileLite(
          nickname:  map['nickname'] as String? ?? '',
          avatarUrl: map['avatar_url'] as String?,
        );
      }
    } catch (e) {
      debugPrint('🔴 [LocationMap] 프로필 로드 실패: $e');
    }
  }

  Future<void> _initMyLocation() async {
    final perm = await LocationShareService.instance.requestPermission();
    if (perm != LocationPermissionResult.granted) return;

    final pos =
        await LocationShareService.instance.getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() => _myPos = pos);

    // 이동 시 마커 업데이트
    _myPosSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((p) {
      if (mounted) setState(() => _myPos = p);
    }, onError: (_) {});
  }

  void _onBroadcast(LocationUpdateBroadcast update) {
    final existing = _shares[update.shareId];
    if (existing == null) {
      // 새로운 공유 (다른 사람이 방금 시작) — 다시 조회
      _reloadShare(update.shareId);
      return;
    }

    if (update.ended) {
      setState(() {
        _shares.remove(update.shareId);
      });
      return;
    }

    setState(() {
      _shares[update.shareId] = existing.copyWith(
        latitude:      update.latitude,
        longitude:     update.longitude,
        lastUpdatedAt: update.timestamp,
      );
    });
  }

  Future<void> _reloadShare(String shareId) async {
    final share =
        await LocationShareService.instance.getShareById(shareId);
    if (!mounted || share == null || !share.isActive) return;

    if (!_profiles.containsKey(share.senderId)) {
      await _loadProfiles({share.senderId});
    }

    setState(() {
      _shares[shareId] = share;
    });
  }

  // ─────────────────────────────────────────────
  // 카메라 제어
  // ─────────────────────────────────────────────

  void _fitAll() {
    final points = <LatLng>[];

    // 포커스 share가 있으면 그것만 중심으로
    if (widget.focusShareId != null) {
      final focus = _shares[widget.focusShareId];
      if (focus != null) {
        _mapController.move(
            LatLng(focus.latitude, focus.longitude), 16);
        return;
      }
    }

    for (final s in _shares.values) {
      points.add(LatLng(s.latitude, s.longitude));
    }
    if (_myPos != null) {
      points.add(LatLng(_myPos!.latitude, _myPos!.longitude));
    }

    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 16);
      return;
    }

    // bounds 계산
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(80),
      ),
    );
  }

  void _flyToMe() {
    if (_myPos == null) return;
    _mapController.move(
      LatLng(_myPos!.latitude, _myPos!.longitude),
      17,
    );
  }

  // ─────────────────────────────────────────────
  // 라이프사이클
  // ─────────────────────────────────────────────

  @override
  void dispose() {
    _ticker?.cancel();
    _unsubscribe?.call();
    _myPosSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // 지도
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(37.5665, 126.9780), // 서울 기본
                initialZoom: 14,
                minZoom: 3,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kyorang.kyorang_talk',
                ),
                MarkerLayer(
                  markers: _buildMarkers(),
                ),
              ],
            ),

            // 로딩
            if (_loading)
              Container(
                color: AppTheme.bg.withOpacity(0.8),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                  color: AppTheme.primary,
                ),
              ),

            // 상단 닫기 + 정보 카드
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _TopBar(
                count: _shares.length,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),

            // 우측 컨트롤
            Positioned(
              right: 12,
              bottom: _shares.isEmpty ? 24 : 180,
              child: Column(
                children: [
                  _ControlButton(
                    icon: Icons.center_focus_strong_rounded,
                    tooltip: '전체 보기',
                    onTap: _fitAll,
                  ),
                  const SizedBox(height: 10),
                  _ControlButton(
                    icon: Icons.my_location_rounded,
                    tooltip: '내 위치',
                    onTap: _flyToMe,
                  ),
                ],
              ),
            ),

            // 하단 사용자 리스트
            if (_shares.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: _BottomUserList(
                  shares: _shares.values.toList(),
                  profiles: _profiles,
                  myId: _myId,
                  onTapUser: (share) {
                    _mapController.move(
                      LatLng(share.latitude, share.longitude),
                      17,
                    );
                  },
                  onStop: (shareId) async {
                    await LocationShareService.instance
                        .stopShare(shareId);
                    if (mounted) {
                      setState(() => _shares.remove(shareId));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // 공유 마커들
    for (final s in _shares.values) {
      final profile = _profiles[s.senderId];
      final isMine = s.senderId == _myId;
      final color = _colorForUser(s.senderId, isMine);

      markers.add(
        Marker(
          point: LatLng(s.latitude, s.longitude),
          width: 80,
          height: 80,
          alignment: Alignment.topCenter,
          child: _UserMarker(
            color:    color,
            nickname: isMine ? '나' : (profile?.nickname ?? '...'),
            avatarUrl: profile?.avatarUrl,
          ),
        ),
      );
    }

    // 내 현재 위치 (공유 안 하고 있을 때만 별도 표시)
    final iAmSharing =
        _shares.values.any((s) => s.senderId == _myId);
    if (_myPos != null && !iAmSharing) {
      markers.add(
        Marker(
          point: LatLng(_myPos!.latitude, _myPos!.longitude),
          width: 24,
          height: 24,
          child: _MyPositionDot(),
        ),
      );
    }

    return markers;
  }

  // 사용자 ID 기반 컬러 (안정적)
  Color _colorForUser(String userId, bool isMine) {
    if (isMine) return AppTheme.primary;
    const palette = [
      Color(0xFF3B82F6), // blue
      Color(0xFF10B981), // green
      Color(0xFFF59E0B), // amber
      Color(0xFFEF4444), // red
      Color(0xFF14B8A6), // teal
      Color(0xFFEC4899), // pink
      Color(0xFF6366F1), // indigo
    ];
    final hash =
        userId.codeUnits.fold<int>(0, (acc, c) => (acc + c) % 9999);
    return palette[hash % palette.length];
  }
}

// ═══════════════════════════════════════════════════
// 상단 바
// ═══════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final int count;
  final VoidCallback onClose;

  const _TopBar({required this.count, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.close_rounded,
          onTap: onClose,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '실시간 위치',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count명 공유 중',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.15),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppTheme.textMain, size: 20),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.bgCard,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.15),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 마커 — 다른 사람
// ═══════════════════════════════════════════════════
class _UserMarker extends StatelessWidget {
  final Color color;
  final String nickname;
  final String? avatarUrl;

  const _UserMarker({
    required this.color,
    required this.nickname,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 닉네임 라벨
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            nickname,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 아바타 핀
        Container(
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: ClipOval(
            child: AvatarWidget(
              url: avatarUrl,
              name: nickname,
              size: 32,
            ),
          ),
        ),
      ],
    );
  }
}

// 내 현재 위치 (공유 안 할 때) — 파란 점
class _MyPositionDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.25),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 하단 사용자 리스트
// ═══════════════════════════════════════════════════
class _BottomUserList extends StatelessWidget {
  final List<LocationShareModel> shares;
  final Map<String, _ProfileLite> profiles;
  final String myId;
  final ValueChanged<LocationShareModel> onTapUser;
  final ValueChanged<String> onStop;

  const _BottomUserList({
    required this.shares,
    required this.profiles,
    required this.myId,
    required this.onTapUser,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in shares) ...[
              _UserRow(
                share:    s,
                profile:  profiles[s.senderId],
                isMine:   s.senderId == myId,
                onTap:    () => onTapUser(s),
                onStop:   s.senderId == myId
                    ? () => onStop(s.id)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final LocationShareModel share;
  final _ProfileLite? profile;
  final bool isMine;
  final VoidCallback onTap;
  final VoidCallback? onStop;

  const _UserRow({
    required this.share,
    required this.profile,
    required this.isMine,
    required this.onTap,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(
              url:  profile?.avatarUrl,
              name: profile?.nickname ?? '',
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMine ? '나' : (profile?.nickname ?? '...'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    share.remainingLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            if (onStop != null)
              TextButton(
                onPressed: onStop,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  backgroundColor:
                      const Color(0xFFEF4444).withOpacity(0.1),
                ),
                child: const Text(
                  '종료',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              Icon(
                Icons.location_on_rounded,
                color: AppTheme.primary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 프로필 lite
// ═══════════════════════════════════════════════════
class _ProfileLite {
  final String nickname;
  final String? avatarUrl;
  _ProfileLite({required this.nickname, required this.avatarUrl});
}