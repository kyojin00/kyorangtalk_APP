// lib/core/ads/ad_helper.dart
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════
// 광고 공통 모듈
//
// 위치: lib/core/ads/ad_helper.dart
//
// - AdConfig    : 노출 조건 / 광고 단위 ID 설정 (여기 숫자만 바꾸면 됨)
// - AdsInitializer : MobileAds 1회 초기화 (lazy, 시작 시간 영향 없음)
// - InlineBannerAd : 재사용 배너 위젯 (친구/채팅 리스트 공용)
//                    로드 실패 시 빈 공간으로 자동 처리
// ═══════════════════════════════════════════════

class AdConfig {
  AdConfig._();

  // ── 노출 조건 (원하는 값으로 조정) ─────────────
  /// 친구 리스트: 친구 수가 이 값 이상일 때만 하단 배너 노출
  static const int friendListMinCount = 10;

  /// 채팅 리스트: 채팅방 이 개수마다 인라인 배너 1개 삽입
  /// (너무 작게 잡으면 AdMob 정책 위반 위험 → 6 이상 권장)
  static const int chatListAdInterval = 8;

  // ── 광고 단위 ID ──────────────────────────────
  // 개발/테스트 중엔 true, 출시 빌드 전 반드시 false 로 바꾸고
  // 아래 _realBannerAndroid 에 실제 AdMob 배너 단위 ID 채워넣기
  static const bool useTestAds = false;

  // Google 공식 테스트 배너 ID (그대로 사용)
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';

  // TODO: AdMob 콘솔에서 발급받은 실제 배너 단위 ID로 교체
  static const String _realBannerAndroid =
      'ca-app-pub-7432728380552317/9553979431';

  static String get bannerUnitId =>
      useTestAds ? _testBannerAndroid : _realBannerAndroid;
}

// ═══════════════════════════════════════════════
// MobileAds 초기화 — 최초 1회만, Future 캐싱으로 중복 방지
// ═══════════════════════════════════════════════
class AdsInitializer {
  AdsInitializer._();

  static Future<InitializationStatus>? _initFuture;

  static Future<InitializationStatus> ensureInitialized() {
    return _initFuture ??= MobileAds.instance.initialize();
  }
}

// ═══════════════════════════════════════════════
// 인라인 배너 위젯
//
// - 스스로 로드/dispose 관리
// - 로드 완료 전 / 실패 시 SizedBox.shrink() (공간 차지 안 함)
// ═══════════════════════════════════════════════
class InlineBannerAd extends StatefulWidget {
  const InlineBannerAd({super.key});

  @override
  State<InlineBannerAd> createState() => _InlineBannerAdState();
}

class _InlineBannerAdState extends State<InlineBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AdsInitializer.ensureInitialized();
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _loaded = true);
          } else {
            _ad?.dispose();
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('🔴 [Ads] 배너 로드 실패: $error');
          ad.dispose();
        },
      ),
    );

    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: SizedBox(
        width: _ad!.size.width.toDouble(),
        height: _ad!.size.height.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}