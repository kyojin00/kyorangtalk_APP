import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ═══════════════════════════════════════════════════
/// 답장 톤 코치 서비스
/// ═══════════════════════════════════════════════════
class ToneCoachService {
  static final _supabase = Supabase.instance.client;
  static const _prefKeyEnabled = 'tone_coach_enabled';

  /// 사용자 설정: 자동 검사 활성화 여부 (기본 ON)
  static Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyEnabled) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, enabled);
  }

  /// 메시지 톤 분석
  static Future<ToneAnalysis> analyze({
    required String text,
    List<String>? context,
  }) async {
    print('🟢 [ToneCoach] analyze: text="$text" (${text.length}자)');

    try {
      final response = await _supabase.functions.invoke(
        'tone-coach',
        body: {
          'text': text,
          if (context != null && context.isNotEmpty) 'context': context,
        },
      );

      final data = response.data;
      if (data is! Map) {
        return ToneAnalysis.safe();
      }

      if (data['error'] != null) {
        print('🔴 [ToneCoach] 서버 에러: ${data['error']}');
        return ToneAnalysis.safe();
      }

      final analysis = ToneAnalysis(
        risk: ToneRisk.fromString(data['risk'] as String? ?? 'safe'),
        reason: data['reason'] as String? ?? '',
        suggestion: data['suggestion'] as String?,
      );

      print('🟢 [ToneCoach] 결과: risk=${analysis.risk}');
      return analysis;
    } catch (e) {
      print('🔴 [ToneCoach] 예외: $e');
      return ToneAnalysis.safe();
    }
  }
}

enum ToneRisk {
  safe,
  caution,
  warning;

  static ToneRisk fromString(String s) {
    switch (s) {
      case 'caution': return ToneRisk.caution;
      case 'warning': return ToneRisk.warning;
      default:        return ToneRisk.safe;
    }
  }

  bool get isSafe => this == ToneRisk.safe;
  bool get needsAttention => this != ToneRisk.safe;
}

class ToneAnalysis {
  final ToneRisk risk;
  final String reason;
  final String? suggestion;

  ToneAnalysis({
    required this.risk,
    required this.reason,
    this.suggestion,
  });

  factory ToneAnalysis.safe() {
    return ToneAnalysis(risk: ToneRisk.safe, reason: '');
  }

  bool get hasSuggestion =>
      suggestion != null && suggestion!.trim().isNotEmpty;
}