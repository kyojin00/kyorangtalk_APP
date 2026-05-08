import 'package:supabase_flutter/supabase_flutter.dart';

/// ═══════════════════════════════════════════════════
/// 1-Tap 공감 답장 (Smart Reply) 서비스
/// ═══════════════════════════════════════════════════
class SmartReplyService {
  static final _supabase = Supabase.instance.client;

  /// 답장 후보 생성
  /// 한도 초과 시 SmartReplyResult.quotaExceeded() 반환
  static Future<SmartReplyResult> generate({
    required String roomId,
    required bool isGroup,
    required String lastMessageId,
    required String lastMessageText,
    required String senderName,
    List<String>? context,
  }) async {
    print('🎀 [SmartReply] generate: msgId=$lastMessageId');

    try {
      final response = await _supabase.functions.invoke(
        'smart-reply',
        body: {
          'roomId': roomId,
          'roomType': isGroup ? 'group' : 'dm',
          'lastMessageId': lastMessageId,
          'lastMessageText': lastMessageText,
          'senderName': senderName,
          if (context != null && context.isNotEmpty) 'context': context,
        },
      );

      final data = response.data;
      if (data is! Map) return SmartReplyResult.empty();

      // ⭐ 한도 초과 체크
      if (data['error'] == 'quota_exceeded') {
        print('⛔ [SmartReply] 한도 초과');
        return SmartReplyResult.quotaExceeded();
      }

      if (data['error'] != null) {
        print('🔴 [SmartReply] 서버 에러: ${data['error']}');
        return SmartReplyResult.empty();
      }

      final raw = data['suggestions'] as List?;
      if (raw == null) return SmartReplyResult.empty();

      final result = raw
          .whereType<Map>()
          .map((m) => SmartReplySuggestion(
                label: m['label']?.toString() ?? '',
                text: m['text']?.toString() ?? '',
              ))
          .where((s) => s.text.isNotEmpty)
          .toList();

      print('🎀 [SmartReply] ${result.length}개 후보 (cached=${data['cached']})');
      return SmartReplyResult(suggestions: result);
    } catch (e) {
      // ⭐ FunctionException에서 429 잡기
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('quota_exceeded') || errStr.contains('429')) {
        print('⛔ [SmartReply] 한도 초과 (catch)');
        return SmartReplyResult.quotaExceeded();
      }

      print('🔴 [SmartReply] 예외: $e');
      return SmartReplyResult.empty();
    }
  }
}

class SmartReplySuggestion {
  final String label; // '공감하기' / '위로하기' / '가볍게' 등
  final String text;

  SmartReplySuggestion({required this.label, required this.text});
}

/// ⭐ 결과를 wrapping해서 quota 정보 같이 전달
class SmartReplyResult {
  final List<SmartReplySuggestion> suggestions;
  final bool isQuotaExceeded;

  SmartReplyResult({
    required this.suggestions,
    this.isQuotaExceeded = false,
  });

  factory SmartReplyResult.empty() {
    return SmartReplyResult(suggestions: []);
  }

  factory SmartReplyResult.quotaExceeded() {
    return SmartReplyResult(suggestions: [], isQuotaExceeded: true);
  }
}