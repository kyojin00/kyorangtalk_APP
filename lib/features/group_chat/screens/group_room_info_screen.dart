import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/password_dialog.dart';
import 'group_members_screen.dart';

// ═══════════════════════════════════════════════════
// 🏛 GroupRoomInfoScreen — 시네마틱 리디자인 + 실시간 인원수
// ═══════════════════════════════════════════════════

class GroupRoomInfoScreen extends ConsumerStatefulWidget {
  final GroupRoomModel room;

  const GroupRoomInfoScreen({super.key, required this.room});

  @override
  ConsumerState<GroupRoomInfoScreen> createState() =>
      _GroupRoomInfoScreenState();
}

class _GroupRoomInfoScreenState
    extends ConsumerState<GroupRoomInfoScreen> {
  bool _isMuted = false;
  bool _loadingMute = true;

  // ⭐ 실시간 인원수
  int _memberCount = 0;
  RealtimeChannel? _memberChannel;

  @override
  void initState() {
    super.initState();
    _memberCount = widget.room.memberCount;
    _loadMuteStatus();
    _subscribeMemberChanges();
    _refreshMemberCount();
  }

  @override
  void dispose() {
    if (_memberChannel != null) {
      Supabase.instance.client.removeChannel(_memberChannel!);
    }
    super.dispose();
  }

  // ⭐ 멤버 변경 실시간 감지
  void _subscribeMemberChanges() {
    try {
      _memberChannel = Supabase.instance.client
          .channel('info_members_${widget.room.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'kyorangtalk_group_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.room.id,
            ),
            callback: (_) {
              if (mounted) _refreshMemberCount();
            },
          )
          .subscribe();
    } catch (e) {
      print('정보 화면 멤버 채널 구독 실패: $e');
    }
  }

  Future<void> _refreshMemberCount() async {
    try {
      final result = await Supabase.instance.client
          .from('kyorangtalk_group_members')
          .select('user_id')
          .eq('room_id', widget.room.id);
      if (mounted) {
        setState(() => _memberCount = (result as List).length);
      }
    } catch (e) {
      print('정보 화면 멤버 카운트 실패: $e');
    }
  }

  Future<void> _loadMuteStatus() async {
    final muted = await NotificationService.isMuted(
        groupRoomId: widget.room.id);
    if (mounted) {
      setState(() {
        _isMuted = muted;
        _loadingMute = false;
      });
    }
  }

  String _formatDate(String dateStr) {
    final dt = DateTime.parse(dateStr).toLocal();
    return DateFormat('yyyy.M.d').format(dt);
  }

  Future<void> _showMuteOptions() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.25),
                          AppTheme.primary.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.notifications_rounded,
                        color: AppTheme.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text('알림 설정',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          letterSpacing: -0.3)),
                ],
              ),
            ),
            if (_isMuted)
              _MuteOption(
                icon: Icons.notifications_active_rounded,
                iconColor: AppTheme.primary,
                title: '알림 켜기',
                titleColor: AppTheme.primary,
                bold: true,
                onTap: () => Navigator.pop(ctx, 'unmute'),
              )
            else ...[
              _MuteOption(
                icon: Icons.notifications_off_rounded,
                iconColor: AppTheme.textSub,
                title: '1시간 동안 알림 끄기',
                onTap: () => Navigator.pop(ctx, '1h'),
              ),
              _MuteOption(
                icon: Icons.notifications_off_rounded,
                iconColor: AppTheme.textSub,
                title: '8시간 동안 알림 끄기',
                onTap: () => Navigator.pop(ctx, '8h'),
              ),
              _MuteOption(
                icon: Icons.notifications_off_rounded,
                iconColor: AppTheme.textSub,
                title: '24시간 동안 알림 끄기',
                onTap: () => Navigator.pop(ctx, '24h'),
              ),
              _MuteOption(
                icon: Icons.do_not_disturb_on_rounded,
                iconColor: const Color(0xFFEF4444),
                title: '계속 끄기',
                titleColor: const Color(0xFFEF4444),
                bold: true,
                onTap: () => Navigator.pop(ctx, 'forever'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result == 'unmute') {
      await NotificationService.unmute(groupRoomId: widget.room.id);
      if (mounted) {
        setState(() => _isMuted = false);
        _showSnack('알림이 켜졌어요');
      }
    } else {
      Duration? duration;
      String label;
      switch (result) {
        case '1h':
          duration = const Duration(hours: 1);
          label = '1시간';
          break;
        case '8h':
          duration = const Duration(hours: 8);
          label = '8시간';
          break;
        case '24h':
          duration = const Duration(hours: 24);
          label = '24시간';
          break;
        case 'forever':
        default:
          duration = null;
          label = '계속';
      }
      await NotificationService.mute(
          groupRoomId: widget.room.id, duration: duration);
      if (mounted) {
        setState(() => _isMuted = true);
        _showSnack('$label 알림을 껐어요');
      }
    }

    if (mounted) {
      ref.invalidate(mutedRoomsProvider);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
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

  Future<void> _leaveRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppTheme.border)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFEF4444).withOpacity(0.25),
                    const Color(0xFFEF4444).withOpacity(0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.exit_to_app_rounded,
                  color: Color(0xFFEF4444), size: 16),
            ),
            const SizedBox(width: 10),
            Text('채팅방 나가기',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3)),
          ],
        ),
        content: Text('채팅방을 나가면 대화 내용을 볼 수 없어요.',
            style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 14,
                letterSpacing: -0.2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: TextStyle(
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await leaveGroupRoom(widget.room.id);
    if (mounted) {
      ref.invalidate(groupRoomsProvider);
      Navigator.pop(context);
      Navigator.pop(context);
    }
  }

  Future<void> _managePassword() async {
    final detail = ref.read(roomDetailProvider(widget.room.id)).value;
    final hasPassword = detail?.hasPassword ?? widget.room.hasPassword;

    final newPw = await showChangePasswordDialog(
      context,
      hasPassword: hasPassword,
    );
    if (newPw == null || !mounted) return;

    final result = await updateRoomPassword(
      roomId: widget.room.id,
      newPassword: newPw.isEmpty ? null : newPw,
    );

    if (!mounted) return;

    switch (result) {
      case PasswordUpdateResult.updated:
        _showSnack(hasPassword ? '비밀번호가 변경됐어요' : '비밀번호가 설정됐어요');
        ref.invalidate(roomDetailProvider(widget.room.id));
        ref.invalidate(groupRoomsProvider);
        ref.invalidate(openRoomsProvider);
        break;
      case PasswordUpdateResult.removed:
        _showSnack('비밀번호가 제거됐어요');
        ref.invalidate(roomDetailProvider(widget.room.id));
        ref.invalidate(groupRoomsProvider);
        ref.invalidate(openRoomsProvider);
        break;
      case PasswordUpdateResult.notAdmin:
        _showSnack('방장만 변경할 수 있어요');
        break;
      default:
        _showSnack('변경에 실패했어요');
    }
  }

  void _shareInvite() {
    final detail = ref.read(roomDetailProvider(widget.room.id)).value;
    final hasPassword = detail?.hasPassword ?? widget.room.hasPassword;

    showInviteShareSheet(
      context,
      roomName: widget.room.name,
      inviteCode: widget.room.inviteCode,
      hasPassword: hasPassword,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    final detailAsync = ref.watch(roomDetailProvider(room.id));
    final hasPassword =
        detailAsync.value?.hasPassword ?? room.hasPassword;
    final isAdmin = room.isAdmin;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: Center(
          child: _GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // ─── 헤더 영역 ───
            _HeaderArea(
              room: room,
              hasPassword: hasPassword,
              isMuted: _isMuted,
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 통계 카드 (실시간) ───
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_alt_rounded,
                          label: '멤버',
                          value: '$_memberCount명',
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.favorite_rounded,
                          label: '좋아요',
                          value: '${room.likeCount}',
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ─── 태그 ───
                  if (room.tags.isNotEmpty) ...[
                    _SectionLabel(
                        icon: Icons.tag_rounded, label: '태그'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: room.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primary.withOpacity(0.18),
                                AppTheme.primary.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primary
                                  .withOpacity(0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text('#$tag',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ─── 소개 ───
                  _SectionLabel(
                      icon: Icons.description_rounded, label: '소개'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      room.description?.isNotEmpty == true
                          ? room.description!
                          : '아직 소개가 없어요',
                      style: TextStyle(
                        fontSize: 14,
                        color: room.description?.isNotEmpty == true
                            ? AppTheme.textMain
                            : AppTheme.textMuted,
                        height: 1.6,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── 관리 메뉴 ───
                  _SectionLabel(
                      icon: Icons.settings_rounded, label: '관리'),
                  const SizedBox(height: 10),

                  _MenuItem(
                    icon: Icons.people_alt_rounded,
                    iconColor: AppTheme.primary,
                    title: '멤버 관리',
                    subtitle: '$_memberCount명',  // ⭐ 실시간
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupMembersScreen(room: room),
                        ),
                      ).then((_) {
                        if (mounted) _refreshMemberCount();
                      });
                    },
                  ),

                  const SizedBox(height: 10),

                  _MenuItem(
                    icon: _isMuted
                        ? Icons.notifications_off_rounded
                        : Icons.notifications_active_rounded,
                    iconColor: _isMuted
                        ? AppTheme.textSub
                        : AppTheme.primary,
                    title: '알림 설정',
                    subtitle: _loadingMute
                        ? '로딩 중...'
                        : (_isMuted ? '알림 꺼짐' : '알림 켜짐'),
                    trailing: _isMuted
                        ? _StatusPill(
                            label: '꺼짐',
                            color: const Color(0xFFEF4444),
                          )
                        : null,
                    onTap: _loadingMute ? null : _showMuteOptions,
                  ),

                  if (isAdmin) ...[
                    const SizedBox(height: 10),
                    _MenuItem(
                      icon: hasPassword
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      iconColor: hasPassword
                          ? const Color(0xFFFBBF24)
                          : AppTheme.textSub,
                      title: '비밀번호 관리',
                      subtitle:
                          hasPassword ? '비밀번호로 보호 중' : '비밀번호 없음',
                      trailing: hasPassword
                          ? _StatusPill(
                              label: '보호 중',
                              color: const Color(0xFFFBBF24),
                            )
                          : null,
                      onTap: _managePassword,
                    ),
                  ],

                  // ─── 초대 공유 ───
                  if (room.inviteCode.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InviteShareCard(
                      inviteCode: room.inviteCode,
                      onTap: _shareInvite,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ─── 생성일 ───
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.schedule_rounded,
                            size: 11, color: AppTheme.textMuted),
                      ),
                      const SizedBox(width: 6),
                      Text('${_formatDate(room.createdAt)}에 생성됨',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ─── 채팅방 나가기 ───
                  _LeaveButton(onTap: _leaveRoom),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 헤더 영역
// ═══════════════════════════════════════════════════
class _HeaderArea extends StatelessWidget {
  final GroupRoomModel room;
  final bool hasPassword;
  final bool isMuted;

  const _HeaderArea({
    required this.room,
    required this.hasPassword,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 340,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            image: room.avatarUrl != null
                ? DecorationImage(
                    image: NetworkImage(room.avatarUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: room.avatarUrl == null
              ? Center(
                  child: AvatarWidget(
                      url: null, name: room.name, size: 120),
                )
              : null,
        ),
        Container(
          width: double.infinity,
          height: 340,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.5),
                Colors.transparent,
                AppTheme.bg.withOpacity(0.3),
                AppTheme.bg,
              ],
              stops: const [0.0, 0.35, 0.75, 1.0],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 20,
          right: 20,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CategoryBadge(
                category: room.isOpen ? room.category : '그룹채팅',
                isOpen: room.isOpen,
              ),
              if (hasPassword) _PasswordBadge(),
              if (isMuted) _MutedBadge(),
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          left: 20,
          right: 20,
          child: Text(
            room.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 뱃지들
// ═══════════════════════════════════════════════════
class _CategoryBadge extends StatelessWidget {
  final String category;
  final bool isOpen;
  const _CategoryBadge({required this.category, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final colors = isOpen
        ? const [Color(0xFF06B6D4), Color(0xFF0891B2)]
        : [AppTheme.primary, AppTheme.primary.withOpacity(0.85)];
    final shadowColor =
        isOpen ? const Color(0xFF06B6D4) : AppTheme.primary;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              isOpen
                  ? Icons.public_rounded
                  : Icons.groups_rounded,
              color: Colors.white,
              size: 12),
          const SizedBox(width: 4),
          Text(category,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

class _PasswordBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFBBF24).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('비밀번호',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

class _MutedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.8,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_off_rounded,
                  color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text('알림 꺼짐',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
            ],
          ),
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
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 통계 카드 (AnimatedSwitcher로 실시간)
// ═══════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.08),
            color.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            child: Text(value,
                key: ValueKey(value),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMain,
                    letterSpacing: -0.3)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 섹션 라벨
// ═══════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppTheme.textSub),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSub,
              letterSpacing: 0.2),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// 메뉴 아이템
// ═══════════════════════════════════════════════════
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      iconColor.withOpacity(0.25),
                      iconColor.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        subtitle,
                        key: ValueKey(subtitle),
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub,
                            letterSpacing: -0.2),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSub, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 상태 알약
// ═══════════════════════════════════════════════════
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.22),
            color.withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: color.withOpacity(0.35),
          width: 0.6,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 초대 공유 카드
// ═══════════════════════════════════════════════════
class _InviteShareCard extends StatelessWidget {
  final String inviteCode;
  final VoidCallback onTap;

  const _InviteShareCard({
    required this.inviteCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withOpacity(0.12),
                AppTheme.primary.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.share_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('초대 공유',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(inviteCode,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryLight,
                            letterSpacing: 2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 채팅방 나가기 버튼
// ═══════════════════════════════════════════════════
class _LeaveButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LeaveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFEF4444);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                redColor.withOpacity(0.15),
                redColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: redColor.withOpacity(0.35),
              width: 0.8,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.exit_to_app_rounded,
                  color: redColor, size: 20),
              SizedBox(width: 8),
              Text('채팅방 나가기',
                  style: TextStyle(
                      color: redColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 알림 옵션 (시트)
// ═══════════════════════════════════════════════════
class _MuteOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final bool bold;
  final VoidCallback onTap;

  const _MuteOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    this.bold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
            color: titleColor ?? AppTheme.textMain,
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: -0.2,
          )),
      onTap: onTap,
    );
  }
}