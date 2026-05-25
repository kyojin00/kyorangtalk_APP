import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../voice_room/screens/voice_room_screen.dart';
import '../../voice_room/services/voice_room_service.dart';
import '../models/group_room_model.dart';

// ═══════════════════════════════════════════════════
// 👥 GroupChatAppBar — 보이스 룸 빠른 진입 (최적화)
// ═══════════════════════════════════════════════════

AppBar buildGroupChatAppBar({
  required BuildContext context,
  required GroupRoomModel room,
  required bool isMuted,
  required VoidCallback onTitleTap,
  required VoidCallback onMenuTap,
  int? memberCount,
}) {
  final displayCount = memberCount ?? room.memberCount;

  return AppBar(
    backgroundColor: AppTheme.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    leadingWidth: 56,
    leading: Center(
      child: _CircleIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () => Navigator.pop(context),
        iconColor: AppTheme.primaryLight,
      ),
    ),
    titleSpacing: 4,
    title: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTitleTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.25),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: AvatarWidget(
                      url: room.avatarUrl,
                      name: room.name,
                      size: 36,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.85),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.bg,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.groups_rounded,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMuted) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.notifications_off_rounded,
                            color: AppTheme.textSub,
                            size: 13,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: Row(
                        key: ValueKey(displayCount),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 11,
                            color: AppTheme.textSub,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$displayCount명 참여중',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSub,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      _VoiceRoomActionButton(
        groupRoomId: room.id,
        groupName: room.name,
      ),
      const SizedBox(width: 4),
      _CircleIconButton(
        icon: Icons.menu_rounded,
        onTap: onMenuTap,
        iconColor: AppTheme.textMain,
      ),
      const SizedBox(width: 10),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(0.5),
      child: Container(
        height: 0.5,
        color: AppTheme.border.withOpacity(0.5),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 보이스 룸 버튼 - 즉시 화면 전환 (로딩 다이얼로그 제거)
// ═══════════════════════════════════════════════════
class _VoiceRoomActionButton extends StatelessWidget {
  final String groupRoomId;
  final String groupName;

  const _VoiceRoomActionButton({
    required this.groupRoomId,
    required this.groupName,
  });

  /// ⭐ 최적화: 로딩 다이얼로그 없이 즉시 VoiceRoomScreen 으로 이동
  /// 화면 진입과 동시에 백그라운드에서 룸 생성/입장 진행
  void _startVoiceRoom(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceRoomScreen(
          voiceRoomId: null, // ⭐ null = 새로 생성
          groupRoomId: groupRoomId,
          title: groupName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _startVoiceRoom(context),
            child: const Center(
              child: Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(icon, color: iconColor, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}