import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/tone_coach_service.dart';

/// ═══════════════════════════════════════════════════
/// 톤 코치 결과 모달
///
/// 반환값:
/// - 'send' : 그대로 보내기
/// - 'replace' : 제안된 표현으로 교체
/// - null : 취소
/// ═══════════════════════════════════════════════════
Future<String?> showToneCoachModal(
  BuildContext context, {
  required ToneAnalysis analysis,
  bool isInterceptMode = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ToneCoachModal(
      analysis: analysis,
      isInterceptMode: isInterceptMode,
    ),
  );
}

class _ToneCoachModal extends StatelessWidget {
  final ToneAnalysis analysis;
  final bool isInterceptMode;

  const _ToneCoachModal({
    required this.analysis,
    required this.isInterceptMode,
  });

  @override
  Widget build(BuildContext context) {
    final isWarning = analysis.risk == ToneRisk.warning;
    final color = isWarning
        ? const Color(0xFFEF4444)
        : const Color(0xFFD97706);
    final icon = isWarning
        ? Icons.warning_amber_rounded
        : Icons.tips_and_updates_outlined;

    final title = isInterceptMode
        ? '잠깐, 보내기 전에 한 번 더'
        : (isWarning ? '메시지 톤 경고' : '톤 코치');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

            // 헤더
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // reason
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Text(
                analysis.reason,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ),

            // suggestion
            if (analysis.hasSuggestion) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: AppTheme.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '이렇게 보내면 어떨까요?',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.10),
                      AppTheme.primary.withOpacity(0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.25),
                  ),
                ),
                child: Text(
                  analysis.suggestion!,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'send'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.border),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isInterceptMode ? '그대로 보내기' : '닫기',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, 'replace'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isInterceptMode
                            ? '부드럽게 바꿔서 보내기'
                            : '이 표현으로 바꾸기',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(
                      context, isInterceptMode ? 'send' : null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isInterceptMode ? '그대로 보내기' : '확인',
                    style:
                        const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}