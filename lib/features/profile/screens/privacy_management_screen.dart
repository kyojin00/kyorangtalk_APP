import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/screens/terms_of_service_screen.dart';
import '../../auth/screens/privacy_policy_screen.dart';

class PrivacyManagementScreen extends ConsumerStatefulWidget {
  const PrivacyManagementScreen({super.key});

  @override
  ConsumerState<PrivacyManagementScreen> createState() =>
      _PrivacyManagementScreenState();
}

class _PrivacyManagementScreenState
    extends ConsumerState<PrivacyManagementScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('kyorangtalk_profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _profile = data;
          _loading = false;
        });
      }
    } catch (e) {
      print('프로필 로드 오류: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final date = DateTime.parse(iso);
      return DateFormat('yyyy.MM.dd').format(date);
    } catch (e) {
      return '-';
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '-';
    try {
      final date = DateTime.parse(iso);
      return DateFormat('yyyy.MM.dd HH:mm').format(date);
    } catch (e) {
      return '-';
    }
  }

  String _getSignupMethodLabel(String? method) {
    switch (method) {
      case 'email':
        return '이메일';
      case 'phone':
        return '전화번호';
      case 'google':
        return 'Google';
      default:
        return '-';
    }
  }

  // ✨ 전화번호 포맷 수정!
  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '-';
    
    // +82로 시작하면 앞부분 제거
    String number = phone;
    if (number.startsWith('+82')) {
      number = '0${number.substring(3)}';
    }
    
    // 숫자만 추출
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    
    // 11자리: 010-XXXX-XXXX
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    // 10자리: 010-XXX-XXXX
    else if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    
    return phone;
  }

  Future<void> _handleDelete() async {
    // 1차 확인
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppTheme.error, size: 24),
            const SizedBox(width: 10),
            Text('회원 탈퇴',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '정말 탈퇴하시겠어요?',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '탈퇴 시 아래 내용이 모두 삭제됩니다:',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            _DeleteWarning('모든 채팅 내역'),
            _DeleteWarning('친구 목록'),
            _DeleteWarning('프로필 정보'),
            _DeleteWarning('참여 중인 그룹/오픈채팅'),
            _DeleteWarning('계정 정보 (재가입 가능)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.error, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '삭제된 데이터는 복구할 수 없어요',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
            ),
            child: const Text('다음',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm1 != true) return;

    // 2차 확인 (텍스트 입력)
    if (!mounted) return;
    final deleteController = TextEditingController();
    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('최종 확인',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '정말 탈퇴하시려면\n아래에 "탈퇴하기"를 입력해주세요',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: deleteController,
                textAlign: TextAlign.center,
                autofocus: true,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: '탈퇴하기',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () {
              if (deleteController.text.trim() == '탈퇴하기') {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('"탈퇴하기"를 정확히 입력해주세요'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
            ),
            child: const Text('탈퇴',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm2 != true) return;

    // 실제 탈퇴 처리
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final supabase = Supabase.instance.client;

      // ✨ Edge Function 호출로 Auth 계정까지 완전 삭제
      final response = await supabase.functions.invoke(
        'delete-account',
        method: HttpMethod.post,
      );

      if (response.status != 200) {
        throw Exception('서버 오류: ${response.status}');
      }

      // 로그아웃
      await supabase.auth.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('회원 탈퇴가 완료되었어요'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      print('탈퇴 오류: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('탈퇴 중 오류가 발생했어요: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('개인정보 관리',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.primary,
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      icon: Icons.person_outline,
                      title: '내 정보',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.person_outline,
                            label: '닉네임',
                            value:
                                _profile?['nickname'] as String? ??
                                    '-',
                          ),
                          _Divider(),
                          _InfoRow(
                            icon: Icons.email_outlined,
                            label: '이메일',
                            value: user?.email?.endsWith(
                                        '@phone.kyorang.com') ==
                                    true
                                ? '-'
                                : user?.email ?? '-',
                          ),
                          _Divider(),
                          _InfoRow(
                            icon: Icons.phone_android_outlined,
                            label: '전화번호',
                            value: _formatPhone(
                                _profile?['phone_number'] as String?),
                          ),
                          _Divider(),
                          _InfoRow(
                            icon: Icons.cake_outlined,
                            label: '생일',
                            value: _formatDate(
                                _profile?['birthday'] as String?),
                          ),
                          _Divider(),
                          _InfoRow(
                            icon: Icons.login_outlined,
                            label: '가입 방법',
                            value: _getSignupMethodLabel(
                                _profile?['signup_method']
                                    as String?),
                          ),
                          _Divider(),
                          _InfoRow(
                            icon: Icons.calendar_today_outlined,
                            label: '가입일',
                            value: _formatDate(
                                _profile?['created_at'] as String?),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    _SectionHeader(
                      icon: Icons.assignment_outlined,
                      title: '약관 동의 내역',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          _AgreementInfoRow(
                            label: '이용약관',
                            agreed: _profile?['terms_agreed_at'] !=
                                null,
                            date: _formatDateTime(
                                _profile?['terms_agreed_at']
                                    as String?),
                            onViewTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const TermsOfServiceScreen(),
                                ),
                              );
                            },
                          ),
                          _Divider(),
                          _AgreementInfoRow(
                            label: '개인정보처리방침',
                            agreed: _profile?['privacy_agreed_at'] !=
                                null,
                            date: _formatDateTime(
                                _profile?['privacy_agreed_at']
                                    as String?),
                            onViewTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PrivacyPolicyScreen(),
                                ),
                              );
                            },
                          ),
                          _Divider(),
                          _AgreementInfoRow(
                            label: '마케팅 알림 수신',
                            agreed: _profile?['marketing_agreed']
                                    as bool? ??
                                false,
                            date: _formatDateTime(
                                _profile?['marketing_agreed_at']
                                    as String?),
                            optional: true,
                            onViewTap: null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    _SectionHeader(
                      icon: Icons.warning_amber_rounded,
                      title: '계정 관리',
                      iconColor: AppTheme.error,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                AppTheme.error.withOpacity(0.2)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleDelete,
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.error
                                        .withOpacity(0.15),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      Icons.person_remove_outlined,
                                      color: AppTheme.error,
                                      size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '회원 탈퇴',
                                        style: TextStyle(
                                          color: AppTheme.error,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '계정과 모든 데이터를 삭제합니다',
                                        style: TextStyle(
                                          color: AppTheme.textSub,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: AppTheme.error
                                      .withOpacity(0.5),
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            color: iconColor ?? AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textMain,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSub, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgreementInfoRow extends StatelessWidget {
  final String label;
  final bool agreed;
  final String date;
  final bool optional;
  final VoidCallback? onViewTap;

  const _AgreementInfoRow({
    required this.label,
    required this.agreed,
    required this.date,
    this.optional = false,
    required this.onViewTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            agreed ? Icons.check_circle : Icons.cancel,
            color:
                agreed ? AppTheme.success : AppTheme.textMuted,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      optional ? '(선택)' : '(필수)',
                      style: TextStyle(
                        color: optional
                            ? AppTheme.textSub
                            : AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  agreed ? '동의일: $date' : '동의하지 않음',
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onViewTap != null)
            GestureDetector(
              onTap: onViewTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '보기',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: AppTheme.border,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _DeleteWarning extends StatelessWidget {
  final String text;

  const _DeleteWarning(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text('•  ',
              style: TextStyle(
                  color: AppTheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          Text(
            text,
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}