import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';
import '../providers/group_chat_provider.dart';
import 'profile_select_screen.dart';

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

  // ✨ 이미 멤버면 바로 입장
  Future<void> _goToRoom() async {
    Navigator.pop(context);
    context.push('/main/group/${widget.room.id}', extra: widget.room);
  }

  // ✨ 새로 입장 (프로필 선택)
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

    setState(() => _joining = true);

    try {
      await joinOpenRoom(
        widget.room.id,
        subProfileId: selection.subProfileId,
      );
      ref.invalidate(groupRoomsProvider);
      ref.invalidate(openRoomsProvider);
      ref.invalidate(isRoomMemberProvider(widget.room.id));

      if (mounted) {
        Navigator.pop(context);
        context.push('/main/group/${widget.room.id}',
            extra: widget.room);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('입장 실패: $e')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  String _formatDate(String dateStr) {
    final dt = DateTime.parse(dateStr).toLocal();
    return DateFormat('yyyy.M.d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomDetailProvider(widget.room.id));
    final isLikedAsync = ref.watch(isLikedProvider(widget.room.id));
    // ✨ 내가 이 방의 멤버인지 확인
    final isMemberAsync = ref.watch(isRoomMemberProvider(widget.room.id));
    final isMember = isMemberAsync.value ?? false;

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
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 320,
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              image: room.avatarUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                          room.avatarUrl!),
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
                                  Colors.black.withOpacity(0.5),
                                ],
                                stops: const [0, 0.5, 1],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 80, left: 20,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF06B6D4),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.public,
                                          color: Colors.white,
                                          size: 12),
                                      const SizedBox(width: 4),
                                      Text(room.category,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight:
                                                  FontWeight.w700)),
                                    ],
                                  ),
                                ),
                                // ✨ 참여 중 배지
                                if (isMember) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.white,
                                            size: 12),
                                        SizedBox(width: 4),
                                        Text('참여 중',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.people_outline,
                                    label: '참여자',
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

                            // ✨ 멤버 아닐 때만 프로필 선택 안내 표시
                            if (!isMember) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary
                                      .withOpacity(0.08),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.primary
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary
                                            .withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.masks,
                                          color: AppTheme.primary,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '프로필을 선택해서 입장해요',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color: AppTheme
                                                      .textMain)),
                                          const SizedBox(height: 2),
                                          Text(
                                              '기본 프로필 또는 부캐 프로필 중 선택할 수 있어요',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme
                                                      .textSub)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

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
                                            color:
                                                AppTheme.primaryLight,
                                            fontWeight:
                                                FontWeight.w600)),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],

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
                                border: Border.all(
                                    color: AppTheme.border),
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
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                Icon(
                                    Icons.schedule_outlined,
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
                      top: BorderSide(color: AppTheme.border)),
                ),
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20,
                    MediaQuery.of(context).padding.bottom + 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _liking ? null : _toggleLike,
                      child: Container(
                        width: 56, height: 50,
                        decoration: BoxDecoration(
                          color: isLiked
                              ? const Color(0xFFEF4444).withOpacity(0.15)
                              : AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isLiked
                                ? const Color(0xFFEF4444)
                                : AppTheme.border,
                          ),
                        ),
                        child: _liking
                            ? const Center(
                                child: SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFEF4444)),
                                ),
                              )
                            : Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isLiked
                                    ? const Color(0xFFEF4444)
                                    : AppTheme.textSub,
                                size: 22,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // ✨ 멤버 여부에 따라 버튼 변경
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _joining
                            ? null
                            : (isMember ? _goToRoom : _joinRoom),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isMember
                              ? AppTheme.primary
                              : const Color(0xFF06B6D4),
                          foregroundColor: Colors.white,
                          minimumSize:
                              const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                        ),
                        child: _joining
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      isMember
                                          ? Icons.chat_bubble_rounded
                                          : Icons.masks,
                                      color: Colors.white,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                      isMember
                                          ? '채팅방 가기'
                                          : '프로필 선택 후 입장',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w700)),
                                ],
                              ),
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