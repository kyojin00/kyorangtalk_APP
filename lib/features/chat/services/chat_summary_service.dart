import 'package:supabase_flutter/supabase_flutter.dart';

/// ═══════════════════════════════════════════════════
/// 채팅 요약 (GPT-4o) 서비스
/// ═══════════════════════════════════════════════════
class ChatSummaryService {
  static final _supabase = Supabase.instance.client;

  /// 안 읽은 메시지를 요약
  ///
  /// 반환: [SummaryResult]
  /// 예외: [SummaryException]
  static Future<SummaryResult> summarize({
    required String roomId,
    required bool isGroup,
    int limit = 200,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'chat-summary',
        body: {
          'roomId': roomId,
          'roomType': isGroup ? 'group' : 'dm',
          'limit': limit,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw SummaryException('잘못된 응답 형식');
      }

      // 에러 응답 처리
      if (data['error'] != null) {
        throw SummaryException(data['error'].toString());
      }

      // 메시지 부족 케이스
      if (data['summary'] == null) {
        return SummaryResult(
          summary: null,
          messageCount: (data['messageCount'] as num?)?.toInt() ?? 0,
          cached: false,
          notEnoughMessages: data['reason'] == 'not_enough_messages',
        );
      }

      return SummaryResult(
        summary: data['summary'] as String,
        messageCount: (data['messageCount'] as num?)?.toInt() ?? 0,
        cached: data['cached'] == true,
        notEnoughMessages: false,
      );
    } on FunctionException catch (e) {
      throw SummaryException(
        e.details?.toString() ?? e.toString(),
      );
    } catch (e) {
      if (e is SummaryException) rethrow;
      throw SummaryException(e.toString());
    }
  }
}

class SummaryResult {
  final String? summary;
  final int messageCount;
  final bool cached;
  final bool notEnoughMessages;

  SummaryResult({
    required this.summary,
    required this.messageCount,
    required this.cached,
    required this.notEnoughMessages,
  });

  bool get isEmpty => summary == null;
}

class SummaryException implements Exception {
  final String message;
  SummaryException(this.message);

  @override
  String toString() => message;
}