import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════
// 🔒 AppLockService
//
// 위치: lib/core/security/app_lock_service.dart
//
// 기능
// - PIN 4자리 SHA-256 해시 저장/검증
// - 생체인증 (지문) 사용 가능 여부 확인 + 실행
// - 잠금 / 생체인증 ON·OFF 토글
// - 5회 실패 시 30초 잠금
//
// 저장 키
//   app_lock_enabled           : bool   잠금 사용 여부
//   app_lock_pin_hash          : String SHA-256 해시
//   app_lock_biometric_enabled : bool   지문 사용 여부
//   app_lock_failed_attempts   : int    실패 횟수
//   app_lock_lockout_until     : int    잠금 해제 시각 (ms)
// ═══════════════════════════════════════════════════

class AppLockService {
  static const _kEnabled = 'app_lock_enabled';
  static const _kPinHash = 'app_lock_pin_hash';
  static const _kBiometric = 'app_lock_biometric_enabled';
  static const _kFailedAttempts = 'app_lock_failed_attempts';
  static const _kLockoutUntil = 'app_lock_lockout_until';

  static const int kMaxAttempts = 5;
  static const int kLockoutSeconds = 30;

  static final LocalAuthentication _auth = LocalAuthentication();

  // ─────────────────────────────────────────────
  // PIN 해시 (SHA-256, 솔트 없음 — 4자리는 어차피 brute force 불가능)
  // ─────────────────────────────────────────────
  static String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // ─────────────────────────────────────────────
  // 잠금 활성화 상태
  // ─────────────────────────────────────────────
  static Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  static Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (!enabled) {
      // 잠금 해제 시 PIN/생체/실패 기록도 초기화
      await prefs.remove(_kPinHash);
      await prefs.remove(_kBiometric);
      await prefs.remove(_kFailedAttempts);
      await prefs.remove(_kLockoutUntil);
    }
  }

  // ─────────────────────────────────────────────
  // PIN 관리
  // ─────────────────────────────────────────────
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_kPinHash);
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw Exception('PIN은 숫자 4자리여야 해요');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinHash, _hashPin(pin));
  }

  /// PIN 검증.
  /// 성공 시 실패 카운트/잠금 자동 리셋, 실패 시 카운트 증가
  static Future<bool> verifyPin(String pin) async {
    if (await isLockedOut()) return false;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPinHash);
    if (stored == null) return false;

    final ok = _hashPin(pin) == stored;
    if (ok) {
      await resetFailedAttempts();
    } else {
      await _recordFailedAttempt();
    }
    return ok;
  }

  // ─────────────────────────────────────────────
  // 생체인증
  // ─────────────────────────────────────────────

  /// 기기가 생체인증을 지원하는지 (지문 등록 여부 포함)
  static Future<bool> canUseBiometric() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('🔴 [AppLock] 생체인증 지원 확인 실패: $e');
      return false;
    }
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometric) ?? false;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometric, enabled);
  }

  /// 생체인증 실행.
  /// 성공 시 true, 실패/취소/오류 시 false
  static Future<bool> authenticateBiometric({
    String reason = '교랑톡 잠금 해제',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) await resetFailedAttempts();
      return ok;
    } on Exception catch (e) {
      // PlatformException 처리
      final msg = e.toString();
      if (msg.contains(auth_error.notAvailable) ||
          msg.contains(auth_error.notEnrolled) ||
          msg.contains(auth_error.lockedOut) ||
          msg.contains(auth_error.permanentlyLockedOut)) {
        debugPrint('🔴 [AppLock] 생체인증 사용 불가: $msg');
      } else {
        debugPrint('🔴 [AppLock] 생체인증 오류: $msg');
      }
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // 실패 카운트 / 잠금
  // ─────────────────────────────────────────────
  static Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFailedAttempts) ?? 0;
  }

  static Future<void> _recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kFailedAttempts) ?? 0;
    final next = current + 1;
    await prefs.setInt(_kFailedAttempts, next);

    if (next >= kMaxAttempts) {
      final until = DateTime.now()
          .add(const Duration(seconds: kLockoutSeconds))
          .millisecondsSinceEpoch;
      await prefs.setInt(_kLockoutUntil, until);
    }
  }

  static Future<void> resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailedAttempts);
    await prefs.remove(_kLockoutUntil);
  }

  /// 현재 5회 실패로 30초 잠금 중인지
  static Future<bool> isLockedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kLockoutUntil);
    if (until == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= until) {
      // 시간 지났으면 자동 해제
      await prefs.remove(_kLockoutUntil);
      await prefs.remove(_kFailedAttempts);
      return false;
    }
    return true;
  }

  /// 잠금 남은 시간 (초). 잠금 아니면 0
  static Future<int> getRemainingLockoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kLockoutUntil);
    if (until == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((until - now) / 1000).ceil();
    return remaining > 0 ? remaining : 0;
  }
}