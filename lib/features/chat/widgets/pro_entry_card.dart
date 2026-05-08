import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/pro_upgrade_screen.dart';
import '../services/subscription_service.dart';

/// ═══════════════════════════════════════════════════
/// Pro 업그레이드 진입 카드 (마이페이지/설정용)
///
/// 사용 예 (마이페이지 어딘가에 한 줄로 추가):
///   const ProEntryCard(),
///
/// 동작:
/// - Free 사용자: "Pro 업그레이드" 카드 표시 (그라디언트)
/// - 7일 체험 중: "체험 중 - X일 남음" 표시 + 페이지로 이동 가능
/// - 이미 Pro: "Pro 사용 중" 표시 + 페이지로 이동 가능
/// ═══════════════════════════════════════════════════
class ProEntryCard extends ConsumerWidget {
  /// 카드 외부 패딩 (기본: 좌우 16, 위아래 8)
  final EdgeInsetsGeometry padding;

  const ProEntryCard({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(subscriptionStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        return Padding(
          padding: padding,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _navigateToPro(context),
              borderRadius: BorderRadius.circular(16),
              child: _buildCard(status),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(SubscriptionStatus status) {
    if (status.isInTrial) {
      return _buildTrialCard(status);
    }
    if (status.isPro) {
      return _buildActiveCard(status);
    }
    return _buildUpgradeCard();
  }

  // ═══════════════════════════════════════════════════
  // Free 사용자 - 업그레이드 유도 (그라디언트)
  // ═══════════════════════════════════════════════════
  Widget _buildUpgradeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '교랑톡 Pro 업그레이드',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'AI 기능 무제한 + 7일 무료 체험',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Colors.white,
            size: 22,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 체험 중 - 시안색
  // ═══════════════════════════════════════════════════
  Widget _buildTrialCard(SubscriptionStatus status) {
    const trialColor = Color(0xFF06B6D4);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: trialColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: trialColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.card_giftcard,
              color: trialColor,
              size: 20,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.trialDaysLeft}일 남았어요. 자세히 보기 →',
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppTheme.textSub,
            size: 20,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 이미 Pro 사용 중 - 보라색
  // ═══════════════════════════════════════════════════
  Widget _buildActiveCard(SubscriptionStatus status) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
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
            child: Icon(
              Icons.verified,
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '교랑톡 Pro',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '활성',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  status.expiresAt != null
                      ? '${_formatDate(status.expiresAt!)} 까지 사용 가능'
                      : 'AI 기능 무제한 사용 중',
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppTheme.textSub,
            size: 20,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  void _navigateToPro(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Pro 업그레이드 메뉴 ListTile (단순 진입용)
///
/// 카드보다 작은 형태로 설정 메뉴 안에 넣고 싶을 때 사용.
///
/// 사용 예:
///   const ProEntryListTile(),
/// ═══════════════════════════════════════════════════
class ProEntryListTile extends ConsumerWidget {
  const ProEntryListTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(subscriptionStatusProvider);

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        final String title;
        final String subtitle;
        final Color iconBg;
        final IconData icon;

        if (status.isInTrial) {
          title = '교랑톡 Pro';
          subtitle = '체험 중 · ${status.trialDaysLeft}일 남음';
          iconBg = const Color(0xFF06B6D4);
          icon = Icons.card_giftcard;
        } else if (status.isPro) {
          title = '교랑톡 Pro';
          subtitle = status.expiresAt != null
              ? '${_formatDate(status.expiresAt!)} 까지'
              : '사용 중';
          iconBg = AppTheme.primary;
          icon = Icons.verified;
        } else {
          title = 'Pro 업그레이드';
          subtitle = 'AI 기능 무제한';
          iconBg = AppTheme.primary;
          icon = Icons.auto_awesome;
        }

        return ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProUpgradeScreen(),
              ),
            );
          },
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconBg, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: AppTheme.textSub,
            size: 20,
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
}