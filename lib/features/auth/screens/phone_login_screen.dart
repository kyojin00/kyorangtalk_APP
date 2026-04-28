import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'sms_verify_screen.dart';

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String _toE164(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      return '+82${digits.substring(1)}';
    }
    return '+82$digits';
  }

  bool _isValidKoreanPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^010\d{8}$').hasMatch(digits);
  }

  Future<void> _sendCode() async {
    final phoneText = _phoneController.text.trim();

    if (!_isValidKoreanPhone(phoneText)) {
      setState(() => _error = '올바른 전화번호를 입력해주세요 (010으로 시작)');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final phoneE164 = _toE164(phoneText);
    final service = ref.read(authServiceProvider);

    try {
      await service.sendSmsCode(
        phoneNumber: phoneE164,
        onCodeSent: (verificationId) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SmsVerifyScreen(
                verificationId: verificationId,
                phoneNumber: phoneE164,
                phoneDisplay: phoneText,
              ),
            ),
          );
          setState(() => _loading = false);
        },
        onFailed: (err) {
          if (!mounted) return;
          setState(() {
            _error = err;
            _loading = false;
          });
        },
        onAutoVerified: () {
          if (!mounted) return;
          _showSnack('인증에 성공했어요!');
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '오류가 발생했어요: $e';
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: AppTheme.textMain)),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '전화번호로 시작하기',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      color: AppTheme.primary, size: 32),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                '전화번호를 입력해주세요',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '인증번호를 문자로 보내드릴게요',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSub),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _error != null
                          ? AppTheme.error
                          : AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('🇰🇷', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text('+82',
                        style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 20,
                      color: AppTheme.border,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                          _PhoneFormatter(),
                        ],
                        decoration: InputDecoration(
                          hintText: '010-0000-0000',
                          hintStyle:
                              TextStyle(color: AppTheme.textMuted),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: (_) {
                          if (_error != null) {
                            setState(() => _error = null);
                          }
                        },
                        onSubmitted: (_) => _sendCode(),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.error, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 13)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.textSub, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '전화번호 인증 안내',
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• 본인 명의 전화번호를 입력해주세요\n'
                            '• 인증번호는 SMS로 발송돼요\n'
                            '• 수수료는 발생하지 않아요',
                            style: TextStyle(
                              color: AppTheme.textSub,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _loading ? null : _sendCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        '인증번호 받기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),

              const SizedBox(height: 24),
            ],
          ),
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