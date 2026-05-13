import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import '../widgets/password_dialog.dart';
import 'profile_select_screen.dart';

// ═══════════════════════════════════════════════════
// 🏛 OpenRoomPreviewScreen — 실시간 인원수 + 시네마틱
// ═══════════════════════════════════════════════════

class OpenRoomPreviewScreen extends ConsumerStatefulWidget {
  final GroupRoomModel room;

  const OpenRoomPreviewScreen({
    super.key,
    required this.room,
  });

  @override
  ConsumerState<OpenRoomPreviewScreen> createState() =>
      _OpenRoomPreviewScreenState();
}

class _OpenRoomPreviewScreenState
    extends ConsumerState<OpenRoomPreviewScreen> {
  bool _joining = false;
  bool _liking = false;

  // ⭐ 실시간 구독
  RealtimeChannel? _memberChannel;

  @override
  void initState() {
    super.initState();
    _subscribeMemberChanges();
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
          .channel('preview_members_${widget.room.id}')
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
              if (mounted) {
                ref.invalidate(roomDetailProvider(widget.room.id));
                ref.invalidate(
                    isRoomMemberProvider(widget.room.id));
              }
            },
          )
          .subscribe();
    } catch (e) {
      print('프리뷰 멤버 채널 구독 실패: $e');
    }
  }

  Future<void> _goToRoom() async {
    Navigator.pop(context);
    context.push('/main/group/${widget.room.id}',
        extra: widget.room);
  }

  Future<void> _joinRoom() async {
    final selection = await Navigator.push<ProfileSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSelectScreen(
          roomName: widget.room.name,
        ),
      ),
    );
    if (selection == null) return;
    if (!mounted) return;

    setState(() => _joining = true);

    try {
      final needsPw = await roomRequiresPassword(widget.room.id);

      String? password;
      String? errorMsg;

      while (needsPw) {
        if (!mounted) return;
        password = await showRoomPasswordDialog(
          context,
          roomName: widget.room.name,
          errorMessage: errorMsg,
        );
        if (password == null) {
          setState(() => _joining = false);
          return;
        }

        final result = await joinRoomWithPassword(
          roomId: widget.room.id,
          password: password,
          subProfileId: selection.subProfileId,
        );

        if (result == JoinResult.ok) break;
        if (result == JoinResult.notFound) {
          if (mounted) {
            _showSnack('방을 찾을 수 없어요');
            setState(() => _joining = false);
          }
          return;
        }
        if (result == JoinResult.wrongPassword) {
          errorMsg = '비밀번호가 틀렸어요';
          continue;
        }
        if (mounted) {
          _showSnack('입장에 실패했어요');
          setState(() => _joining = false);
        }
        return;
      }

      if (!needsPw) {
        final result = await joinRoomWithPassword(
          roomId: widget.room.id,
          password: null,
          subProfileId: selection.subProfileId,
        );
        if (result != JoinResult.ok) {
          if (mounted) {
            _showSnack('입장에 실패했어요');
            setState(() => _joining = false);
          }
          return;
        }
      }

      ref.invalidate(groupRoomsProvider);
      ref.invalidate(openRoomsProvider);
      ref.invalidate(isRoomMemberProvider(widget.room.id));

      if (mounted) {
        Navigator.pop(context);
        context.push('/main/group/${widget.room.id}',
            extra: widget.room);
      }
    } catch (e) {
      if (mounted) _showSnack('입장 실패: $e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);

    try {
      await toggleRoomLike(widget.room.id);
      ref.invalidate(isLikedProvider(widget.room.id));
      ref.invalidate(roomDetailProvider(widget.room.id));
      ref.invalidate(openRoomsProvider);
    } catch (e) {
      if (mounted) _showSnack('실패: $e');
    } finally {
      if (mounted) setState(() => _liking = false);
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

  String _formatDate(String dateStr) {
    final dt = DateTime.parse(dateStr).toLocal();
    return DateFormat('yyyy.M.d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomDetailProvider(widget.room.id));
    final isLikedAsync = ref.watch(isLikedProvider(widget.room.id));
    final isMemberAsync =
        ref.watch(isRoomMemberProvider(widget.room.id));
    final isMember = isMemberAsync.value ?? false;

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
      body: roomAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
        error: (e, _) => Center(
          child: Text('오류: $e',
              style: TextStyle(color: AppTheme.textSub)),
        ),
        data: (room) {
          if (room == null) {
            return Center(
              child: Text('방을 찾을 수 없어요',
                  style: TextStyle(color: AppTheme.textSub)),
            );
          }

          final isLiked = isLikedAsync.value ?? false;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _HeaderArea(
                        room: room,
                        isMember: isMember,
                      ),

                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            // ⭐ 통계 카드 (멤버 수는 AnimatedSwitcher로 부드럽게)
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.people_alt_rounded,
                                    label: '참여자',
                                    value: '${room.memberCount}명',
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

                            if (!isMember && room.hasPassword) ...[
                              _InfoCard(
                                icon: Icons.lock_rounded,
                                iconColor: const Color(0xFFFBBF24),
                                title: '비밀번호 보호 채팅방',
                                description:
                                    '입장 시 방장이 설정한 비밀번호가 필요해요',
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (!isMember) ...[
                              _InfoCard(
                                icon: Icons.masks_rounded,
                                iconColor: AppTheme.primary,
                                title: '프로필을 선택해서 입장해요',
                                description:
                                    '기본 프로필 또는 부캐 프로필 중 선택할 수 있어요',
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (room.tags.isNotEmpty) ...[
                              _SectionLabel(
                                  icon: Icons.tag_rounded,
                                  label: '태그'),
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
                                          AppTheme.primary
                                              .withOpacity(0.18),
                                          AppTheme.primary
                                              .withOpacity(0.08),
                                        ],
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.primary
                                            .withOpacity(0.25),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text('#$tag',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.primaryLight,
                                            fontWeight:
                                                FontWeight.w700,
                                            letterSpacing: -0.2)),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],

                            _SectionLabel(
                                icon: Icons.description_rounded,
                                label: '소개'),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius:
                                    BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppTheme.border),
                              ),
                              child: Text(
                                room.description?.isNotEmpty == true
                                    ? room.description!
                                    : '아직 소개가 없어요',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: room.description
                                              ?.isNotEmpty ==
                                          true
                                      ? AppTheme.textMain
                                      : AppTheme.textMuted,
                                  height: 1.6,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgCard,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                      Icons.schedule_rounded,
                                      size: 11,
                                      color: AppTheme.textMuted),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_formatDate(room.createdAt)}에 생성됨',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.border.withOpacity(0.5),
                      width: 0.8,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).padding.bottom + 12,
                ),
                child: Row(
                  children: [
                    _LikeButton(
                      isLiked: isLiked,
                      liking: _liking,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _JoinButton(
                        isMember: isMember,
                        hasPassword: room.hasPassword,
                        joining: _joining,
                        onTap: isMember ? _goToRoom : _joinRoom,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 헤더 영역
// ═══════════════════════════════════════════════════
class _HeaderArea extends StatelessWidget {
  final GroupRoomModel room;
  final bool isMember;

  const _HeaderArea({required this.room, required this.isMember});

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
              _CategoryBadge(category: room.category),
              if (room.hasPassword) _PasswordBadge(),
              if (isMember) _MemberBadge(),
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

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.public_rounded,
              color: Colors.white, size: 12),
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

class _MemberBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('참여 중',
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
// ⭐ 통계 카드 (참여자 수는 AnimatedSwitcher로 부드러운 전환)
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
          // ⭐ 값이 바뀌면 부드럽게 슬라이드 전환
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconColor.withOpacity(0.12),
            iconColor.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iconColor.withOpacity(0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  iconColor.withOpacity(0.25),
                  iconColor.withOpacity(0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      letterSpacing: -0.2),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSub,
                      height: 1.3,
                      letterSpacing: -0.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _LikeButton extends StatelessWidget {
  final bool isLiked;
  final bool liking;
  final VoidCallback onTap;

  const _LikeButton({
    required this.isLiked,
    required this.liking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFEF4444);
    return SizedBox(
      width: 56,
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isLiked
              ? LinearGradient(
                  colors: [
                    redColor.withOpacity(0.18),
                    redColor.withOpacity(0.08),
                  ],
                )
              : null,
          color: isLiked ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLiked
                ? redColor.withOpacity(0.5)
                : AppTheme.border,
            width: 1,
          ),
          boxShadow: isLiked
              ? [
                  BoxShadow(
                    color: redColor.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: liking ? null : onTap,
              child: Center(
                child: liking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: redColor,
                        ),
                      )
                    : Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isLiked ? redColor : AppTheme.textSub,
                        size: 22,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  final bool isMember;
  final bool hasPassword;
  final bool joining;
  final VoidCallback onTap;

  const _JoinButton({
    required this.isMember,
    required this.hasPassword,
    required this.joining,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = isMember
        ? [AppTheme.primary, AppTheme.primary.withOpacity(0.85)]
        : const [Color(0xFF06B6D4), Color(0xFF0891B2)];
    final shadowColor =
        isMember ? AppTheme.primary : const Color(0xFF06B6D4);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.4),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: joining ? null : onTap,
            child: Center(
              child: joining
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isMember
                              ? Icons.chat_bubble_rounded
                              : (hasPassword
                                  ? Icons.lock_open_rounded
                                  : Icons.masks_rounded),
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isMember
                              ? '채팅방 가기'
                              : (hasPassword
                                  ? '비밀번호 입력 후 입장'
                                  : '프로필 선택 후 입장'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}