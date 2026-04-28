import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

const String _supportEmail = 'rywls123450@gmail.com';

class InquiryScreen extends ConsumerStatefulWidget {
  const InquiryScreen({super.key});

  @override
  ConsumerState<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends ConsumerState<InquiryScreen> {
  final _subjectController = TextEditingController();
  final _contentController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final content = _contentController.text.trim();

    if (subject.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final info = await PackageInfo.fromPlatform();

      // ✨ DB에 저장 (자동으로 트리거가 이메일 발송!)
      await Supabase.instance.client
          .from('kyorangtalk_inquiries')
          .insert({
        'user_id': user?.id,
        'user_email': user?.email,
        'subject': subject,
        'content': content,
        'app_version': '${info.version}+${info.buildNumber}',
      });

      if (mounted) {
        // 성공 다이얼로그
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Column(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle,
                      color: AppTheme.primary, size: 36),
                ),
                const SizedBox(height: 12),
                Text('문의 접수 완료',
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '소중한 의견 감사해요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '확인 후 빠르게 답변 드릴게요\n(보통 1~2일 내)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                  ),
                  child: const Text('확인',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );

        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전송 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('문의하기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary),
                  )
                : Text('보내기',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '불편사항, 건의사항, 오류 신고 등 자유롭게 알려주세요',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMain,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text('제목',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub)),
              const SizedBox(height: 8),
              TextField(
                controller: _subjectController,
                style: TextStyle(color: AppTheme.textMain),
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: '간단한 제목을 입력해주세요',
                  counterStyle: TextStyle(
                      color: AppTheme.textSub, fontSize: 11),
                ),
              ),
              const SizedBox(height: 16),

              Text('내용',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub)),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                style: TextStyle(color: AppTheme.textMain),
                maxLength: 1000,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText:
                      '문의하실 내용을 자세히 적어주세요.\n오류의 경우 발생 시점과 상황을 알려주시면 빠른 해결에 도움이 돼요.',
                  counterStyle: TextStyle(
                      color: AppTheme.textSub, fontSize: 11),
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mail_outline,
                            color: AppTheme.textSub, size: 14),
                        const SizedBox(width: 6),
                        Text(_supportEmail,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSub,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '보내기를 누르면 문의가 접수되고, 관리자에게 자동으로 전달돼요.\n답변은 보통 1~2일 내로 받으실 수 있어요.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}