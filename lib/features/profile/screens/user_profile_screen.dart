import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/chat/models/chat_room_model.dart';
import '../../reports/widgets/report_dialog.dart';
import '../widgets/profile_gallery_section.dart';
import 'photo_viewer_screen.dart';

// ═══════════════════════════════════════════════════
// 👤 UserProfileScreen — 시네마틱 + 갤러리
//
// 변경:
// - 프로필 사진 클릭 시 PhotoViewerScreen (큰 뷰)
// - 갤러리 섹션 추가 (RLS가 권한 자동 필터링)
// - SingleChildScrollView로 변경 (갤러리 스크롤)
// ═══════════════════════════════════════════════════

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
  List<Map<String, dynamic>> _photos = []; // ⭐ 갤러리
  bool _loading = true;
  String _friendStatus = 'none';
  bool _actionLoading = false;
  bool _isBlocked = false;
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
      _loadPhotos(), // ⭐
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
        'nickname': subProfileData['nickname'] ?? widget.nickname,
        'avatar_url': subProfileData['avatar_url'],
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

  // ⭐ 갤러리 로드 — RLS가 자동으로 권한 필터링
  Future<void> _loadPhotos() async {
  try {
    final data = await Supabase.instance.client
        .from('kyorangtalk_profile_photos')
        .select('id, photo_url, visibility, position, created_at')
        .eq('user_id', widget.userId)
        .order('created_at', ascending: false);  // ⭐ 최신이 앞으로
    if (mounted) {
      setState(() => _photos = List<Map<String, dynamic>>.from(data));
    }
  } catch (e) {
    print('상대 프로필 사진 로드 실패: $e');
  }
}

  Future<void> _loadFriendStatus() async {
    final data = await Supabase.instance.client
        .from('kyorangtalk_friends')
        .select('status')
        .or('and(requester_id.eq.$_myId,receiver_id.eq.${widget.userId}),'
            'and(requester_id.eq.${widget.userId},receiver_id.eq.$_myId)')
        .maybeSingle();
    if (mounted) {
      setState(
          () => _friendStatus = data?['status'] as String? ?? 'none');
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
    try {
      await Supabase.instance.client.rpc(
        'send_friend_request',
        params: {'target_user_id': widget.userId},
      );
      setState(() {
        _friendStatus = 'pending';
        _actionLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('친구 요청을 보냈어요!'),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } on PostgrestException catch (e) {
      setState(() => _actionLoading = false);
      if (mounted) {
        String msg;
        if (e.message.contains('already_friends')) {
          msg = '이미 친구예요';
        } else if (e.message.contains('already_pending')) {
          msg = '이미 요청 중이에요';
        } else if (e.message.contains('blocked')) {
          msg = '차단된 유저예요';
        } else {
          msg = '요청 실패: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _actionLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('요청 실패: $e'),
              backgroundColor: AppTheme.bgCard),
        );
      }
    }
  }

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
              color: AppTheme.textSub, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('취소', style: TextStyle(color: AppTheme.textSub)),
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

      await supabase.from('kyorangtalk_friends').delete().or(
          'and(requester_id.eq.$_myId,receiver_id.eq.${widget.userId}),'
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
              backgroundColor: AppTheme.bgCard,
              behavior: SnackBarBehavior.floating),
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
                color: AppTheme.textMain, fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.nickname}님의 차단을 해제하시겠어요?\n'
          '다시 메시지를 주고받을 수 있어요.',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('취소', style: TextStyle(color: AppTheme.textSub)),
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
              backgroundColor: AppTheme.bgCard,
              behavior: SnackBarBehavior.floating),
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
      partnerId: widget.userId,
      partnerUsername:
          _profile?['nickname'] as String? ?? widget.nickname,
      partnerName:
          _profile?['nickname'] as String? ?? widget.nickname,
      partnerAvatar: _profile?['avatar_url'] as String?,
      lastMessage: '',
      lastTime: DateTime.now(),
      unreadCount: 0,
      isSent: false,
      roomId: roomId,
    );

    context.pop();
    context.push('/main/chat/$roomId', extra: room);
  }

  // ⭐ 큰 뷰어로 교체
  void _showAvatarFullscreen(String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => PhotoViewerScreen(
          imageUrls: [url],
          initialIndex: 0,
          isOwner: false,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
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
    final nickname =
        _profile?['nickname'] as String? ?? widget.nickname;
    final avatar = _getAvatarUrl();
    final background = _profile?['background_url'] as String?;
    final statusMessage = _profile?['status_message'] as String?;
    final isMe = widget.userId == _myId;
    final isFriend = _friendStatus == 'accepted';
    final isPending = _friendStatus == 'pending';

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final bgCacheWidth = (screenWidth * pixelRatio).round();
    final bgCacheHeight = (screenHeight * pixelRatio).round();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primary),
            )
          : Stack(
              children: [
                // 배경
                Positioned.fill(
                  child: background != null
                      ? Image.network(
                          background,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          cacheWidth: bgCacheWidth,
                          cacheHeight: bgCacheHeight,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              _DefaultBackground(),
                        )
                      : _DefaultBackground(),
                ),

                // 오버레이
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                            AppTheme.bg.withOpacity(0.5),
                            AppTheme.bg,
                          ],
                          stops: const [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // 스티커
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
                    top: y * screenHeight - size / 2,
                    child: IgnorePointer(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: Center(
                          child: Text(emoji,
                              style: TextStyle(fontSize: size * 0.7)),
                        ),
                      ),
                    ),
                  );
                }),

                // 본문
                SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        // 헤더
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              12, 8, 12, 0),
                          child: Row(
                            children: [
                              _GlassIconButton(
                                icon: Icons.close_rounded,
                                onTap: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              if (!isMe)
                                _GlassIconButton(
                                  icon: Icons.more_horiz_rounded,
                                  onTap: () => _showMenu(),
                                ),
                            ],
                          ),
                        ),

                        SizedBox(
                            height: screenHeight * 0.15),

                        // 아바타
                        GestureDetector(
                          onTap: avatar != null
                              ? () => _showAvatarFullscreen(avatar)
                              : null,
                          child: Stack(
                            children: [
                              Container(
                                width: 124,
                                height: 124,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withOpacity(0.4),
                                      blurRadius: 40,
                                      spreadRadius: 4,
                                    ),
                                    BoxShadow(
                                      color: AppTheme.primaryLight
                                          .withOpacity(0.3),
                                      blurRadius: 60,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 124,
                                height: 124,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.primaryLight,
                                      AppTheme.primary,
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: ClipOval(
                                  child: Container(
                                    color: AppTheme.bg,
                                    padding:
                                        const EdgeInsets.all(2),
                                    child: ClipOval(
                                      child: AvatarWidget(
                                        url: avatar,
                                        name: nickname,
                                        size: 114,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 부 프로필 뱃지
                        if (_isSubProfile)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primary.withOpacity(0.2),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.primary
                                    .withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  color: AppTheme.primaryLight,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '부 프로필',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primaryLight,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // 닉네임
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              LinearGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.85),
                            ],
                          ).createShader(bounds),
                          child: Text(
                            nickname,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color:
                                      Colors.black.withOpacity(0.6),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 상태 메시지
                        if (statusMessage != null &&
                            statusMessage.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 36),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(14),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                    sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withOpacity(0.1),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white
                                          .withOpacity(0.15),
                                    ),
                                  ),
                                  child: Text(
                                    statusMessage,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white
                                          .withOpacity(0.95),
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        // ⭐ 갤러리 (RLS가 자동 필터링)
                        if (_photos.isNotEmpty)
                          ProfileGallerySection(
                            photos: _photos,
                            isOwner: false,
                          ),

                        const SizedBox(height: 24),

                        // 액션 버튼
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 8),
                            child: _buildActions(
                              isFriend: isFriend,
                              isPending: isPending,
                            ),
                          ),

                        SizedBox(
                            height: MediaQuery.of(context)
                                    .padding
                                    .bottom +
                                24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _MenuRow(
                icon: Icons.flag_outlined,
                iconColor: const Color(0xFFEF4444),
                label: '신고하기',
                labelColor: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(ctx);
                  _reportUser();
                },
              ),
              Divider(
                  color: AppTheme.border,
                  height: 1,
                  indent: 20,
                  endIndent: 20),
              if (_isBlocked)
                _MenuRow(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: AppTheme.primary,
                  label: '차단 해제',
                  labelColor: AppTheme.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _unblockUser();
                  },
                )
              else
                _MenuRow(
                  icon: Icons.block_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: '차단하기',
                  labelColor: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(ctx);
                    _blockUser();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions({
    required bool isFriend,
    required bool isPending,
  }) {
    if (_isBlocked) {
      return _InfoBar(
        icon: Icons.block_rounded,
        label: '차단된 유저',
        color: const Color(0xFFEF4444),
      );
    }

    if (isPending) {
      return _InfoBar(
        icon: Icons.schedule_rounded,
        label: '친구 요청 대기 중',
        color: Colors.white.withOpacity(0.7),
      );
    }

    return Row(
      children: [
        if (isFriend) ...[
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.chat_bubble_rounded,
              label: '1:1 채팅',
              onTap: _startChat,
            ),
          ),
        ] else ...[
          Expanded(
            child: _PrimaryActionButton(
              icon: Icons.person_add_alt_1_rounded,
              label: '친구 추가',
              loading: _actionLoading,
              onTap: _actionLoading ? null : _sendFriendRequest,
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 기본 배경
// ═══════════════════════════════════════════════════
class _DefaultBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A1655),
            const Color(0xFF1E1B3A),
            const Color(0xFF0F0F1F),
            AppTheme.bg,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 글래스 원형 버튼
// ═══════════════════════════════════════════════════
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.15),
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Primary 액션 버튼
// ═══════════════════════════════════════════════════
class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: disabled
              ? null
              : LinearGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.85),
                  ],
                ),
          color: disabled ? AppTheme.bgCard : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 정보 바
// ═══════════════════════════════════════════════════
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 메뉴 row
// ═══════════════════════════════════════════════════
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}