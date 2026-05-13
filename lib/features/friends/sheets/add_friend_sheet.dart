import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ═══════════════════════════════════════════════
// 👥 AddFriendSheet — RPC + 메시지 보내기
// ═══════════════════════════════════════════════

class AddFriendSheet extends ConsumerStatefulWidget {
  final String myId;
  final VoidCallback onSent;
  final void Function(Map<String, dynamic> user)? onMessage;

  const AddFriendSheet({
    super.key,
    required this.myId,
    required this.onSent,
    this.onMessage,
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

  Future<void> _searchByEmail() async {
    final raw = _emailController.text.trim();
    if (raw.isEmpty) return;
    final email = raw.toLowerCase();

    if (!_isValidEmail(email)) {
      setState(() => _error = '올바른 이메일 형식이 아니에요');
      return;
    }
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

  // ⭐ RPC 사용 (rejected 재요청 등 atomic 처리)
  Future<void> _sendRequest() async {
    if (_foundUser == null || _sending) return;
    setState(() => _sending = true);

    try {
      await Supabase.instance.client.rpc(
        'send_friend_request',
        params: {'target_user_id': _foundUser!['id']},
      );

      setState(() {
        _friendStatus = 'pending';
        _sending = false;
      });

      widget.onSent();

      if (mounted) {
        _showSnack(
            '${_foundUser!['nickname']}님에게 친구 요청을 보냈어요!');
      }
    } on PostgrestException catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        String msg;
        if (e.message.contains('already_friends')) {
          msg = '이미 친구예요';
          setState(() => _friendStatus = 'accepted');
        } else if (e.message.contains('already_pending')) {
          msg = '이미 요청 중이에요';
          setState(() => _friendStatus = 'pending');
        } else if (e.message.contains('blocked')) {
          msg = '차단된 유저예요';
          setState(() => _friendStatus = 'blocked');
        } else {
          msg = '요청 실패: ${e.message}';
        }
        _showSnack(msg);
      }
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) _showSnack('요청 실패: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _sendMessage() {
    if (_foundUser == null) return;
    Navigator.pop(context);
    widget.onMessage?.call(_foundUser!);
  }

  Widget _buildActions() {
    if (_friendStatus == 'blocked') {
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFEF4444).withOpacity(0.15),
              const Color(0xFFEF4444).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFEF4444).withOpacity(0.3),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded,
                color: Color(0xFFEF4444), size: 18),
            SizedBox(width: 8),
            Text('차단된 유저예요',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2)),
          ],
        ),
      );
    }

    return Row(
      children: [
        if (widget.onMessage != null) ...[
          Expanded(child: _MessageButton(onTap: _sendMessage)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: _FriendActionButton(
            status: _friendStatus,
            sending: _sending,
            onTap: _sendRequest,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          controller: sc,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin:
                      const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.25),
                            AppTheme.primary.withOpacity(0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.person_add_alt_1_rounded,
                          color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('친구 추가',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textMain,
                            letterSpacing: -0.4)),
                  ],
                ),
                const SizedBox(height: 18),

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
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.textSub,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    tabs: const [
                      Tab(
                        height: 38,
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.alternate_email_rounded,
                                size: 14),
                            SizedBox(width: 5),
                            Text('이메일'),
                          ],
                        ),
                      ),
                      Tab(
                        height: 38,
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_rounded, size: 14),
                            SizedBox(width: 5),
                            Text('전화번호'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                SizedBox(
                  height: 52,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEmailInput(),
                      _buildPhoneInput(),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (_error != null) _ErrorCard(message: _error!),
                if (_foundUser != null) _buildResultCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.08),
            AppTheme.primary.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: AvatarWidget(
              url: _foundUser!['avatar_url'] as String?,
              name: _foundUser!['nickname'] as String?,
              size: 76,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _foundUser!['nickname'] as String? ?? '알 수 없음',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppTheme.textMain,
                letterSpacing: -0.4),
          ),
          if (_foundUser!['status_message'] != null &&
              (_foundUser!['status_message'] as String).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _foundUser!['status_message'] as String,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSub,
                  height: 1.4,
                  letterSpacing: -0.2),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildEmailInput() {
    return Row(
      children: [
        Expanded(
          child: _SearchTextField(
            controller: _emailController,
            hint: 'example@email.com',
            prefix: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _searchByEmail(),
          ),
        ),
        const SizedBox(width: 8),
        _SearchButton(
          loading: _searching,
          onTap: _searchByEmail,
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(13),
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
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                const SizedBox(width: 8),
                Container(
                    width: 1, height: 16, color: AppTheme.border),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    cursorColor: AppTheme.primary,
                    style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                      _PhoneFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: '010-0000-0000',
                      hintStyle: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w400),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _searchByPhone(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SearchButton(
          loading: _searching,
          onTap: _searchByPhone,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// 친구 액션 버튼
// ═════════════════════════════════════════════
class _FriendActionButton extends StatelessWidget {
  final String? status;
  final bool sending;
  final VoidCallback onTap;

  const _FriendActionButton({
    required this.status,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'accepted':
        return Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.18),
                AppTheme.primary.withOpacity(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: AppTheme.primary.withOpacity(0.3),
                width: 0.8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt_rounded,
                  color: AppTheme.primary, size: 16),
              SizedBox(width: 6),
              Text('이미 친구',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
            ],
          ),
        );

      case 'pending':
        return Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded,
                  color: AppTheme.textSub, size: 16),
              const SizedBox(width: 6),
              Text('요청 중',
                  style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2)),
            ],
          ),
        );

      default:
        return Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary,
                AppTheme.primary.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: sending ? null : onTap,
                child: Center(
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1_rounded,
                                color: Colors.white, size: 17),
                            SizedBox(width: 6),
                            Text('친구 요청',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
    }
  }
}

// ═════════════════════════════════════════════
// 메시지 버튼
// ═════════════════════════════════════════════
class _MessageButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MessageButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF06B6D4);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cyan, Color(0xFF0891B2)],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: cyan.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_rounded,
                      color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('메시지',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 검색 텍스트 필드
// ═════════════════════════════════════════════
class _SearchTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefix;
  final TextInputType keyboardType;
  final ValueChanged<String> onSubmitted;

  const _SearchTextField({
    required this.controller,
    required this.hint,
    required this.prefix,
    required this.keyboardType,
    required this.onSubmitted,
  });

  @override
  State<_SearchTextField> createState() => _SearchTextFieldState();
}

class _SearchTextFieldState extends State<_SearchTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted && _focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _focused
              ? AppTheme.primary.withOpacity(0.5)
              : AppTheme.border,
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        keyboardType: widget.keyboardType,
        cursorColor: AppTheme.primary,
        style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w400),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 4, vertical: 14),
          prefixIcon: Icon(widget.prefix,
              color: _focused
                  ? AppTheme.primary
                  : AppTheme.textSub,
              size: 18),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 검색 버튼
// ═════════════════════════════════════════════
class _SearchButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _SearchButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.search_rounded,
                              color: Colors.white, size: 17),
                          SizedBox(width: 4),
                          Text('검색',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 에러 카드
// ═════════════════════════════════════════════
class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEF4444).withOpacity(0.12),
            const Color(0xFFEF4444).withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFEF4444).withOpacity(0.3),
            width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 전화번호 포맷터
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