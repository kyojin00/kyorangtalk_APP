import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════
// 친구 추가 바텀시트
//
// 위치: lib/features/friends/sheets/add_friend_sheet.dart
//
// 탭 2개:
//   - 이메일   : kyorangtalk_profiles.email 컬럼으로 검색
//                (가짜 이메일 @phone.kyorang.com 은 차단)
//   - 전화번호 : kyorangtalk_profiles.phone_number 로 검색
//
// (닉네임 검색은 동명이인 문제로 제거됨)
// ═══════════════════════════════════════════════

class AddFriendSheet extends ConsumerStatefulWidget {
  final String myId;
  final VoidCallback onSent;

  const AddFriendSheet({
    super.key,
    required this.myId,
    required this.onSent,
  });

  @override
  ConsumerState<AddFriendSheet> createState() =>
      _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<AddFriendSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _searching = false;
  bool _sending = false;
  Map<String, dynamic>? _foundUser;
  String? _friendStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _foundUser = null;
          _friendStatus = null;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════
  // 검증 유틸
  // ═════════════════════════════════════════════
  bool _isValidEmail(String value) {
    return RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$')
        .hasMatch(value);
  }

  bool _isValidKoreanPhone(String value) {
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

  // ═════════════════════════════════════════════
  // 이메일로 검색
  // ═════════════════════════════════════════════
  Future<void> _searchByEmail() async {
    final raw = _emailController.text.trim();
    if (raw.isEmpty) return;

    final email = raw.toLowerCase();

    if (!_isValidEmail(email)) {
      setState(() => _error = '올바른 이메일 형식이 아니에요');
      return;
    }

    // 전화번호 가입자의 가짜 이메일은 차단
    if (email.endsWith('@phone.kyorang.com')) {
      setState(() => _error = '이 이메일로는 검색할 수 없어요');
      return;
    }

    setState(() {
      _searching = true;
      _foundUser = null;
      _friendStatus = null;
      _error = null;
    });

    final supabase = Supabase.instance.client;

    // ilike: LOWER(email) 인덱스 활용 + 대소문자 무시
    final profile = await supabase
        .from('kyorangtalk_profiles')
        .select('id, nickname, avatar_url, status_message, email')
        .ilike('email', email)
        .neq('id', widget.myId)
        .maybeSingle();

    if (profile == null) {
      setState(() {
        _searching = false;
        _error = '해당 이메일로 가입한 유저를 찾을 수 없어요';
      });
      return;
    }

    await _loadFriendStatus(profile);
  }

  // ═════════════════════════════════════════════
  // 전화번호로 검색
  // ═════════════════════════════════════════════
  Future<void> _searchByPhone() async {
    final phoneText = _phoneController.text.trim();
    if (!_isValidKoreanPhone(phoneText)) {
      setState(() => _error = '올바른 전화번호를 입력해주세요 (010으로 시작)');
      return;
    }

    setState(() {
      _searching = true;
      _foundUser = null;
      _friendStatus = null;
      _error = null;
    });

    final phoneE164 = _toE164(phoneText);
    final supabase = Supabase.instance.client;

    final profile = await supabase
        .from('kyorangtalk_profiles')
        .select(
            'id, nickname, avatar_url, status_message, phone_number')
        .eq('phone_number', phoneE164)
        .neq('id', widget.myId)
        .maybeSingle();

    if (profile == null) {
      setState(() {
        _searching = false;
        _error = '해당 전화번호로 가입한 유저가 없어요';
      });
      return;
    }

    await _loadFriendStatus(profile);
  }

  Future<void> _loadFriendStatus(Map<String, dynamic> profile) async {
    final supabase = Supabase.instance.client;

    final existing = await supabase
        .from('kyorangtalk_friends')
        .select('status, requester_id')
        .or('and(requester_id.eq.${widget.myId},receiver_id.eq.${profile['id']}),'
            'and(requester_id.eq.${profile['id']},receiver_id.eq.${widget.myId})')
        .maybeSingle();

    setState(() {
      _searching = false;
      _foundUser = profile;
      _friendStatus = existing?['status'] as String? ?? 'none';
    });
  }

  Future<void> _sendRequest() async {
    if (_foundUser == null || _sending) return;

    setState(() => _sending = true);

    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .insert({
      'requester_id': widget.myId,
      'receiver_id':  _foundUser!['id'],
      'status':       'pending',
    });

    setState(() {
      _friendStatus = 'pending';
      _sending = false;
    });

    widget.onSent();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${_foundUser!['nickname']}님에게 친구 요청을 보냈어요!'),
          backgroundColor: AppTheme.bgCard,
        ),
      );
    }
  }

  // ═════════════════════════════════════════════
  // 친구 상태별 액션 버튼
  // ═════════════════════════════════════════════
  Widget _buildActionButton() {
    switch (_friendStatus) {
      case 'accepted':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.primary.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, color: AppTheme.primary, size: 16),
              SizedBox(width: 6),
              Text('이미 친구예요',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
      case 'pending':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text('요청 중',
              style: TextStyle(
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600)),
        );
      case 'blocked':
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('차단된 유저',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700)),
        );
      default:
        return GestureDetector(
          onTap: _sending ? null : _sendRequest,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_outlined,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('친구 요청 보내기',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('친구 추가',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
              const SizedBox(height: 16),

              // ── 탭바: 이메일 / 전화번호 ──
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSub,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.email_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('이메일'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('전화번호'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 68,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEmailInput(),
                    _buildPhoneInput(),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              if (_foundUser != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      AvatarWidget(
                        url: _foundUser!['avatar_url'] as String?,
                        name: _foundUser!['nickname'] as String?,
                        size: 72,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _foundUser!['nickname'] as String? ??
                            '알 수 없음',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain),
                      ),
                      if (_foundUser!['status_message'] != null &&
                          (_foundUser!['status_message'] as String)
                              .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _foundUser!['status_message'] as String,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSub),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildActionButton(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════
  // 이메일 입력 필드
  // ═════════════════════════════════════════════
  Widget _buildEmailInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: TextField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              style: TextStyle(color: AppTheme.textMain),
              decoration: InputDecoration(
                hintText: 'example@email.com',
                hintStyle: TextStyle(color: AppTheme.textSub),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 12),
                prefixIcon: Icon(Icons.alternate_email,
                    color: AppTheme.textSub, size: 18),
              ),
              onSubmitted: (_) => _searchByEmail(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _searching ? null : _searchByEmail,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _searching
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('검색',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════
  // 전화번호 입력 필드
  // ═════════════════════════════════════════════
  Widget _buildPhoneInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Text('🇰🇷', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text('+82',
                    style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                    width: 1, height: 16, color: AppTheme.border),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w600),
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
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _searchByPhone(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _searching ? null : _searchByPhone,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _searching
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('검색',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// 전화번호 포맷터: 010-0000-0000 형태로 자동 변환
// (이 파일 내부에서만 사용)
// ═════════════════════════════════════════════
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