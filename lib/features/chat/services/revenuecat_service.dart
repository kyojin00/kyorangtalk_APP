import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';                        // ⭐ PlatformException
import 'package:purchases_flutter/purchases_flutter.dart';

/// ═══════════════════════════════════════════════════
/// RevenueCat 서비스 (purchases_flutter 8.x 호환)
/// ═══════════════════════════════════════════════════
class RevenueCatService {
  // ⭐ RC Dashboard → Project Settings → API Keys → Android의 'goog_...' 키
  // TODO: 실제 키로 교체
  static const String _googleApiKey = 'goog_CNBOGcKPfZLIBevDLzJezLcsMvD';

  // iOS (나중에 Apple Developer 가입 후 추가)
  // static const String _appleApiKey = 'appl_YOUR_API_KEY_HERE';

  // RC Dashboard에서 정의한 Entitlement 식별자
  static const String entitlementId = 'pro';

  static bool _initialized = false;

  /// 초기화 (앱 시작 시 1회)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.warn,
      );

      final config = PurchasesConfiguration(_googleApiKey);
      await Purchases.configure(config);
      _initialized = true;
      debugPrint('✅ [RC] 초기화 완료');
    } catch (e) {
      debugPrint('🔴 [RC] 초기화 실패: $e');
    }
  }

  /// Supabase user.id ↔ RC AppUserID 매핑
  static Future<void> login(String supabaseUserId) async {
    if (!_initialized) {
      debugPrint('⚠️ [RC] 초기화 전에 login 호출됨');
      return;
    }

    try {
      final result = await Purchases.logIn(supabaseUserId);
      debugPrint(
        '✅ [RC] 로그인 완료: $supabaseUserId (created=${result.created})',
      );
    } catch (e) {
      debugPrint('🔴 [RC] 로그인 실패: $e');
    }
  }

  static Future<void> logout() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
      debugPrint('✅ [RC] 로그아웃 완료');
    } catch (e) {
      debugPrint('🔴 [RC] 로그아웃 실패: $e');
    }
  }

  /// 현재 RC 캐시상 Pro인지
  static Future<bool> isProActive() async {
    if (!_initialized) return false;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final entitlement = customerInfo.entitlements.active[entitlementId];
      return entitlement != null;
    } catch (e) {
      debugPrint('🔴 [RC] isProActive 확인 실패: $e');
      return false;
    }
  }

  /// 사용 가능한 패키지 목록
  static Future<List<Package>> fetchAvailablePackages() async {
    if (!_initialized) return [];

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        debugPrint(
            '⚠️ [RC] Current offering 없음. RC Dashboard에서 default offering 설정 필요');
        return [];
      }
      return current.availablePackages;
    } catch (e) {
      debugPrint('🔴 [RC] 패키지 목록 조회 실패: $e');
      return [];
    }
  }

  /// 월간 패키지
  static Future<Package?> fetchMonthlyPackage() async {
    if (!_initialized) return null;

    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return null;

      if (current.monthly != null) return current.monthly;

      if (current.availablePackages.isNotEmpty) {
        return current.availablePackages.first;
      }
      return null;
    } catch (e) {
      debugPrint('🔴 [RC] 월간 패키지 조회 실패: $e');
      return null;
    }
  }

  /// ═══════════════════════════════════════════════════
  /// ⭐ 결제 (purchases_flutter 8.x API)
  ///
  /// 8.x에서는 purchasePackage()가 CustomerInfo를 직접 반환
  /// (이전 버전의 PurchaseResult.customerInfo 아님)
  /// ═══════════════════════════════════════════════════
  static Future<PurchaseResult> purchase(Package package) async {
    if (!_initialized) {
      return PurchaseResult.error('RC가 초기화되지 않았습니다');
    }

    try {
      // ⭐ 8.x: CustomerInfo 직접 반환
      final customerInfo = await Purchases.purchasePackage(package);
      final entitlement = customerInfo.entitlements.active[entitlementId];

      if (entitlement != null) {
        debugPrint('✅ [RC] 결제 완료, Pro 활성화: $entitlementId');
        return PurchaseResult.success();
      } else {
        debugPrint('⚠️ [RC] 결제는 됐는데 entitlement 활성화 안 됨');
        return PurchaseResult.error('결제는 처리됐지만 권한이 활성화되지 않았어요');
      }
    } on PlatformException catch (e) {
      // ⭐ flutter/services.dart에서 import
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('⏸️ [RC] 사용자가 결제 취소');
        return PurchaseResult.userCancelled();
      }
      debugPrint('🔴 [RC] 결제 실패: $errorCode / ${e.message}');
      return PurchaseResult.error(_errorMessageKr(errorCode, e.message));
    } catch (e) {
      debugPrint('🔴 [RC] 결제 실패 (기타): $e');
      return PurchaseResult.error('결제 중 오류가 발생했어요');
    }
  }

  /// 구매 복원
  static Future<RestoreResult> restorePurchases() async {
    if (!_initialized) {
      return RestoreResult.error('RC가 초기화되지 않았습니다');
    }

    try {
      final customerInfo = await Purchases.restorePurchases();
      final entitlement = customerInfo.entitlements.active[entitlementId];

      if (entitlement != null) {
        debugPrint('✅ [RC] 복원 성공, Pro 활성화');
        return RestoreResult.success();
      } else {
        debugPrint('ℹ️ [RC] 복원했지만 활성화된 구독 없음');
        return RestoreResult.notFound();
      }
    } catch (e) {
      debugPrint('🔴 [RC] 복원 실패: $e');
      return RestoreResult.error('복원 중 오류가 발생했어요');
    }
  }

  static String _errorMessageKr(
      PurchasesErrorCode code, String? defaultMsg) {
    switch (code) {
      case PurchasesErrorCode.purchaseNotAllowedError:
        return '이 기기에서는 결제가 허용되지 않아요';
      case PurchasesErrorCode.purchaseInvalidError:
        return '결제 정보가 유효하지 않아요';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return '구매할 수 없는 상품이에요';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return '이미 구매한 상품이에요. 복원을 시도해보세요';
      case PurchasesErrorCode.networkError:
        return '네트워크 연결을 확인해주세요';
      case PurchasesErrorCode.storeProblemError:
        return '스토어에 문제가 있어요. 잠시 후 다시 시도해주세요';
      case PurchasesErrorCode.paymentPendingError:
        return '결제가 보류 중이에요. 처리되면 알려드릴게요';
      default:
        return defaultMsg ?? '결제 중 오류가 발생했어요';
    }
  }
}

