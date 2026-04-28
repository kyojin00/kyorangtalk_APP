import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../app.dart';
import '../auth/screens/signup_method_screen.dart';
import 'birthday_picker.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _statusController = TextEditingController();
  DateTime? _birthday;
  bool _loading = false;
  String? _error;

  late AnimationController _logoController;
  late Animation<double> _logoScaleAnim;
  late Animation<double> _logoGlowAnim;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _logoScaleAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _logoGlowAnim = Tween<double>(begin: 0.3, end: 0.5).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _loadPhoneFromUser();
  }

  void _loadPhoneFromUser() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final phone = user.userMetadata?['phone_number'] as String?;
    if (phone != null && phone.isNotEmpty) {
      String displayPhone = phone.startsWith('+82')
          ? '0${phone.substring(3)}'
          : phone;

      final digits = displayPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 11) {
        displayPhone =
            '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
      }
      _phoneController.text = displayPhone;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    _statusController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nicknameController.text.trim().length >= 2 &&
      _birthday != null &&
      _isValidPhone(_phoneController.text) &&
      !_loading;

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^010\d{8}$').hasMatch(digits);
  }

  String _toE164(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      return '+82${digits.substring(1)}';
    }
    return '+82$digits';
  }

  Future<void> _pickBirthday() async {
    FocusScope.of(context).unfocus();

    final picked = await showBirthdayPicker(
      context: context,
      initialDate: _birthday,
    );

    if (picked != null) {
      setState(() => _birthday = picked);
    }
  }

  String _getSignupMethod(User user) {
    final method = user.userMetadata?['signup_method'] as String?;
    if (method != null) return method;

    final provider = user.appMetadata['provider'] as String?;
    if (provider == 'google') return 'google';
    if (provider == 'email') return 'email';

    if (user.email?.endsWith('@phone.kyorang.com') == true) {
      return 'phone';
    }

    return 'email';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser!;
    final nickname = _nicknameController.text.trim();
    final phoneE164 = _toE164(_phoneController.text);
    final status = _statusController.text.trim();

    try {
      print('🟡 온보딩 시작, userId: ${user.id}');

      final existing = await supabase
          .from('kyorangtalk_profiles')
          .select('id')
          .eq('nickname', nickname)
          .neq('id', user.id)
          .maybeSingle();

      if (existing != null) {
        setState(() {
          _error = '이미 사용 중인 닉네임이에요';
          _loading = false;
        });
        return;
      }

      final signupMethod = _getSignupMethod(user);
      final now = DateTime.now().toIso8601String();

      // ✨ 약관 동의 정보 포함
      final profileData = {
        'id': user.id,
        'nickname': nickname,
        'birthday': _birthday!.toIso8601String().split('T')[0],
        'phone_number': phoneE164,
        'status_message': status.isEmpty ? null : status,
        'avatar_url': user.userMetadata?['avatar_url'],
        'signup_method': signupMethod,
        // 약관 동의 기록
        'terms_agreed_at': TempSignupAgreement.termsAgreed ? now : null,
        'privacy_agreed_at':
            TempSignupAgreement.privacyAgreed ? now : null,
        'marketing_agreed': TempSignupAgreement.marketingAgreed,
        if (TempSignupAgreement.marketingAgreed)
          'marketing_agreed_at': now,
      };

      print('🟡 프로필 upsert 시도: $profileData');

      await supabase.from('kyorangtalk_profiles').upsert(profileData);

      print('🟢 프로필 upsert 성공!');

      // 약관 동의 정보 초기화
      TempSignupAgreement.clear();

      markProfileCreated();

      if (mounted) {
        print('🟢 /main 으로 이동');
        context.go('/main');
      }
    } catch (e) {
      print('🔴 온보딩 오류: $e');
      setState(() {
        _error = '오류가 발생했어요: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A0B3D),
                    Color(0xFF0F0F1F),
                    Color(0xFF080810),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: -100, left: -50, right: -50,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  Center(
                    child: AnimatedBuilder(
                      animation: _logoController,
                      builder: (_, __) => Transform.scale(
                        scale: _logoScaleAnim.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary
                                    .withOpacity(_logoGlowAnim.value),
                                blurRadius: 40,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        Colors.white,
                        AppTheme.primaryLight,
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      '환영해요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    '프로필을 설정해볼까요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),

                  const SizedBox(height: 40),

                  const _FieldLabel(label: '닉네임'),
                  const SizedBox(height: 8),
                  _GlassTextField(
                    controller: _nicknameController,
                    hint: '교랑이',
                    icon: Icons.emoji_emotions_outlined,
                    maxLength: 20,
                    onChanged: () => setState(() {}),
                    isValid:
                        _nicknameController.text.trim().length >= 2,
                  ),

                  const SizedBox(height: 20),

                  const _FieldLabel(label: '생일'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickBirthday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cake_outlined,
                            color: Colors.white.withOpacity(0.5),
                            size: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _birthday != null
                                  ? '${_birthday!.year}년 ${_birthday!.month}월 ${_birthday!.day}일'
                                  : '생일을 선택해주세요',
                              style: TextStyle(
                                color: _birthday != null
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (_birthday != null)
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF10B981),
                              size: 20,
                            )
                          else
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white.withOpacity(0.5),
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const _FieldLabel(label: '전화번호'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('🇰🇷', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text('+82',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 20,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                              _PhoneFormatter(),
                            ],
                            decoration: InputDecoration(
                              hintText: '010-0000-0000',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_isValidPhone(_phoneController.text))
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const _FieldLabel(
                    label: '상태 메시지',
                    hint: '(선택)',
                  ),
                  const SizedBox(height: 8),
                  _GlassTextField(
                    controller: _statusController,
                    hint: '간단한 상태 메시지를 남겨요',
                    icon: Icons.chat_bubble_outline,
                    maxLength: 50,
                  ),

                  const SizedBox(height: 16),

                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFEF4444)
                                .withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFEF4444), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  Container(
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: _canSubmit
                          ? LinearGradient(
                              colors: [
                                AppTheme.primary,
                                AppTheme.primaryLight,
                              ],
                            )
                          : null,
                      color: _canSubmit
                          ? null
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _canSubmit
                          ? [
                              BoxShadow(
                                color:
                                    AppTheme.primary.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                      border: _canSubmit
                          ? null
                          : Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _canSubmit ? _submit : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  '교랑톡 시작하기',
                                  style: TextStyle(
                                    color: _canSubmit
                                        ? Colors.white
                                        : Colors.white
                                            .withOpacity(0.4),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (!_canSubmit && _error == null)
                    Center(
                      child: Text(
                        '모든 필수 항목을 입력해주세요',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final String? hint;

  const _FieldLabel({required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int? maxLength;
  final VoidCallback? onChanged;
  final bool isValid;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLength,
    this.onChanged,
    this.isValid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        autocorrect: false,
        maxLength: maxLength,
        onChanged: (_) => onChanged?.call(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withOpacity(0.5),
            size: 20,
          ),
          suffixIcon: isValid
              ? const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 20,
                )
              : null,
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
          filled: false,
        ),
      ),
    );
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    String formatted = digits;

    if (digits.length > 3 && digits.length <= 7) {
      formatted = '${digits.substring(0, 3)}-${digits.substring(3)}';
    } else if (digits.length > 7 && digits.length <= 11) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length > 11) {
      formatted =
          '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, 11)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}