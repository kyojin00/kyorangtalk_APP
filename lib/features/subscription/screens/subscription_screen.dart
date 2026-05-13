import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/services/revenuecat_service.dart';
import '../services/subscription_service.dart';

// ═══════════════════════════════════════════════
// 💳 구독 화면 — RevenueCat 실제 결제
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: const Text('🗄️', style: TextStyle(fontSize: 80)),
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
                          message: '결제 상품이 준비 중이에요\n잠시 후 다시 시도해주세요',
                          onRetry: () =>
                              ref.invalidate(offeringProvider),
                        );
                      }
                      return _PackagesSection(
                        offering: offering,
                        selected: _selectedPackage,
                        onSelect: (p) =>
                            setState(() => _selectedPackage = p),
                      );
                    },
                  ),

                const SizedBox(height: 24),

                if (isActive)
                  OutlinedButton(
                    onPressed: _showCancelInfo,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

                const SizedBox(height: 24),

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
              content: const Text('🎉 서랍이 열렸어요! 즐거운 추억 여행을 시작해보세요'),
              backgroundColor: AppTheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else if (result.isUserCancelled) {
        // 사용자 취소
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('결제가 취소됐어요')),
          );
        }
      } else {
        // 에러
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
          style: TextStyle(color: AppTheme.textSub, fontSize: 14, height: 1.6),
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

  @override
  Widget build(BuildContext context) {
    final monthly = offering.monthly;
    final annual = offering.annual;

    return Row(
      children: [
        if (monthly != null)
          Expanded(
            child: _PackageCard(
              package: monthly,
              label: '월간',
              subtitle: '월 단위 결제',
              isSelected: selected?.identifier == monthly.identifier,
              onTap: () => onSelect(monthly),
            ),
          ),
        if (monthly != null && annual != null)
          const SizedBox(width: 12),
        if (annual != null)
          Expanded(
            child: _PackageCard(
              package: annual,
              label: '연간',
              subtitle: '2개월 무료',
              recommended: true,
              isSelected: selected?.identifier == annual.identifier,
              onTap: () => onSelect(annual),
            ),
          ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final String label;
  final String subtitle;
  final bool isSelected;
  final bool recommended;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.15)
              : (recommended
                  ? AppTheme.primary.withOpacity(0.05)
                  : AppTheme.bgCard),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : (recommended
                    ? AppTheme.primary.withOpacity(0.5)
                    : AppTheme.border),
            width: isSelected ? 2 : (recommended ? 1.5 : 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSub,
                  ),
                ),
                if (recommended) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '인기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              package.storeProduct.priceString,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}