/// ═══════════════════════════════════════════════════
/// 결과 타입
/// ═══════════════════════════════════════════════════
class PurchaseResult {
  final PurchaseResultType type;
  final String? errorMessage;

  PurchaseResult._(this.type, [this.errorMessage]);

  factory PurchaseResult.success() =>
      PurchaseResult._(PurchaseResultType.success);
  factory PurchaseResult.userCancelled() =>
      PurchaseResult._(PurchaseResultType.userCancelled);
  factory PurchaseResult.error(String message) =>
      PurchaseResult._(PurchaseResultType.error, message);

  bool get isSuccess => type == PurchaseResultType.success;
  bool get isUserCancelled => type == PurchaseResultType.userCancelled;
  bool get isError => type == PurchaseResultType.error;
}

enum PurchaseResultType { success, userCancelled, error }

class RestoreResult {
  final RestoreResultType type;
  final String? errorMessage;

  RestoreResult._(this.type, [this.errorMessage]);

  factory RestoreResult.success() =>
      RestoreResult._(RestoreResultType.success);
  factory RestoreResult.notFound() =>
      RestoreResult._(RestoreResultType.notFound);
  factory RestoreResult.error(String message) =>
      RestoreResult._(RestoreResultType.error, message);

  bool get isSuccess => type == RestoreResultType.success;
  bool get isNotFound => type == RestoreResultType.notFound;
  bool get isError => type == RestoreResultType.error;
}

enum RestoreResultType { success, notFound, error }