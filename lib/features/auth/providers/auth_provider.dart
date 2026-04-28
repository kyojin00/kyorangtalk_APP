import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 현재 세션 스트림
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// 현재 유저
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session?.user,
    loading: () => Supabase.instance.client.auth.currentUser,
    error: (_, __) => null,
  );
});

// 현재 유저 프로필
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final data = await Supabase.instance.client
      .from('kyorangtalk_profiles')
      .select('*')
      .eq('id', user.id)
      .maybeSingle();

  return data;
});

class AuthService {
  final _supabase = Supabase.instance.client;
  final _firebaseAuth = fb.FirebaseAuth.instance;

  // 이메일 로그인
  Future<void> signInWithEmail(String email, String password) async {
    final res = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (res.session == null) throw Exception('로그인에 실패했어요');
  }

  // 이메일 회원가입
  Future<void> signUpWithEmail(String email, String password) async {
    final res = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );
    if (res.user == null) throw Exception('회원가입에 실패했어요');
  }

  // Google 로그인
  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      serverClientId:'54388432481-v8n3a8ijv4m5as0kltofu1jn00puu1tc.apps.googleusercontent.com',
      scopes: ['email', 'profile'],
      forceCodeForRefreshToken: true,
    );

    await googleSignIn.signOut();

    try {
      final account = await googleSignIn.signIn();
      if (account == null) throw Exception('로그인이 취소됐어요');

      final auth = await account.authentication;
      print('idToken: ${auth.idToken}');
      print('accessToken: ${auth.accessToken}');

      if (auth.idToken == null) throw Exception('idToken null');

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: auth.idToken!,
        accessToken: auth.accessToken,
      );
    } catch (e) {
      print('Google 로그인 상세 오류: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════
  // 전화번호 로그인 (Firebase Phone Auth + Supabase)
  // ═══════════════════════════════════════════════

  /// 전화번호로 SMS 인증코드 전송
  /// onCodeSent: verificationId를 콜백으로 전달
  /// onFailed: 실패 시 에러 메시지
  Future<void> sendSmsCode({
    required String phoneNumber, // 예: "+821012345678"
    required Function(String verificationId) onCodeSent,
    required Function(String error) onFailed,
    Function()? onAutoVerified,
  }) async {
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (fb.PhoneAuthCredential credential) async {
        // Android 자동 인증 (SIM 카드 확인)
        try {
          await _firebaseAuth.signInWithCredential(credential);
          await _completePhoneSignIn(phoneNumber);
          onAutoVerified?.call();
        } catch (e) {
          print('자동 인증 오류: $e');
        }
      },
      verificationFailed: (fb.FirebaseAuthException e) {
        print('SMS 전송 실패: ${e.code} - ${e.message}');
        String msg = '인증에 실패했어요';
        if (e.code == 'invalid-phone-number') {
          msg = '올바른 전화번호가 아니에요';
        } else if (e.code == 'too-many-requests') {
          msg = '너무 많은 요청이 있었어요. 잠시 후 시도해주세요';
        } else if (e.code == 'quota-exceeded') {
          msg = 'SMS 전송 한도를 초과했어요';
        }
        onFailed(msg);
      },
      codeSent: (String verificationId, int? resendToken) {
        print('SMS 전송 성공, verificationId: $verificationId');
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        print('자동 인증 타임아웃: $verificationId');
      },
    );
  }

  /// SMS 인증코드 확인 후 로그인/가입
  Future<void> verifySmsCode({
    required String verificationId,
    required String smsCode,
    required String phoneNumber, // 예: "+821012345678"
  }) async {
    // 1. Firebase 인증
    final credential = fb.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    await _firebaseAuth.signInWithCredential(credential);

    // 2. Supabase 로그인/가입 처리
    await _completePhoneSignIn(phoneNumber);
  }

  /// Firebase 인증 후 Supabase에 로그인/가입 처리
  Future<void> _completePhoneSignIn(String phoneNumber) async {
    // 전화번호를 이메일 형태로 변환
    // +82 10-1234-5678 -> 821012345678@phone.kyorang.com
    final cleanPhone =
        phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final phoneEmail = '$cleanPhone@phone.kyorang.com';
    final password = _generatePasswordForPhone(cleanPhone);

    print('Supabase 로그인 시도: $phoneEmail');

    try {
      // 먼저 로그인 시도
      await _supabase.auth.signInWithPassword(
        email: phoneEmail,
        password: password,
      );
      print('Supabase 기존 계정 로그인 성공');
    } catch (e) {
      // 로그인 실패 시 → 신규 가입
      print('신규 가입 진행: $e');
      final res = await _supabase.auth.signUp(
        email: phoneEmail,
        password: password,
        data: {
          'phone_number': phoneNumber,
          'signup_method': 'phone',
        },
      );
      if (res.user == null) {
        throw Exception('Supabase 가입에 실패했어요');
      }
      print('Supabase 가입 성공');
    }
  }

  /// 전화번호 기반 결정적 비밀번호 생성
  /// 동일한 전화번호는 항상 같은 비밀번호가 생성되어야 함
  String _generatePasswordForPhone(String cleanPhone) {
    // 간단한 해시 방식 (실제로는 더 안전한 방법 써야 함)
    const salt = 'kyorangtalk_phone_auth_2026';
    final combined = '$cleanPhone$salt';
    // 기기별 고유 시드 없이, 전화번호만으로 결정적 생성
    final bytes = combined.codeUnits;
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7FFFFFFF;
    }
    // 16자리 비밀번호 생성
    final chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random(hash);
    final password = List.generate(
        16, (_) => chars[random.nextInt(chars.length)]).join();
    return 'P${password}!';
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      print('Firebase 로그아웃 오류: $e');
    }
    await _supabase.auth.signOut();
  }

  // 프로필 존재 확인
  Future<bool> hasProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final data = await _supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname')
        .eq('id', user.id)
        .maybeSingle();

    return data != null &&
        (data['nickname'] as String?)?.isNotEmpty == true;
  }
}

final authServiceProvider = Provider((ref) => AuthService());