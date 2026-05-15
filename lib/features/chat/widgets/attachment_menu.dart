import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 📎 첨부 메뉴 (DM + 그룹 공통)
// ═══════════════════════════════════════════════════
//
// 사용법:
// final action = await showAttachmentMenu(context);
//
// 반환값:
// - 'gallery'  : 갤러리에서 이미지
// - 'camera'   : 카메라
// - 'voice'    : 음성 녹음
// - 'game'     : 게임
// - 'poll'     : 투표
// - 'file'     : 파일
// - 'location' : 📍 위치 공유
// - 'schedule' : 📅 일정 잡기
// - null       : 취소
// ═══════════════════════════════════════════════════

Future<String?> showAttachmentMenu(BuildContext context) {
  FocusScope.of(context).unfocus();

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 1줄: 사진, 카메라, 음성
            Row(
              children: [
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.photo_library_outlined,
                    label: '사진',
                    color: const Color(0xFFA78BFA),
                    onTap: () => Navigator.pop(context, 'gallery'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.camera_alt_outlined,
                    label: '카메라',
                    color: const Color(0xFF60A5FA),
                    onTap: () => Navigator.pop(context, 'camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.mic_none_outlined,
                    label: '음성',
                    color: const Color(0xFFF472B6),
                    onTap: () => Navigator.pop(context, 'voice'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2줄: 게임, 투표, 파일
            Row(
              children: [
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.casino_outlined,
                    label: '게임',
                    color: const Color(0xFFFBBF24),
                    onTap: () => Navigator.pop(context, 'game'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.poll_outlined,
                    label: '투표',
                    color: const Color(0xFF10B981),
                    onTap: () => Navigator.pop(context, 'poll'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.attach_file,
                    label: '파일',
                    color: const Color(0xFF6366F1),
                    onTap: () => Navigator.pop(context, 'file'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3줄: 위치 공유, 일정 잡기
            Row(
              children: [
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.location_on_outlined,
                    label: '위치 공유',
                    color: const Color(0xFFEF4444),
                    onTap: () => Navigator.pop(context, 'location'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AttachmentButton(
                    icon: Icons.calendar_today_outlined,
                    label: '일정 잡기',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => Navigator.pop(context, 'schedule'),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════
// 🎨 첨부 버튼 위젯
// ═══════════════════════════════════════════════════
class AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const AttachmentButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}