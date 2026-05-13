import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../chat/services/revenuecat_service.dart';

// ═══════════════════════════════════════════════
// 💳 구독 서비스 (RevenueCat 통합)
//
// 위치: lib/features/subscription/services/subscription_service.dart
//
// 기존 RevenueCatService를 활용해서 Supabase 동기화 + UI 연결
// ═══════════════════════════════════════════════

class SubscriptionModel {
  final String tier;                  // 'free' or 'pro'
  final String? productId;
  final DateTime expiresAt;
  final DateTime? purchasedAt;
  final DateTime? cancelledAt;
  final String? paymentProvider;
  final String? store;
  final bool autoRenew;
  final bool willRenew;
  final bool isInTrial;

  SubscriptionModel({
    required this.tier,
    this.productId,
    required this.expiresAt,
    this.purchasedAt,
    this.cancelledAt,
    this.paymentProvider,
    this.store,
    this.autoRenew = false,
    this.willRenew = false,
    this.isInTrial = false,
  });

  bool get isActive => tier == 'pro' && expiresAt.isAfter(DateTime.now());
  bool get isCancelled => cancelledAt != null;
  bool get isTest =>
      paymentProvider == 'test' || productId == 'drawer_test';

  int get daysRemaining =>
      expiresAt.difference(DateTime.now()).inDays;

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      tier:            (map['tier'] as String?) ?? 'free',
      productId:       map['product_id'] as String?,
      expiresAt:       DateTime.parse(map['expires_at'] as String),
      purchasedAt:     map['purchased_at'] != null
          ? DateTime.parse(map['purchased_at'] as String)
          : null,
      cancelledAt:     map['cancelled_at'] != null
          ? DateTime.parse(map['cancelled_at'] as String)
          : null,
      paymentProvider: map['payment_provider'] as String?,
      store:           map['store'] as String?,
      autoRenew:       (map['auto_renew'] as bool?) ?? false,
      willRenew:       (map['will_renew'] as bool?) ?? false,
      isInTrial:       (map['is_in_trial'] as bool?) ?? false,
    );
  }
}

class SubscriptionService {
  static final _supabase = Supabase.instance.client;

  // ═══════════════════════════════════════════════
  // Supabase 조회 (DB 기준)
  // ═══════════════════════════════════════════════
  static Future<SubscriptionModel?> getCurrentSubscription() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _supabase
          .from('kyorangtalk_subscriptions')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null) return null;
      return SubscriptionModel.fromMap(data);
    } catch (e) {
      print('🔴 구독 조회 실패: $e');
      return null;
    }
  }

  static Future<bool> hasActiveSubscription() async {
    final sub = await getCurrentSubscription();
    return sub?.isActive ?? false;
  }

  // ═══════════════════════════════════════════════
  // 개발용 테스트 활성화
  // ═══════════════════════════════════════════════
  static Future<void> activateTestSubscription({int days = 30}) async {
    try {
      await _supabase.rpc(
        'kyorangtalk_activate_test_subscription',
        params: {'p_days': days},
      );
    } catch (e) {
      print('🔴 테스트 구독 활성화 실패: $e');
      rethrow;
    }
  }

  static Future<void> cancelSubscription() async {
    try {
      await _supabase.rpc('kyorangtalk_cancel_subscription');
    } catch (e) {
      print('🔴 구독 취소 실패: $e');
      rethrow;
    }
  }

  static Future<int> restoreAllRooms() async {
    try {
      final result = await _supabase.rpc('kyorangtalk_restore_all_rooms');
      return (result as int?) ?? 0;
    } catch (e) {
      print('🔴 전체 복원 실패: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════
  // ⭐ RevenueCat 통합 — RevenueCatService 활용
  // ═══════════════════════════════════════════════

  /// 사용 가능한 패키지 목록
  static Future<List<Package>> getAvailablePackages() async {
    return await RevenueCatService.fetchAvailablePackages();
  }

  /// 현재 Offering — UI에서 monthly/annual 등 구분용
  static Future<Offering?> getCurrentOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      print('🔴 Offering 로드 실패: $e');
      return null;
    }
  }

  /// 패키지 구매
  static Future<PurchaseResult> purchasePackage(Package package) async {
    return await RevenueCatService.purchase(package);
  }

  /// 구매 복원
  static Future<RestoreResult> restorePurchases() async {
    return await RevenueCatService.restorePurchases();
  }
}

// ═══════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════

final subscriptionProvider =
    FutureProvider<SubscriptionModel?>((ref) async {
  return await SubscriptionService.getCurrentSubscription();
});

final hasActiveSubscriptionProvider = FutureProvider<bool>((ref) async {
  final sub = await ref.watch(subscriptionProvider.future);
  return sub?.isActive ?? false;
});

/// RevenueCat Offering Provider
final offeringProvider = FutureProvider<Offering?>((ref) async {
  return await SubscriptionService.getCurrentOffering();
});

// ═══════════════════════════════════════════════
// 서랍 — 나간 방 목록
// ═══════════════════════════════════════════════

class HiddenRoom {
  final String roomId;
  final String partnerId;
  final String partnerName;
  final String? partnerAvatar;
  final String lastMessage;
  final DateTime lastMessageAt;
  final DateTime hiddenAt;
  final int hiddenMessagesCount;

  HiddenRoom({
    required this.roomId,
    required this.partnerId,
    required this.partnerName,
    this.partnerAvatar,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.hiddenAt,
    required this.hiddenMessagesCount,
  });

  factory HiddenRoom.fromMap(Map<String, dynamic> map) {
    return HiddenRoom(
      roomId:               map['out_room_id'] as String,
      partnerId:            map['out_partner_id'] as String,
      partnerName:          (map['out_partner_name'] as String?) ?? '알 수 없음',
      partnerAvatar:        map['out_partner_avatar'] as String?,
      lastMessage:          (map['out_last_message'] as String?) ?? '',
      lastMessageAt:        DateTime.parse(map['out_last_message_at'] as String),
      hiddenAt:             DateTime.parse(map['out_hidden_at'] as String),
      hiddenMessagesCount:  (map['out_hidden_messages_count'] as num?)?.toInt() ?? 0,
    );
  }
}

final hiddenRoomsProvider = FutureProvider<List<HiddenRoom>>((ref) async {
  try {
    final response = await Supabase.instance.client
        .rpc('kyorangtalk_get_hidden_rooms');

    if (response == null) return [];

    return (response as List)
        .map((row) => HiddenRoom.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  } catch (e) {
    print('🔴 서랍 목록 로드 실패: $e');
    return [];
  }
});