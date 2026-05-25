import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/services/revenuecat_service.dart';
import '../services/subscription_service.dart';

// ═══════════════════════════════════════════════
// 💳 메시지 서랍 구독 화면 — RevenueCat 결제
//
// 위치: lib/features/subscription/screens/subscription_screen.dart
// ═══════════════════════════════════════════════

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState
    extends ConsumerState<SubscriptionScreen> {
  Package? _selectedPackage;
  bool _isPurchasing = false;
  bool _autoSelected = false; // 최초 1회 자동 선택 가드

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(subscriptionProvider);
    final offeringAsync = ref.watch(offeringProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '메시지 서랍',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _restorePurchases,
            child: Text(
              '복원',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: subAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (e, _) => Center(
          child: Text('오류: $e',
              style: TextStyle(color: AppTheme.textSub)),
        ),
        data: (sub) {
          final isActive = sub?.isActive ?? false;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── 헤더 일러스트 ─────────────────────
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.3),
                        AppTheme.primary.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child:
                      const Text('🗄️', style: TextStyle(fontSize: 80)),
                ),

                const SizedBox(height: 28),

                Text(
                  '잊지 마세요,\n소중한 대화는 서랍 속에',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  '나간 채팅방의 옛 메시지를 다시 보고 싶을 때,\n'
                  '메시지 서랍을 열어보세요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSub,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 28),

                if (isActive && sub != null)
                  _ActiveStatusCard(subscription: sub)
                else
                  _BenefitsCard(),

                const SizedBox(height: 24),

                // ─── 결제 패키지 선택 ────────────────────
                if (!isActive)
                  offeringAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary),
                      ),
                    ),
                    error: (e, _) => _ErrorState(
                      message: '결제 정보 로드 실패\n$e',
                      onRetry: () => ref.invalidate(offeringProvider),
                    ),
                    data: (offering) {
                      if (offering == null ||
                          offering.availablePackages.isEmpty) {
                        return _ErrorState(
                          message:
                              '결제 상품이 준비 중이에요\n잠시 후 다시 시도해주세요',
                          onRetry: () =>
                              ref.invalidate(offeringProvider),
                        );
                      }

                      // 최초 진입 시 연간(추천)을 기본 선택
                      if (!_autoSelected && _selectedPackage == null) {
                        _autoSelected = true;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _selectedPackage = offering.annual ??
                                  offering.monthly;
                            });
                          }
                        });
                      }

                      return _PackagesSection(
                        offering: offering,
                        selected: _selectedPackage,
                        onSelect: (p) =>
                            setState(() => _selectedPackage = p),
                      );
                    },
                  ),

                const SizedBox(height: 18),

                // ─── 신뢰 포인트 ─────────────────────────
                if (!isActive) ...[
                  _TrustPoint(text: '언제든지 해지 가능'),
                  const SizedBox(height: 6),
                  _TrustPoint(text: '7일 이내 미사용 시 100% 환불'),
                  const SizedBox(height: 6),
                  _TrustPoint(text: '자동 갱신 직후 48시간 이내 100% 환불'),
                  const SizedBox(height: 24),
                ],

                // ─── 결제 / 관리 버튼 ────────────────────
                if (isActive)
                  OutlinedButton(
                    onPressed: _showCancelInfo,
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      '구독 관리',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed:
                        (_selectedPackage == null || _isPurchasing)
                            ? null
                            : _purchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.border,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isPurchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _selectedPackage == null
                                ? '구독 옵션을 선택해주세요'
                                : '서랍 열기',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),

                const SizedBox(height: 28),

                // ─── 자주 묻는 질문 ──────────────────────
                _FaqSection(),

                const SizedBox(height: 24),

                // ─── 결제 안내 ─────────────────────────
                Text(
                  '• 구독은 자동 갱신됩니다.\n'
                  '• 갱신 24시간 전까지 언제든지 취소할 수 있습니다.\n'
                  '• 구독 취소는 Google Play에서 진행됩니다.\n'
                  '• 다른 기기에서도 같은 계정으로 이용 가능합니다.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _purchase() async {
    if (_selectedPackage == null) return;
    setState(() => _isPurchasing = true);

    try {
      final result =
          await SubscriptionService.purchasePackage(_selectedPackage!);

      if (!mounted) return;

      if (result.isSuccess) {
        // 결제 성공 — webhook으로 Supabase 동기화 대기
        await Future.delayed(const Duration(seconds: 2));
        ref.invalidate(subscriptionProvider);
        ref.invalidate(hasActiveSubscriptionProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('🎉 서랍이 열렸어요! 즐거운 추억 여행을 시작해보세요'),
              backgroundColor: AppTheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else if (result.isUserCancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('결제가 취소됐어요')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.errorMessage ?? '결제 실패')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('결제 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restorePurchases() async {
    try {
      final result = await SubscriptionService.restorePurchases();
      if (!mounted) return;

      if (result.isSuccess) {
        await Future.delayed(const Duration(seconds: 2));
        ref.invalidate(subscriptionProvider);
        ref.invalidate(hasActiveSubscriptionProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('구독을 복원했어요'),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (result.isNotFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원할 구독이 없어요')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? '복원 실패')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원 실패: $e')),
        );
      }
    }
  }

  void _showCancelInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          '구독 취소 안내',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '구독은 Google Play에서 직접 취소하실 수 있어요.\n\n'
          'Google Play 앱 → 메뉴 → 결제 및 정기결제\n'
          '→ 정기결제에서 메시지 서랍 선택 → 취소',
          style: TextStyle(
              color: AppTheme.textSub, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('확인',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 신뢰 포인트 한 줄
// ═══════════════════════════════════════════════
class _TrustPoint extends StatelessWidget {
  final String text;
  const _TrustPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: AppTheme.primary, size: 14),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// 활성 상태 카드
// ═══════════════════════════════════════════════
class _ActiveStatusCard extends StatelessWidget {
  final SubscriptionModel subscription;
  const _ActiveStatusCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                '서랍이 열려있어요',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
              if (subscription.isTest) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'TEST',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${subscription.daysRemaining}일 남음',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '만료일: ${_formatDate(subscription.expiresAt)}',
            style: TextStyle(fontSize: 12, color: AppTheme.textSub),
          ),
          if (subscription.isCancelled) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '취소됨 · 만료일까지 이용 가능',
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════
// 혜택 카드
// ═══════════════════════════════════════════════
class _BenefitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final benefits = [
      ('📜', '나간 모든 채팅방의 옛 메시지 복원'),
      ('♾', '메시지 보관 무제한'),
      ('🔒', '비공개 보관 — 나만 볼 수 있어요'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '서랍에서 무엇을 할 수 있나요?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 16),
          ...benefits.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        b.$2,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMain,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 에러 상태
// ═══════════════════════════════════════════════
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline,
              color: AppTheme.textSub, size: 32),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSub,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text('다시 시도',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 패키지 선택
// ═══════════════════════════════════════════════
class _PackagesSection extends StatelessWidget {
  final Offering offering;
  final Package? selected;
  final ValueChanged<Package> onSelect;

  const _PackagesSection({
    required this.offering,
    required this.selected,
    required this.onSelect,
  });

  /// 월간 대비 연간 할인율 (자동 계산)
  int? _calcDiscount() {
    final m = offering.monthly;
    final a = offering.annual;
    if (m == null || a == null) return null;
    final monthlyTotal = m.storeProduct.price * 12;
    if (monthlyTotal <= 0) return null;
    final discount =
        ((monthlyTotal - a.storeProduct.price) / monthlyTotal) * 100;
    if (discount <= 0) return null;
    return discount.round();
  }

  /// 연간 → 월 환산 가격 텍스트
  String _annualMonthlyEquiv() {
    final a = offering.annual;
    if (a == null) return '';
    final perMonth = (a.storeProduct.price / 12).round();
    final fullStr = a.storeProduct.priceString;
    final currencyMatch = RegExp(r'^[^\d]+').firstMatch(fullStr);
    final currency = (currencyMatch?.group(0) ?? '').trim();
    final formatted = perMonth.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return '$currency$formatted';
  }

  @override
  Widget build(BuildContext context) {
    final monthly = offering.monthly;
    final annual = offering.annual;
    final discount = _calcDiscount();
    final monthlyEquiv = _annualMonthlyEquiv();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (annual != null)
            Expanded(
              child: _PackageCard(
                package: annual,
                label: '연간',
                subtitle: monthlyEquiv.isEmpty
                    ? '연 1회 결제'
                    : '월 $monthlyEquiv 꼴',
                badge: discount != null && discount > 0
                    ? '$discount% 절약'
                    : '인기',
                periodSuffix: '/ 년',
                recommended: true,
                isSelected:
                    selected?.identifier == annual.identifier,
                onTap: () => onSelect(annual),
              ),
            ),
          if (monthly != null && annual != null)
            const SizedBox(width: 10),
          if (monthly != null)
            Expanded(
              child: _PackageCard(
                package: monthly,
                label: '월간',
                subtitle: '매월 자동 갱신',
                periodSuffix: '/ 월',
                isSelected:
                    selected?.identifier == monthly.identifier,
                onTap: () => onSelect(monthly),
              ),
            ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final String label;
  final String subtitle;
  final String? badge;
  final String periodSuffix;
  final bool isSelected;
  final bool recommended;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.label,
    required this.subtitle,
    required this.periodSuffix,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary.withOpacity(0.18),
                      AppTheme.primary.withOpacity(0.05),
                    ],
                  )
                : null,
            color: isSelected ? null : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primary
                  : (recommended
                      ? AppTheme.primary.withOpacity(0.4)
                      : AppTheme.border),
              width: isSelected ? 2 : (recommended ? 1.5 : 1),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                package.storeProduct.priceString,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMain,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                periodSuffix,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// FAQ
// ═══════════════════════════════════════════════
class _FaqSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final faqs = [
      (
        '메시지 서랍이 뭐예요?',
        '나간 채팅방의 메시지를 안전하게 보관해주는 기능이에요. '
            '구독 중이면 언제든지 옛 대화를 다시 불러올 수 있어요.'
      ),
      (
        '월간과 연간 중에 뭘 선택해야 하나요?',
        '연간 결제는 1년치를 한 번에 결제하는 대신 월간 대비 더 저렴해요. '
            '길게 쓰실 계획이라면 연간이, 우선 짧게 써보고 싶으시면 월간이 적합해요.'
      ),
      (
        '언제든지 해지할 수 있나요?',
        '네, Google Play의 정기 결제 메뉴에서 언제든지 해지할 수 있어요. '
            '해지해도 결제한 기간 동안은 서랍을 계속 이용할 수 있어요.'
      ),
      (
        '환불은 어떻게 받을 수 있나요?',
        '결제 후 7일 이내 + 거의 사용하지 않으셨다면 100% 환불해드려요.\n\n'
            '자동 갱신 직후 48시간 이내라면 실수 갱신 보호 차원에서 100% 환불해드려요.\n\n'
            '장기 사용 후엔 사용 기간을 제외한 부분 환불이 가능할 수 있어요.\n\n'
            '환불 신청은 Play 스토어 → 결제 및 정기 결제 → 예산 및 내역에서 직접 진행하시거나 '
            '문의하기로 연락 주세요.'
      ),
      (
        '실수로 자동 갱신됐어요',
        '갱신 후 48시간 이내라면 100% 환불해드려요. '
            '갱신 알림을 놓치셨거나 실수로 결제된 경우 안심하고 문의해 주세요.'
      ),
      (
        '구독을 해지하면 서랍의 메시지는 어떻게 되나요?',
        '구독이 만료되면 서랍이 잠겨서 옛 메시지에 접근할 수 없지만, '
            '메시지는 안전하게 보관돼요. 다시 구독하시면 모두 그대로 볼 수 있어요.'
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(Icons.help_outline,
                    size: 16, color: AppTheme.textSub),
                const SizedBox(width: 6),
                Text(
                  '자주 묻는 질문',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          ...faqs.map((f) => _FaqItem(question: f.$1, answer: f.$2)),
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 0.5,
          color: AppTheme.border,
        ),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration:
                          const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: AppTheme.textSub,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (_expanded)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 8, right: 24),
                    child: Text(
                      widget.answer,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSub,
                        height: 1.6,
                      ),
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