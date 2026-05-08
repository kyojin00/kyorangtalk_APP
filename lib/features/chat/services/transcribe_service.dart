import 'package:supabase_flutter/supabase_flutter.dart';

/// ═══════════════════════════════════════════════════
/// 음성 메시지 STT (Whisper) 서비스
///
/// Supabase Edge Function `voice-transcribe`를 호출해서
/// audio_transcript 컬럼을 채운다.
/// 결과는 DB에 캐시되므로, 같은 메시지 두 번째 호출은
/// 즉시 반환됨 (cached: true).
/// ═══════════════════════════════════════════════════
class TranscribeService {
  static final _supabase = Supabase.instance.client;

  /// 음성 메시지를 텍스트로 변환
  ///
  /// 반환: 변환된 텍스트 (성공 시)
  /// 예외: 실패 시 [TranscribeException]
  ///   - isProcessing=true: 이미 다른 클라이언트가 변환 중
  ///   - isQuotaExceeded=true: Free 사용자 한도 초과 ⭐ NEW
  static Future<String> transcribe({
    required String messageId,
    required bool isGroup,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'voice-transcribe',
        body: {
          'messageId': messageId,
          'isGroup': isGroup,
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw TranscribeException('잘못된 응답 형식');
      }

      // 에러 응답 처리
      if (data['error'] != null) {
        final err = data['error'].toString();

        // ⭐ 한도 초과
        if (err == 'quota_exceeded') {
          throw TranscribeException(
            data['message']?.toString() ?? '오늘의 무료 사용 횟수를 다 썼어요',
            isQuotaExceeded: true,
          );
        }

        // 이미 진행 중인 경우 — UI는 polling으로 결과 기다림
        if (data['status'] == 'processing') {
          throw TranscribeException('이미 변환 중이에요', isProcessing: true);
        }

        throw TranscribeException(err);
      }

      final transcript = data['transcript'] as String?;
      if (transcript == null || transcript.isEmpty) {
        throw TranscribeException('변환 결과가 비어있어요');
      }

      return transcript;
    } on FunctionException catch (e) {
      // ⭐ FunctionException에서 quota 에러 잡기
      final detail = e.details?.toString() ?? '';
      final combined = '$detail ${e.toString()}'.toLowerCase();

      if (combined.contains('quota_exceeded') || combined.contains('429')) {
        throw TranscribeException(
          '오늘의 무료 사용 횟수를 다 썼어요',
          isQuotaExceeded: true,
        );
      }

      throw TranscribeException(
        'Edge Function 오류: ${e.details ?? e.toString()}',
      );
    } catch (e) {
      if (e is TranscribeException) rethrow;

      // ⭐ 일반 예외에서도 quota 체크
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('quota_exceeded') || errStr.contains('429')) {
        throw TranscribeException(
          '오늘의 무료 사용 횟수를 다 썼어요',
          isQuotaExceeded: true,
        );
      }

      throw TranscribeException(e.toString());
    }
  }

  /// 변환 결과를 DB에서 직접 조회 (polling 용)
  ///
  /// 반환: { 'status': ..., 'transcript': ... }
  static Future<Map<String, dynamic>?> fetchStatus({
    required String messageId,
    required bool isGroup,
  }) async {
    final tableName = isGroup
        ? 'kyorangtalk_group_messages'
        : 'kyorangtalk_messages';

    try {
      final data = await _supabase
          .from(tableName)
          .select('audio_transcript, audio_transcript_status')
          .eq('id', messageId)
          .maybeSingle();

      if (data == null) return null;
      return {
        'status':     data['audio_transcript_status'] as String?,
        'transcript': data['audio_transcript'] as String?,
      };
    } catch (e) {
      print('🔴 fetchStatus 실패: $e');
      return null;
    }
  }
}

class TranscribeException implements Exception {
  final String message;
  final bool isProcessing;
  final bool isQuotaExceeded; // ⭐ NEW

  TranscribeException(
    this.message, {
    this.isProcessing = false,
    this.isQuotaExceeded = false,
  });

  @override
  String toString() => message;
}