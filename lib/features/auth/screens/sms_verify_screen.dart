import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class SmsVerifyScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final String phoneDisplay;

  const SmsVerifyScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    required this.phoneDisplay,
  });

  @override
  ConsumerState<SmsVerifyScreen> createState() => _SmsVerifyScreenState();
}

class _SmsVerifyScreenState extends ConsumerState<SmsVerifyScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _resending = false;
  String? _error;
  String _verificationId = '';
  Timer? _timer;
  int _remainingSeconds = 180;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startTimer();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _remainingSeconds = 180;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  String get _timerText {
    final minutes = (_remainingSeconds / 60).floor();
    final seconds = _remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '6자리 인증번호를 입력해주세요');
      return;
    }

    if (_remainingSeconds <= 0) {
      setState(() => _error = '인증 시간이 만료됐어요. 재전송을 눌러주세요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final service = ref.read(authServiceProvider);

    try {
      await service.verifySmsCode(
        verificationId: _verificationId,
        smsCode: code,
        phoneNumber: widget.phoneNumber,
      );

      if (!mounted) return;

      _timer?.cancel();

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      context.go('/');
    } catch (e) {
      final errorMsg = e.toString();
      String userMsg = '인증에 실패했어요';
      if (errorMsg.contains('invalid-verification-code')) {
        userMsg = '인증번호가 올바르지 않아요';
      } else if (errorMsg.contains('session-expired')) {
        userMsg = '인증 시간이 만료됐어요';
      } else if (errorMsg.contains('too-many-requests')) {
        userMsg = '너무 많이 시도했어요. 잠시 후 다시 시도해주세요';
      }
      if (mounted) {
        setState(() {
          _error = userMsg;
          _loading = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resending) return;

    setState(() {
      _resending = true;
      _error = null;
      _codeController.clear();
    });

    final service = ref.read(authServiceProvider);

    try {
      await service.sendSmsCode(
        phoneNumber: widget.phoneNumber,
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resending = false;
          });
          _startTimer();
          _showSnack('인증번호를 다시 보냈어요');
        },
        onFailed: (err) {
          if (!mounted) return;
          setState(() {
            _error = err;
            _resending = false;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '재전송에 실패했어요';
          _resending = false;
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
          '인증번호 입력',
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
                  child: const Icon(Icons.sms_outlined,
                      color: AppTheme.primary, size: 32),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                '인증번호를 입력해주세요',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.phoneDisplay}로\n6자리 인증번호를 보냈어요',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSub, height: 1.5),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 36),

              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _error != null
                          ? AppTheme.error
                          : AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        color: AppTheme.textSub, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          hintText: '000000',
                          hintStyle: TextStyle(
                              color: AppTheme.textMuted,
                              letterSpacing: 8),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: (v) {
                          if (_error != null) {
                            setState(() => _error = null);
                          }
                          if (v.length == 6) {
                            _verifyCode();
                          }
                        },
                      ),
                    ),
                    if (_remainingSeconds > 0)
                      Text(
                        _timerText,
                        style: TextStyle(
                          color: _remainingSeconds < 30
                              ? AppTheme.error
                              : AppTheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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

              const SizedBox(height: 20),

              Center(
                child: TextButton.icon(
                  onPressed: _resending ? null : _resendCode,
                  icon: _resending
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.textSub),
                        )
                      : Icon(Icons.refresh,
                          color: AppTheme.textSub, size: 16),
                  label: Text(
                    _remainingSeconds > 0
                        ? '인증번호가 오지 않나요?'
                        : '인증번호 재전송',
                    style: TextStyle(
                        color: AppTheme.textSub, fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _loading ? null : _verifyCode,
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
                        '확인',
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