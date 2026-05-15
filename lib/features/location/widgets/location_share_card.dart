import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../models/location_share_model.dart';
import '../services/location_share_service.dart';

// ═══════════════════════════════════════════════════
// 📍 LocationShareCard
//
// 위치: lib/features/location/widgets/location_share_card.dart
//
// 메시지 버블 내부에 들어가는 위치 공유 카드.
//
// 사용
//   LocationShareCard(
//     shareId: msg.locationShareId!,
//     onTap: () => 풀스크린 지도 열기,
//   )
//
// 자동으로
//   1) DB에서 현재 share 정보 조회
//   2) 실시간 Broadcast 구독 (위치/종료 업데이트)
//   3) 1초마다 남은 시간 갱신
// ═══════════════════════════════════════════════════

class LocationShareCard extends StatefulWidget {
  final String shareId;
  final VoidCallback? onTap;
  final VoidCallback? onStop;

  /// 버블 폭 제한용 (선택)
  final double? maxWidth;

  const LocationShareCard({
    super.key,
    required this.shareId,
    this.onTap,
    this.onStop,
    this.maxWidth,
  });

  @override
  State<LocationShareCard> createState() => _LocationShareCardState();
}

class _LocationShareCardState extends State<LocationShareCard> {
  LocationShareModel? _share;
  bool _loading = true;
  Timer? _ticker;
  VoidCallback? _unsubscribe;

  String get _myId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  bool get _isMine => _share?.senderId == _myId;

  @override
  void initState() {
    super.initState();
    _load();
    // 1초마다 남은 시간 갱신
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _unsubscribe?.call();
    super.dispose();
  }

  Future<void> _load() async {
    final share = await LocationShareService.instance
        .getShareById(widget.shareId);
    if (!mounted) return;

    setState(() {
      _share = share;
      _loading = false;
    });

    // 활성 상태면 Broadcast 구독
    if (share != null && share.isActive) {
      _unsubscribe = LocationShareService.instance.subscribeRoom(
        share.roomId,
        _onBroadcast,
      );
    }
  }

  void _onBroadcast(LocationUpdateBroadcast update) {
    if (update.shareId != widget.shareId) return;
    if (!mounted || _share == null) return;

    if (update.ended) {
      setState(() {
        _share = _share!.copyWith(endedAt: DateTime.now());
      });
      _unsubscribe?.call();
      _unsubscribe = null;
    } else {
      setState(() {
        _share = _share!.copyWith(
          latitude:      update.latitude,
          longitude:     update.longitude,
          lastUpdatedAt: update.timestamp,
        );
      });
    }
  }

  Future<void> _onStop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '위치 공유 종료',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          '실시간 위치 공유를 종료할까요?',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '종료',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await LocationShareService.instance.stopShare(widget.shareId);
    widget.onStop?.call();
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(
        child: const SizedBox(
          height: 180,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    if (_share == null) {
      return _shell(
        child: _stateText('위치 공유를 불러올 수 없어요'),
      );
    }

    return _shell(
      onTap: widget.onTap,
      child: Column(
        children: [
          _MapPreview(
            share: _share!,
            active: _share!.isActive,
          ),
          _InfoRow(
            share:    _share!,
            isMine:   _isMine,
            onStop:   _isMine && _share!.isActive ? _onStop : null,
          ),
        ],
      ),
    );
  }

  // 카드 껍데기 (테두리 + 라운드)
  Widget _shell({required Widget child, VoidCallback? onTap}) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth ?? 260,
      ),
      child: Material(
        color: AppTheme.bgCard,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  Widget _stateText(String msg) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        msg,
        style: TextStyle(
          color: AppTheme.textSub,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 지도 미리보기
// ═══════════════════════════════════════════════════
class _MapPreview extends StatelessWidget {
  final LocationShareModel share;
  final bool active;

  const _MapPreview({required this.share, required this.active});

  @override
  Widget build(BuildContext context) {
    final point = LatLng(share.latitude, share.longitude);

    return SizedBox(
      height: 160,
      child: Stack(
        children: [
          // 지도
          AbsorbPointer(
            absorbing: true, // 미리보기라서 스크롤 막음 (탭은 외부 InkWell)
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kyorang.kyorang_talk',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: _Pin(active: active),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 비활성 시 회색 오버레이
          if (!active)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '공유 종료됨',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          // 좌상단 LIVE 뱃지
          if (active)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final bool active;
  const _Pin({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.primary : AppTheme.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const Icon(
          Icons.arrow_drop_down,
          color: Colors.white,
          size: 14,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 하단 정보 + 종료 버튼
// ═══════════════════════════════════════════════════
class _InfoRow extends StatelessWidget {
  final LocationShareModel share;
  final bool isMine;
  final VoidCallback? onStop;

  const _InfoRow({
    required this.share,
    required this.isMine,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final active = share.isActive;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.location_on_rounded
                : Icons.location_off_rounded,
            color: active ? AppTheme.primary : AppTheme.textMuted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active
                      ? (isMine ? '내 위치 공유 중' : '실시간 위치 공유')
                      : '위치 공유 종료',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  active
                      ? share.remainingLabel
                      : '공유가 종료됐어요',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSub,
                  ),
                ),
              ],
            ),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onStop,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
            ),
          ],
        ],
      ),
    );
  }
}