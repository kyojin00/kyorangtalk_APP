import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import 'group_members_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMuteStatus();
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('알림 설정',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain)),
              ),
            ),
            if (_isMuted)
              ListTile(
                leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppTheme.primary),
                title: const Text('알림 켜기',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'unmute'),
              )
            else ...[
              ListTile(
                leading: Icon(
                    Icons.notifications_off_outlined,
                    color: AppTheme.textMain),
                title: Text('1시간 동안 알림 끄기',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () => Navigator.pop(ctx, '1h'),
              ),
              ListTile(
                leading: Icon(
                    Icons.notifications_off_outlined,
                    color: AppTheme.textMain),
                title: Text('8시간 동안 알림 끄기',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () => Navigator.pop(ctx, '8h'),
              ),
              ListTile(
                leading: Icon(
                    Icons.notifications_off_outlined,
                    color: AppTheme.textMain),
                title: Text('24시간 동안 알림 끄기',
                    style: TextStyle(color: AppTheme.textMain)),
                onTap: () => Navigator.pop(ctx, '24h'),
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on,
                    color: Color(0xFFEF4444)),
                title: const Text('계속 끄기',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600)),
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
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _leaveRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('채팅방 나가기',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700)),
        content: Text(
          '채팅방을 나가면 대화 내용을 볼 수 없어요.',
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
            child: const Text('나가기',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await leaveGroupRoom(widget.room.id);
    if (mounted) {
      ref.invalidate(groupRoomsProvider);
      Navigator.pop(context); // 정보 화면 닫기
      Navigator.pop(context); // 채팅방 닫기
    }
  }

  void _copyInviteCode() {
    Clipboard.setData(ClipboardData(text: widget.room.inviteCode));
    _showSnack('초대코드가 복사됐어요!');
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ✨ 상단 이미지 + 그라데이션 + 방 이름
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 320,
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
                              url: null,
                              name: room.name,
                              size: 120),
                        )
                      : null,
                ),
                Container(
                  width: double.infinity,
                  height: 320,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
                // 상단 배지 (오픈채팅/그룹채팅 + 카테고리)
                Positioned(
                  top: 80, left: 20,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: room.isOpen
                              ? const Color(0xFF06B6D4)
                              : AppTheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                room.isOpen
                                    ? Icons.public
                                    : Icons.group,
                                color: Colors.white,
                                size: 12),
                            const SizedBox(width: 4),
                            Text(
                                room.isOpen
                                    ? room.category
                                    : '그룹채팅',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      // 음소거 배지
                      if (_isMuted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_off,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('알림 꺼짐',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 하단 방 이름
                Positioned(
                  bottom: 20, left: 20, right: 20,
                  child: Text(
                    room.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✨ 통계 카드
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_outline,
                          label: '멤버',
                          value: '${room.memberCount}명',
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.favorite,
                          label: '좋아요',
                          value: '${room.likeCount}',
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ✨ 태그 (있으면 표시)
                  if (room.tags.isNotEmpty) ...[
                    Text('태그',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSub)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: room.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary
                                .withOpacity(0.12),
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: Text('#$tag',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ✨ 소개
                  Text('소개',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
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
                          color: room.description?.isNotEmpty ==
                                  true
                              ? AppTheme.textMain
                              : AppTheme.textMuted,
                          height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ✨ 메뉴 리스트 (멤버, 알림, 초대코드)
                  Text('관리',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub)),
                  const SizedBox(height: 10),

                  // 멤버 목록
                  _MenuItem(
                    icon: Icons.people_outline,
                    iconColor: AppTheme.primary,
                    title: '멤버 관리',
                    subtitle: '${room.memberCount}명',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupMembersScreen(room: room),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // ✨ 알림 설정 (추가!)
                  _MenuItem(
                    icon: _isMuted
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                    iconColor: _isMuted
                        ? AppTheme.textSub
                        : AppTheme.primary,
                    title: '알림 설정',
                    subtitle: _loadingMute
                        ? '로딩 중...'
                        : (_isMuted ? '알림 꺼짐' : '알림 켜짐'),
                    trailing: _isMuted
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444)
                                  .withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: const Text('꺼짐',
                                style: TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          )
                        : null,
                    onTap: _loadingMute ? null : _showMuteOptions,
                  ),

                  // 초대코드 (있으면)
                  if (room.inviteCode.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _copyInviteCode,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primary
                                    .withOpacity(0.15),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.link,
                                  color: AppTheme.primary,
                                  size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('초대코드',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppTheme.textSub)),
                                  const SizedBox(height: 2),
                                  Text(room.inviteCode,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight.w800,
                                          color: AppTheme
                                              .primaryLight,
                                          letterSpacing: 2)),
                                ],
                              ),
                            ),
                            Icon(Icons.copy,
                                color: AppTheme.textSub,
                                size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ✨ 생성일
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 14,
                          color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Text(
                          '${_formatDate(room.createdAt)}에 생성됨',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ✨ 채팅방 나가기
                  InkWell(
                    onTap: _leaveRoom,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFEF4444)
                                .withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(Icons.exit_to_app,
                              color: Color(0xFFEF4444),
                              size: 20),
                          SizedBox(width: 8),
                          Text('채팅방 나가기',
                              style: TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 15,
                                  fontWeight:
                                      FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),

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
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textSub)),
        ],
      ),
    );
  }
}

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: AppTheme.textSub, size: 20),
          ],
        ),
      ),
    );
  }
}