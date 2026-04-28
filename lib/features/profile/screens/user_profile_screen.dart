import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/chat/models/chat_room_model.dart';
import '../../reports/widgets/report_dialog.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String nickname;
  final String? avatarUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.nickname,
    this.avatarUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isSubProfile = false;
  List<Map<String, dynamic>> _stickers = [];
  bool _loading = true;
  String _friendStatus = 'none';
  bool _actionLoading  = false;
  bool _isBlocked      = false;
  final _myId = Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadProfileWithSubProfile(),
      _loadFriendStatus(),
      _loadBlockStatus(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProfileWithSubProfile() async {
    final supabase = Supabase.instance.client;

    final subProfileData = await supabase
        .from('kyorangtalk_sub_profiles')
        .select('''
          id, name, nickname, avatar_url, background_url, status_message,
          kyorangtalk_sub_profile_viewers!inner(viewer_id)
        ''')
        .eq('user_id', widget.userId)
        .eq('kyorangtalk_sub_profile_viewers.viewer_id', _myId)
        .maybeSingle();

    Map<String, dynamic>? finalProfile;
    bool isSub = false;

    if (subProfileData != null) {
      finalProfile = {
        'nickname':       subProfileData['nickname'] ?? widget.nickname,
        'avatar_url':     subProfileData['avatar_url'],
        'background_url': subProfileData['background_url'],
        'status_message': subProfileData['status_message'],
      };
      isSub = true;
    } else {
      final mainData = await supabase
          .from('kyorangtalk_profiles')
          .select('*')
          .eq('id', widget.userId)
          .maybeSingle();
      finalProfile = mainData;
    }

    if (mounted) {
      setState(() {
        _profile = finalProfile;
        _isSubProfile = isSub;
      });
    }

    if (!isSub) {
      await _loadStickers();
    }
  }

  Future<void> _loadStickers() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_profile_stickers')
        .select('*')
        .eq('user_id', widget.userId);
    if (mounted) setState(() => _stickers = List.from(data));
  }

  Future<void> _loadFriendStatus() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_friends')
        .select('status')
        .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.userId}),'
            'and(requester_id.eq.${widget.userId},receiver_id.eq.$_myId)')
        .maybeSingle();
    if (mounted) {
      setState(() =>
          _friendStatus = data?['status'] as String? ?? 'none');
    }
  }

  Future<void> _loadBlockStatus() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_blocks')
        .select('id')
        .eq('blocker_id', _myId)
        .eq('blocked_id', widget.userId)
        .maybeSingle();
    if (mounted) {
      setState(() => _isBlocked = data != null);
    }
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _actionLoading = true);
    await Supabase.instance.client
        .from('kyorangtalk_friends')
        .insert({
      'requester_id': _myId,
      'receiver_id':  widget.userId,
      'status':       'pending',
    });
    setState(() {
      _friendStatus  = 'pending';
      _actionLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('친구 요청을 보냈어요!'),
            backgroundColor: AppTheme.bgCard),
      );
    }
  }

  // ✨ 신고 기능
  Future<void> _reportUser() async {
    await showReportUserDialog(
      context: context,
      reportedUserId: widget.userId,
      reportedNickname: widget.nickname,
    );
  }

  Future<void> _blockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('${widget.nickname}님 차단하기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: Text(
          '차단하면 다음과 같이 동작해요:\n\n'
          '• 서로 친구 목록에서 사라져요\n'
          '• 메시지를 주고받을 수 없어요\n'
          '• 프로필을 볼 수 없어요\n'
          '• 검색에 노출되지 않아요\n\n'
          '차단은 설정에서 해제할 수 있어요.',
          style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
              height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('차단',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _actionLoading = true);

    try {
      final supabase = Supabase.instance.client;

      await supabase.from('kyorangtalk_blocks').insert({
        'blocker_id': _myId,
        'blocked_id': widget.userId,
      });

      await supabase
          .from('kyorangtalk_friends')
          .delete()
          .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.userId}),'
              'and(requester_id.eq.${widget.userId},receiver_id.eq.$_myId)');

      if (mounted) {
        setState(() {
          _isBlocked = true;
          _friendStatus = 'none';
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${widget.nickname}님을 차단했어요'),
              backgroundColor: AppTheme.bgCard),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('차단 실패: $e'),
              backgroundColor: AppTheme.bgCard),
        );
      }
    }
  }

  Future<void> _unblockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('차단 해제',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.nickname}님의 차단을 해제하시겠어요?\n'
          '다시 메시지를 주고받을 수 있어요.',
          style: TextStyle(
              color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('해제',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _actionLoading = true);

    try {
      await Supabase.instance.client
          .from('kyorangtalk_blocks')
          .delete()
          .eq('blocker_id', _myId)
          .eq('blocked_id', widget.userId);

      if (mounted) {
        setState(() {
          _isBlocked = false;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${widget.nickname}님의 차단을 해제했어요'),
              backgroundColor: AppTheme.bgCard),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('해제 실패: $e'),
              backgroundColor: AppTheme.bgCard),
        );
      }
    }
  }

  Future<void> _startChat() async {
    final supabase = Supabase.instance.client;

    final existing = await supabase
        .from('kyorangtalk_rooms')
        .select('*')
        .or('and(user1_id.eq.$_myId,user2_id.eq.${widget.userId}),'
            'and(user1_id.eq.${widget.userId},user2_id.eq.$_myId)')
        .maybeSingle();

    String roomId;
    if (existing != null) {
      roomId = existing['id'] as String;
    } else {
      final newRoom = await supabase
          .from('kyorangtalk_rooms')
          .insert({
            'user1_id': _myId,
            'user2_id': widget.userId,
          })
          .select()
          .single();
      roomId = newRoom['id'] as String;
    }

    if (!mounted) return;

    final room = ChatRoomModel(
      partnerId:       widget.userId,
      partnerUsername: _profile?['nickname'] as String? ??
          widget.nickname,
      partnerName:     _profile?['nickname'] as String? ??
          widget.nickname,
      partnerAvatar:   _profile?['avatar_url'] as String?,
      lastMessage:     '',
      lastTime:        DateTime.now(),
      unreadCount:     0,
      isSent:          false,
      roomId:          roomId,
    );

    context.pop();
    context.push('/main/chat/$roomId', extra: room);
  }

  void _showAvatarFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(url,
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _getAvatarUrl() {
    final profileAvatar = _profile?['avatar_url'] as String?;
    if (_isSubProfile) {
      return profileAvatar;
    }
    return profileAvatar ?? widget.avatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _profile?['nickname'] as String? ??
        widget.nickname;
    final avatar = _getAvatarUrl();
    final background = _profile?['background_url'] as String?;
    final statusMessage = _profile?['status_message'] as String?;
    final isMe      = widget.userId == _myId;
    final isFriend  = _friendStatus == 'accepted';
    final isPending = _friendStatus == 'pending';

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary))
          : Stack(
              children: [
                Positioned.fill(
                  child: background != null
                      ? Image.network(background,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(
                                  color: const Color(0xFF1E1B3A)))
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF1E1B3A),
                                AppTheme.bg,
                              ],
                            ),
                          ),
                        ),
                ),

                if (background != null)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.black.withOpacity(0.1),
                            AppTheme.bg.withOpacity(0.3),
                            AppTheme.bg,
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),

                ..._stickers.map((sticker) {
                  final id = sticker['id'] as String;
                  final emoji = sticker['emoji'] as String;
                  final x =
                      (sticker['pos_x'] as num?)?.toDouble() ?? 0.5;
                  final y =
                      (sticker['pos_y'] as num?)?.toDouble() ?? 0.4;
                  final scale =
                      (sticker['scale'] as num?)?.toDouble() ?? 1.0;
                  final size = 60.0 * scale;

                  return Positioned(
                    key: ValueKey(id),
                    left: x * screenWidth - size / 2,
                    top:  y * screenHeight - size / 2,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Center(
                        child: Text(emoji,
                            style: TextStyle(fontSize: size * 0.7)),
                      ),
                    ),
                  );
                }),

                SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 24),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          if (!isMe)
                            PopupMenuButton<String>(
                              color: AppTheme.bgCard,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white),
                              onSelected: (value) {
                                if (value == 'report') {
                                  _reportUser();
                                } else if (value == 'block') {
                                  _blockUser();
                                } else if (value == 'unblock') {
                                  _unblockUser();
                                }
                              },
                              itemBuilder: (_) => [
                                // ✨ 신고하기 (신규!)
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag_outlined,
                                          color: Color(0xFFEF4444),
                                          size: 18),
                                      SizedBox(width: 10),
                                      Text('신고하기',
                                          style: TextStyle(
                                              color: Color(0xFFEF4444),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                if (_isBlocked)
                                  PopupMenuItem(
                                    value: 'unblock',
                                    child: Row(
                                      children: [
                                        Icon(
                                            Icons
                                                .check_circle_outline,
                                            color:
                                                AppTheme.primary,
                                            size: 18),
                                        const SizedBox(width: 10),
                                        Text('차단 해제',
                                            style: TextStyle(
                                                color: AppTheme
                                                    .primary,
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight
                                                        .w600)),
                                      ],
                                    ),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Row(
                                      children: [
                                        Icon(Icons.block,
                                            color: Color(
                                                0xFFEF4444),
                                            size: 18),
                                        SizedBox(width: 10),
                                        Text('차단하기',
                                            style: TextStyle(
                                                color: Color(
                                                    0xFFEF4444),
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight
                                                        .w600)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),

                      const Spacer(flex: 2),

                      GestureDetector(
                        onTap: avatar != null
                            ? () => _showAvatarFullscreen(avatar)
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary
                                    .withOpacity(0.3),
                                blurRadius: 20,
                              ),
                            ],
                            border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 2),
                          ),
                          child: AvatarWidget(
                            url:  avatar,
                            name: nickname,
                            size: 100,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        nickname,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ]),
                      ),

                      if (statusMessage != null &&
                          statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40),
                          child: Text(
                            statusMessage,
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.white
                                    .withOpacity(0.85),
                                shadows: [
                                  Shadow(
                                    color: Colors.black
                                        .withOpacity(0.5),
                                    blurRadius: 6,
                                  ),
                                ]),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

                      const Spacer(flex: 3),

                      if (!isMe)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 20),
                          child: _buildActions(
                              isFriend:  isFriend,
                              isPending: isPending),
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildActions({
    required bool isFriend,
    required bool isPending,
  }) {
    if (_isBlocked) {
      return _InfoBar(
        icon:  Icons.block,
        label: '차단된 유저',
        color: const Color(0xFFEF4444),
      );
    }

    if (isPending) {
      return _InfoBar(
        icon:  Icons.schedule,
        label: '친구 요청 대기 중',
        color: AppTheme.textSub,
      );
    }

    return Row(
      children: [
        if (isFriend) ...[
          Expanded(
            child: _ActionButton(
              icon:  Icons.chat_bubble_rounded,
              label: '1:1 채팅',
              color: AppTheme.primary,
              onTap: _startChat,
            ),
          ),
        ] else ...[
          Expanded(
            child: _ActionButton(
              icon:  Icons.person_add_alt_1_rounded,
              label: '친구 추가',
              color: AppTheme.primary,
              loading: _actionLoading,
              onTap: _actionLoading ? null : _sendFriendRequest,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width:  20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoBar({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}