import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/group_room_model.dart';

// ═══════════════════════════════════════════════════
// 오픈채팅 탐색 타일
//
// 위치: lib/features/group_chat/widgets/open_room_tile.dart
// ═══════════════════════════════════════════════════

class OpenRoomTile extends StatelessWidget {
  final GroupRoomModel room;
  final String myId;
  final int? rank;
  final VoidCallback onPreview;

  const OpenRoomTile({
    super.key,
    required this.room,
    required this.myId,
    required this.onPreview,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final isTopRank = rank != null && rank! <= 3;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPreview,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: isTopRank
                ? AppTheme.primary.withOpacity(0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isTopRank
                ? Border.all(
                    color: AppTheme.primary.withOpacity(0.15),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              // ─── 랭킹 뱃지
              if (rank != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: isTopRank
                        ? LinearGradient(
                            colors: rank == 1
                                ? [
                                    const Color(0xFFFBBF24),
                                    const Color(0xFFF59E0B),
                                  ]
                                : rank == 2
                                    ? [
                                        const Color(0xFFD1D5DB),
                                        const Color(0xFF9CA3AF),
                                      ]
                                    : [
                                        const Color(0xFFD97706),
                                        const Color(0xFFB45309),
                                      ],
                          )
                        : null,
                    color: isTopRank ? null : AppTheme.bgCard,
                    shape: BoxShape.circle,
                    border: !isTopRank
                        ? Border.all(color: AppTheme.border)
                        : null,
                    boxShadow: isTopRank
                        ? [
                            BoxShadow(
                              color: (rank == 1
                                      ? const Color(0xFFFBBF24)
                                      : rank == 2
                                          ? const Color(0xFF9CA3AF)
                                          : const Color(0xFFD97706))
                                  .withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isTopRank
                            ? Colors.white
                            : AppTheme.textSub,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // ─── 아바타
              AvatarWidget(
                url: room.avatarUrl,
                name: room.name,
                size: 50,
              ),
              const SizedBox(width: 12),

              // ─── 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (room.hasPassword) ...[
                          Icon(Icons.lock,
                              size: 12, color: AppTheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            room.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            room.category,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF06B6D4),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (room.description != null &&
                        room.description!.isNotEmpty)
                      Text(
                        room.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.people_alt_rounded,
                          value: '${room.memberCount}',
                          color: AppTheme.textSub,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.favorite_rounded,
                          value: '${room.likeCount}',
                          color: const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ─── 입장 화살표
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF06B6D4).withOpacity(0.15),
                      const Color(0xFF06B6D4).withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF06B6D4).withOpacity(0.3),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFF06B6D4),
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}