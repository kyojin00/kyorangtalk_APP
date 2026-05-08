import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════
// 사이드 패널 메뉴 한 줄
//
// 위치: lib/features/friends/widgets/panel_menu_item.dart
//
// 우상단 더보기 버튼을 누르면 열리는 오른쪽 슬라이드 패널의
// 메뉴 항목 하나를 표현. 뱃지(숫자)도 지원.
// ═══════════════════════════════════════════════

class PanelMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const PanelMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSub, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textMain,
                      fontWeight: FontWeight.w500)),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}