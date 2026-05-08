import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/subscription_service.dart';
import 'pro_upgrade_modal.dart';
import 'summary_sheet.dart';

/// ═══════════════════════════════════════════════════
/// 채팅방 상단의 "안 읽은 메시지 N개 요약 보기" 배너
///
/// 표시 조건: 안 읽은 메시지 수가 임계치 이상일 때만
/// ═══════════════════════════════════════════════════
class SummaryBanner extends StatelessWidget {
  final String roomId;
  final bool isGroup;
  final int unreadCount;
  final VoidCallback? onDismiss;

  /// 이 개수 이상일 때만 배너 표시
  static const int threshold = 5;

  const SummaryBanner({
    super.key,
    required this.roomId,
    required this.isGroup,
    required this.unreadCount,
    this.onDismiss,
  });

  bool get shouldShow => unreadCount >= threshold;

  /// ⭐ 요약 보기 탭 - 사용량 사전 체크 후 진행
  Future<void> _handleTap(BuildContext context) async {
    final ok = await ensureUsageAllowed(context, AiFeature.summary);
    if (!ok) return;

    if (context.mounted) {
      showSummarySheet(
        context,
        roomId: roomId,
        isGroup: isGroup,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldShow) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.18),
                AppTheme.primary.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: AppTheme.primary,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '안 읽은 메시지 $unreadCount개',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'AI 요약으로 빠르게 따라잡기',
                      style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      '요약 보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios,
                        color: Colors.white, size: 9),
                  ],
                ),
              ),
              if (onDismiss != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        color: AppTheme.textSub, size: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}