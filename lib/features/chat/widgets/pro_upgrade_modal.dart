import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/pro_upgrade_screen.dart';
import '../services/subscription_service.dart';

/// ═══════════════════════════════════════════════════
/// Pro 업그레이드 모달
///
/// 한도 초과 또는 Free 사용자에게 표시
/// "Pro 업그레이드" 버튼 → ProUpgradeScreen으로 이동
/// ═══════════════════════════════════════════════════
Future<void> showProUpgradeModal(
  BuildContext context, {
  required AiFeature feature,
  UsageCheckResult? usage,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ProUpgradeSheet(
      feature: feature,
      usage: usage,
    ),
  );
}

class _ProUpgradeSheet extends StatelessWidget {
  final AiFeature feature;
  final UsageCheckResult? usage;

  const _ProUpgradeSheet({
    required this.feature,
    this.usage,
  });

  @override
  Widget build(BuildContext context) {
    final isQuotaExceeded =
        usage != null && !usage!.isPro && !usage!.allowed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 헤더 아이콘
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
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
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // 제목
            Text(
              isQuotaExceeded
                  ? '오늘의 무료 사용을 다 썼어요'
                  : 'Pro 기능을 사용해 보세요',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),

            // 부제
            Text(
              isQuotaExceeded
                  ? '${feature.label}을(를) 비롯한 모든 AI 기능을 무제한으로 사용하려면 Pro로 업그레이드하세요.'
                  : '${feature.label}을(를) 포함한 강력한 AI 기능을 무제한으로 사용할 수 있어요.',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),

            // 현재 사용량 (한도 초과 시)
            if (isQuotaExceeded) _buildUsageInfo(context),

            // Pro 혜택
            _buildBenefits(),

            const SizedBox(height: 22),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '나중에',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToProPage(context);
                    },
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text(
                      'Pro 자세히 보기',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageInfo(BuildContext context) {
    final u = usage!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: AppTheme.textSub, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${feature.label} ${u.currentCount}/${u.limit}회 사용 (내일 자정에 리셋)',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefits() {
    final benefits = [
      ('대화 요약', '읽지 못한 메시지를 한눈에'),
      ('톤 코치', '메시지 보내기 전 자동 점검'),
      ('추천 답장', 'AI가 만들어주는 답장 후보'),
      ('약속 정리', '대화 속 약속 자동 추출'),
      ('음성 변환', '음성 메시지를 텍스트로'),
    ];

    return Column(
      children: benefits.map((b) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.check,
                  color: AppTheme.primary,
                  size: 12,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.$1,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      b.$2,
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// ⭐ Pro 업그레이드 페이지로 이동
  void _navigateToProPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProUpgradeScreen()),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// 사용량 가드 헬퍼
///
/// AI 기능 호출 전에 미리 체크해서 한도 초과면 모달 표시
/// 사용 예:
///   final ok = await ensureUsageAllowed(context, AiFeature.tone);
///   if (!ok) return;
///   // 정상 호출
/// ═══════════════════════════════════════════════════
Future<bool> ensureUsageAllowed(
  BuildContext context,
  AiFeature feature,
) async {
  try {
    final result = await SubscriptionService.checkUsage(feature);
    if (result.allowed) return true;

    if (context.mounted) {
      await showProUpgradeModal(
        context,
        feature: feature,
        usage: result,
      );
    }
    return false;
  } catch (e) {
    print('🔴 [Subscription] ensureUsageAllowed 실패: $e');
    return true;
  }
}

/// ═══════════════════════════════════════════════════
/// Edge Function 응답 에러 처리
/// ═══════════════════════════════════════════════════
bool handleQuotaError(
  BuildContext context,
  Object error,
  AiFeature feature,
) {
  final errStr = error.toString().toLowerCase();
  if (errStr.contains('quota_exceeded') ||
      errStr.contains('429') ||
      errStr.contains('오늘의 무료 사용')) {
    if (context.mounted) {
      showProUpgradeModal(context, feature: feature);
    }
    return true;
  }
  return false;
}