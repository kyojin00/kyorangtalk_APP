import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../services/revenuecat_service.dart';
import '../services/subscription_service.dart';

/// ═══════════════════════════════════════════════════
/// Pro 업그레이드 페이지 (RC 결제 통합)
/// ═══════════════════════════════════════════════════
class ProUpgradeScreen extends ConsumerStatefulWidget {
  const ProUpgradeScreen({super.key});

  @override
  ConsumerState<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends ConsumerState<ProUpgradeScreen> {
  Package? _monthlyPackage;
  bool _loadingPackage = true;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _loadPackage();
  }

  Future<void> _loadPackage() async {
    final pkg = await RevenueCatService.fetchMonthlyPackage();
    if (mounted) {
      setState(() {
        _monthlyPackage = pkg;
        _loadingPackage = false;
      });
    }
  }

  String get _priceText {
    if (_monthlyPackage != null) {
      return _monthlyPackage!.storeProduct.priceString;
    }
    return '₩6,500';
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHero(context)),
                SliverToBoxAdapter(
                  child: statusAsync.when(
                    data: (status) =>
                        _buildStatusCard(context, status),
                    loading: () => const SizedBox(height: 8),
                    error: (_, __) => const SizedBox(height: 8),
                  ),
                ),
                SliverToBoxAdapter(child: _buildPriceCard(context)),
                SliverToBoxAdapter(child: _buildBenefits(context)),
                SliverToBoxAdapter(child: _buildComparison(context)),
                SliverToBoxAdapter(child: _buildRestoreButton(context)),
                SliverToBoxAdapter(child: _buildFaq(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),

            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textMain),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(context, statusAsync.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withOpacity(0.18),
            AppTheme.primary.withOpacity(0.04),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withOpacity(0.3),
              ),
            ),
            child: Text(
              '교랑톡 Pro',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'AI 기능을\n무제한으로 사용해 보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),

          Text(
            '대화 요약, 톤 코치, 추천 답장, 약속 정리,\n음성 변환을 매일 마음껏 사용할 수 있어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
      BuildContext context, SubscriptionStatus status) {
    if (status.isInTrial) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF06B6D4).withOpacity(0.15),
                const Color(0xFF06B6D4).withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF06B6D4).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  color: Color(0xFF06B6D4),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '7일 무료 체험 중',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${status.trialDaysLeft}일 남았어요. 지금 모든 AI 기능을 무제한으로 쓸 수 있어요.',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (status.isPro && !status.isInTrial) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.verified, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status.expiresAt != null
                      ? 'Pro 사용 중 (${_formatDate(status.expiresAt!)} 까지)'
                      : 'Pro 사용 중',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildPriceCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary.withOpacity(0.12),
              AppTheme.primary.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '추천',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pro 월간',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_loadingPackage)
                  SizedBox(
                    height: 32,
                    width: 100,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    _priceText,
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/ 월',
                    style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppTheme.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  '신규 가입 시 7일 무료 체험',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppTheme.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  '언제든지 해지 가능',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefits(BuildContext context) {
    final benefits = [
      _Benefit(
        icon: Icons.auto_stories_outlined,
        title: '대화 요약',
        description: '안 읽은 메시지를 AI가 한눈에 정리해줘요',
      ),
      _Benefit(
        icon: Icons.psychology_outlined,
        title: '톤 코치',
        description: '메시지 보내기 전 자동으로 톤을 점검해요',
      ),
      _Benefit(
        icon: Icons.reply_outlined,
        title: '추천 답장',
        description: 'AI가 만든 답장 후보 중에서 골라 보내세요',
      ),
      _Benefit(
        icon: Icons.event_note_outlined,
        title: '약속 정리',
        description: '대화 속 약속을 자동으로 캘린더에 모아둬요',
      ),
      _Benefit(
        icon: Icons.text_fields_outlined,
        title: '음성 변환',
        description: '음성 메시지를 텍스트로 즉시 변환해요',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pro 혜택',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...benefits.map((b) => _buildBenefitItem(b)),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(_Benefit b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(b.icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  b.title,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.description,
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparison(BuildContext context) {
    final rows = [
      ('AI 대화 요약', '하루 5회', '무제한'),
      ('AI 톤 코치', '하루 5회', '무제한'),
      ('AI 추천 답장', '하루 5회', '무제한'),
      ('AI 약속 정리', '하루 5회', '무제한'),
      ('AI 음성 변환', '하루 5회', '무제한'),
      ('일반 메시지 / 음성 / 이미지', '제한 없음', '제한 없음'),
      ('메시지 반응 (이모지)', '제한 없음', '제한 없음'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Free vs Pro',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(13),
                      topRight: Radius.circular(13),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          '기능',
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Free',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Pro',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  final isLast = i == rows.length - 1;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(
                                color: AppTheme.border,
                                width: 0.5,
                              ),
                            ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            row.$1,
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            row.$3,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestoreButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Center(
        child: TextButton.icon(
          onPressed: _purchasing ? null : _handleRestore,
          icon: Icon(Icons.refresh, color: AppTheme.textSub, size: 16),
          label: Text(
            '이전 구매 복원',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaq(BuildContext context) {
    final faqs = [
      _Faq(
        question: '7일 무료 체험은 어떻게 시작되나요?',
        answer:
            '교랑톡에 가입하시면 7일간 자동으로 Pro 모든 기능이 활성화돼요. 별도 결제 정보 없이 바로 사용할 수 있어요.',
      ),
      _Faq(
        question: '체험 후에는 어떻게 되나요?',
        answer:
            '7일이 지나면 자동으로 Free로 전환돼요. AI 기능은 하루 5회씩 사용 가능하고, 일반 채팅은 그대로 무제한이에요.',
      ),
      _Faq(
        question: '언제든지 해지할 수 있나요?',
        answer:
            '네, Google Play의 구독 관리 메뉴에서 언제든지 해지할 수 있어요. 해지해도 결제한 기간 동안은 Pro 기능을 계속 사용할 수 있어요.',
      ),
      _Faq(
        question: '일일 사용량은 언제 리셋되나요?',
        answer:
            '매일 자정(한국 시간)에 자동으로 리셋돼요. AI 기능별로 각각 5회씩이에요.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자주 묻는 질문',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...faqs.map((faq) => _FaqItem(faq: faq)),
        ],
      ),
    );
  }

  // ⭐ 결제 버튼
  Widget _buildBottomBar(
      BuildContext context, SubscriptionStatus? status) {
    final isAlreadyPro =
        status?.isPro == true && status?.isInTrial == false;
    final canPurchase = !isAlreadyPro &&
        !_loadingPackage &&
        _monthlyPackage != null &&
        !_purchasing;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
        border: Border(
          top: BorderSide(color: AppTheme.border),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      child: ElevatedButton(
        onPressed: canPurchase ? _handlePurchase : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.border,
          disabledForegroundColor: AppTheme.textSub,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _purchasing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isAlreadyPro ? Icons.verified : Icons.bolt,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isAlreadyPro
                        ? '이미 Pro 사용 중'
                        : (_loadingPackage
                            ? '상품 정보 불러오는 중...'
                            : (_monthlyPackage == null
                                ? '결제 준비 중'
                                : '$_priceText / 월 — Pro 시작하기')),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ⭐ 결제 핸들러
  // ═══════════════════════════════════════════════════
  Future<void> _handlePurchase() async {
    if (_monthlyPackage == null || _purchasing) return;

    setState(() => _purchasing = true);

    final result = await RevenueCatService.purchase(_monthlyPackage!);

    if (!mounted) return;
    setState(() => _purchasing = false);

    if (result.isSuccess) {
      _showSuccessDialog();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ref.invalidate(subscriptionStatusProvider);
          ref.invalidate(todayAiUsageProvider);
        }
      });
    } else if (result.isUserCancelled) {
      // 조용히 무시
    } else {
      _showErrorSnack(result.errorMessage ?? '결제 중 오류가 발생했어요');
    }
  }

  Future<void> _handleRestore() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);

    final result = await RevenueCatService.restorePurchases();

    if (!mounted) return;
    setState(() => _purchasing = false);

    if (result.isSuccess) {
      _showSnack('구매가 복원됐어요. Pro가 활성화됩니다');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ref.invalidate(subscriptionStatusProvider);
        }
      });
    } else if (result.isNotFound) {
      _showSnack('복원할 구매 내역이 없어요');
    } else {
      _showErrorSnack(result.errorMessage ?? '복원 중 오류가 발생했어요');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              '결제 완료',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: Text(
          '교랑톡 Pro가 활성화됐어요.\n모든 AI 기능을 무제한으로 사용해보세요!',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '확인',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }
}

class _Benefit {
  final IconData icon;
  final String title;
  final String description;

  _Benefit({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _Faq {
  final String question;
  final String answer;

  _Faq({required this.question, required this.answer});
}

class _FaqItem extends StatefulWidget {
  final _Faq faq;

  const _FaqItem({required this.faq});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.faq.question,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppTheme.textSub,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.faq.answer,
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}