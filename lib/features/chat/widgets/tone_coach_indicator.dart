import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/tone_coach_service.dart';

/// ═══════════════════════════════════════════════════
/// 입력창 위에 표시되는 톤 코치 인디케이터
///
/// 사용자가 1.5초 입력 멈추면 분석 → 결과에 따라 표시:
/// - safe: 아무것도 안 보임
/// - caution/warning: 색깔 있는 작은 칩이 입력창 위에 표시
/// ═══════════════════════════════════════════════════
class ToneCoachIndicator extends StatefulWidget {
  final TextEditingController controller;
  final List<String> recentMessages;
  final void Function(String suggestion) onApplySuggestion;

  const ToneCoachIndicator({
    super.key,
    required this.controller,
    required this.recentMessages,
    required this.onApplySuggestion,
  });

  @override
  State<ToneCoachIndicator> createState() => _ToneCoachIndicatorState();
}

class _ToneCoachIndicatorState extends State<ToneCoachIndicator> {
  Timer? _debounce;
  ToneAnalysis? _analysis;
  bool _analyzing = false;
  String _lastAnalyzedText = '';
  bool _dismissed = false;

  static const _debounceMs = 1500;
  static const _minChars = 5;

  @override
  void initState() {
    super.initState();
    print('🟡 [ToneCoach] Indicator initState');
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    print('🟡 [ToneCoach] Indicator dispose');
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text.trim();
    print('🟡 [ToneCoach] 텍스트 변경: "$text" (${text.length}자)');

    if (text.isEmpty) {
      _debounce?.cancel();
      if (_analysis != null) {
        setState(() {
          _analysis = null;
          _dismissed = false;
          _lastAnalyzedText = '';
        });
      }
      return;
    }

    if (text == _lastAnalyzedText) {
      print('🟡 [ToneCoach] 같은 텍스트, 재분석 스킵');
      return;
    }

    if (text.length < _minChars) {
      print('🟡 [ToneCoach] 짧은 텍스트(${text.length}자), 분석 안 함');
      if (_analysis != null) {
        setState(() => _analysis = null);
      }
      return;
    }

    print('🟡 [ToneCoach] 디바운스 타이머 시작 (${_debounceMs}ms)');
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: _debounceMs),
      _runAnalysis,
    );
  }

  Future<void> _runAnalysis() async {
    final text = widget.controller.text.trim();
    print('🟡 [ToneCoach] _runAnalysis 시작: "$text"');

    if (text.length < _minChars) {
      print('🟡 [ToneCoach] _runAnalysis 진입 후 짧음, 스킵');
      return;
    }
    if (_analyzing) {
      print('🟡 [ToneCoach] 이미 분석 중, 스킵');
      return;
    }

    setState(() {
      _analyzing = true;
      _dismissed = false;
    });

    final result = await ToneCoachService.analyze(
      text: text,
      context: widget.recentMessages,
    );

    if (!mounted) {
      print('🟡 [ToneCoach] 분석 완료했는데 unmounted');
      return;
    }

    if (widget.controller.text.trim() != text) {
      print('🟡 [ToneCoach] 분석 도중 텍스트 변경됨, 결과 무시');
      setState(() => _analyzing = false);
      return;
    }

    print('🟡 [ToneCoach] setState로 결과 반영: risk=${result.risk}');
    setState(() {
      _analyzing = false;
      _analysis = result;
      _lastAnalyzedText = text;
    });
  }

  void _dismiss() {
    print('🟡 [ToneCoach] 사용자가 dismiss');
    setState(() => _dismissed = true);
  }

  void _showDetails() {
    if (_analysis == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ToneCoachSheet(
        analysis: _analysis!,
        onApply: (s) {
          Navigator.pop(context);
          widget.onApplySuggestion(s);
          setState(() {
            _analysis = null;
            _lastAnalyzedText = '';
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('🟡 [ToneCoach] build: analyzing=$_analyzing, analysis=${_analysis?.risk}, dismissed=$_dismissed');

    if (_dismissed || _analysis == null || _analysis!.risk.isSafe) {
      return const SizedBox.shrink();
    }

    final risk = _analysis!.risk;
    final isWarning = risk == ToneRisk.warning;

    final bgColor = isWarning
        ? const Color(0xFFEF4444).withOpacity(0.10)
        : const Color(0xFFFBBF24).withOpacity(0.12);
    final borderColor = isWarning
        ? const Color(0xFFEF4444).withOpacity(0.35)
        : const Color(0xFFFBBF24).withOpacity(0.45);
    final iconColor =
        isWarning ? const Color(0xFFEF4444) : const Color(0xFFD97706);
    final iconData = isWarning
        ? Icons.warning_amber_rounded
        : Icons.tips_and_updates_outlined;
    final label = isWarning ? '받는 사람이 부담스러울 수 있어요' : '톤이 살짝 차가워요';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showDetails,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(iconData, color: iconColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _analysis!.hasSuggestion
                            ? '탭해서 부드러운 표현 보기'
                            : '탭해서 자세히 보기',
                        style: TextStyle(
                          color: AppTheme.textSub,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _dismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      color: AppTheme.textSub,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 톤 코치 상세 바텀시트
// ═══════════════════════════════════════════════════
class _ToneCoachSheet extends StatelessWidget {
  final ToneAnalysis analysis;
  final void Function(String suggestion) onApply;

  const _ToneCoachSheet({
    required this.analysis,
    required this.onApply,
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
                Text(
                  isWarning ? '메시지 톤 경고' : '톤 코치',
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // reason
            Text(
              analysis.reason,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),

            // suggestion
            if (analysis.hasSuggestion) ...[
              const SizedBox(height: 18),
              Text(
                '이렇게 보내면 어떨까요?',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
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
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '그대로 보낼게요',
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
                      onPressed: () => onApply(analysis.suggestion!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '이 표현으로 바꾸기',
                        style: TextStyle(fontWeight: FontWeight.w700),
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
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(fontWeight: FontWeight.w700),
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