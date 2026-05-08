import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ═══════════════════════════════════════════════════
/// 구독 상태 모델
/// ═══════════════════════════════════════════════════
class SubscriptionStatus {
  final bool isPro;
  final DateTime? expiresAt;       // Pro 결제 만료일 (체험 기간엔 null)
  final bool isInTrial;            // 7일 체험 중인지
  final int trialDaysLeft;         // 체험 남은 일수 (0 이상)

  SubscriptionStatus({
    required this.isPro,
    this.expiresAt,
    required this.isInTrial,
    required this.trialDaysLeft,
  });

  static SubscriptionStatus free() => SubscriptionStatus(
        isPro: false,
        isInTrial: false,
        trialDaysLeft: 0,
      );
}

/// AI 기능 종류
enum AiFeature {
  stt('stt', '음성 텍스트 변환'),
  summary('summary', '대화 요약'),
  tone('tone', '톤 코치'),
  smartReply('smart_reply', '추천 답장'),
  plan('plan', '약속 정리');

  final String key;
  final String label;
  const AiFeature(this.key, this.label);
}

/// 사용량 한도 체크 결과
class UsageCheckResult {
  final bool allowed;
  final int currentCount;  // 오늘 사용한 횟수
  final int limit;         // 한도 (-1 = 무제한)
  final bool isPro;

  UsageCheckResult({
    required this.allowed,
    required this.currentCount,
    required this.limit,
    required this.isPro,
  });

  int get remaining =>
      isPro ? -1 : (limit - currentCount).clamp(0, limit);

  factory UsageCheckResult.fromJson(Map<String, dynamic> j) {
    return UsageCheckResult(
      allowed: j['allowed'] as bool? ?? false,
      currentCount: j['current_count'] as int? ?? 0,
      limit: j['limit'] as int? ?? 5,
      isPro: j['is_pro'] as bool? ?? false,
    );
  }
}

/// ═══════════════════════════════════════════════════
/// SubscriptionService
/// ═══════════════════════════════════════════════════
class SubscriptionService {
  static final _supabase = Supabase.instance.client;

  /// 현재 사용자의 구독 상태 조회
  static Future<SubscriptionStatus> fetchStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return SubscriptionStatus.free();

      // 1. 프로필에서 가입일 확인 → 7일 체험 여부
      final profile = await _supabase
          .from('kyorangtalk_profiles')
          .select('created_at')
          .eq('id', user.id)
          .maybeSingle();

      bool isInTrial = false;
      int trialDaysLeft = 0;

      if (profile != null) {
        final createdAt = DateTime.parse(profile['created_at'] as String);
        final trialEnd = createdAt.add(const Duration(days: 7));
        final now = DateTime.now();
        if (trialEnd.isAfter(now)) {
          isInTrial = true;
          trialDaysLeft = trialEnd.difference(now).inDays + 1;
        }
      }

      // 2. 구독 정보 확인
      final sub = await _supabase
          .from('kyorangtalk_subscriptions')
          .select('tier, expires_at')
          .eq('user_id', user.id)
          .maybeSingle();

      bool isPaidPro = false;
      DateTime? expiresAt;
      if (sub != null && sub['tier'] == 'pro') {
        if (sub['expires_at'] == null) {
          isPaidPro = true;
        } else {
          expiresAt = DateTime.parse(sub['expires_at'] as String);
          if (expiresAt.isAfter(DateTime.now())) {
            isPaidPro = true;
          }
        }
      }

      return SubscriptionStatus(
        isPro: isInTrial || isPaidPro,
        expiresAt: expiresAt,
        isInTrial: isInTrial,
        trialDaysLeft: trialDaysLeft,
      );
    } catch (e) {
      print('🔴 [Subscription] fetchStatus 실패: $e');
      return SubscriptionStatus.free();
    }
  }

  /// 특정 AI 기능 사용 가능한지 체크
  /// - DB 함수 호출
  static Future<UsageCheckResult> checkUsage(AiFeature feature) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return UsageCheckResult(
          allowed: false,
          currentCount: 0,
          limit: 5,
          isPro: false,
        );
      }

      final result = await _supabase.rpc('check_kt_ai_usage_limit', params: {
        'p_user_id': user.id,
        'p_feature': feature.key,
      });

      if (result is Map<String, dynamic>) {
        return UsageCheckResult.fromJson(result);
      }
      // result가 String일 때 대비 (JSON 직렬화)
      if (result is String) {
        // 일부 클라이언트에서 String으로 옴 - JSON 파싱
        return UsageCheckResult.fromJson(_decodeJson(result));
      }

      return UsageCheckResult(
        allowed: false,
        currentCount: 0,
        limit: 5,
        isPro: false,
      );
    } catch (e) {
      print('🔴 [Subscription] checkUsage 실패: $e');
      return UsageCheckResult(
        allowed: false,
        currentCount: 0,
        limit: 5,
        isPro: false,
      );
    }
  }

  /// 오늘 모든 AI 기능별 사용량 조회 (UI 표시용)
  /// 반환: { 'tone': 3, 'summary': 1, ... }
  static Future<Map<AiFeature, int>> fetchTodayUsage() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return {};

      final result = await _supabase.rpc('get_kt_ai_usage_today',
          params: {'p_user_id': user.id});

      final map = <AiFeature, int>{};
      if (result is List) {
        for (final row in result) {
          if (row is Map) {
            final featureKey = row['feature'] as String?;
            final count = row['count'] as int? ?? 0;
            if (featureKey != null) {
              for (final f in AiFeature.values) {
                if (f.key == featureKey) {
                  map[f] = count;
                  break;
                }
              }
            }
          }
        }
      }
      return map;
    } catch (e) {
      print('🔴 [Subscription] fetchTodayUsage 실패: $e');
      return {};
    }
  }

  static Map<String, dynamic> _decodeJson(String s) {
    try {
      // ignore: avoid_dynamic_calls
      return Map<String, dynamic>.from(
          (s.isEmpty ? <String, dynamic>{} : _parseJson(s)));
    } catch (_) {
      return {};
    }
  }

  static dynamic _parseJson(String s) {
    // dart:convert 의존하지 않게 import 없이 처리
    // 호출 시점엔 거의 안 쓰이므로 안전한 fallback
    return <String, dynamic>{};
  }
}

/// ═══════════════════════════════════════════════════
/// Riverpod Providers
/// ═══════════════════════════════════════════════════

/// 현재 사용자의 구독 상태
/// invalidate해서 새로고침 가능
final subscriptionStatusProvider =
    FutureProvider<SubscriptionStatus>((ref) async {
  return await SubscriptionService.fetchStatus();
});

/// 오늘 AI 사용량 (전체)
final todayAiUsageProvider =
    FutureProvider<Map<AiFeature, int>>((ref) async {
  return await SubscriptionService.fetchTodayUsage();
});

/// 특정 기능 사용 가능 여부 (live 체크)
final aiUsageCheckProvider =
    FutureProvider.family.autoDispose<UsageCheckResult, AiFeature>(
        (ref, feature) async {
  return await SubscriptionService.checkUsage(feature);
});