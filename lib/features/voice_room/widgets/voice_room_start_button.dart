import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../services/voice_room_service.dart';
import '../screens/voice_room_screen.dart';

// ═══════════════════════════════════════════════════════════════
// 🎙️ VoiceRoomStartButton
//
// 위치: lib/features/voice_room/widgets/voice_room_start_button.dart
//
// 사용법 1) 첨부 메뉴 아이템으로:
//   VoiceRoomStartButton.menuItem(
//     groupRoomId: room.id,
//     groupName: room.name,
//   )
//
// 사용법 2) AppBar 액션 IconButton 으로:
//   VoiceRoomStartButton.appBarAction(
//     groupRoomId: room.id,
//     groupName: room.name,
//   )
//
// 사용법 3) 큰 시작 버튼 (룸 없을 때 안내용):
//   VoiceRoomStartButton.bigButton(
//     groupRoomId: room.id,
//     groupName: room.name,
//   )
//
// 동작:
// - 이미 active 룸이 있으면 거기로 입장 (start_voice_room RPC 가 자동으로 반환)
// - 없으면 새 룸 생성 후 입장
// ═══════════════════════════════════════════════════════════════

class VoiceRoomStartButton extends ConsumerWidget {
  final String groupRoomId;
  final String? groupName;
  final _ButtonStyle _style;

  const VoiceRoomStartButton._({
    required this.groupRoomId,
    required this.groupName,
    required _ButtonStyle style,
  }) : _style = style;

  /// 첨부 메뉴 아이템 형태 (아이콘 + 라벨, 보통 그리드 한 칸)
  factory VoiceRoomStartButton.menuItem({
    required String groupRoomId,
    String? groupName,
  }) =>
      VoiceRoomStartButton._(
        groupRoomId: groupRoomId,
        groupName: groupName,
        style: _ButtonStyle.menuItem,
      );

  /// AppBar action 형태 (IconButton 한 개)
  factory VoiceRoomStartButton.appBarAction({
    required String groupRoomId,
    String? groupName,
  }) =>
      VoiceRoomStartButton._(
        groupRoomId: groupRoomId,
        groupName: groupName,
        style: _ButtonStyle.appBarAction,
      );

  /// 큰 시작 버튼 (룸 없을 때 안내용)
  factory VoiceRoomStartButton.bigButton({
    required String groupRoomId,
    String? groupName,
  }) =>
      VoiceRoomStartButton._(
        groupRoomId: groupRoomId,
        groupName: groupName,
        style: _ButtonStyle.bigButton,
      );

  Future<void> _start(BuildContext context) async {
    // 진입 직전 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final voiceRoomId = await VoiceRoomService.instance.startRoom(
        groupRoomId: groupRoomId,
        title: groupName,
      );

      if (context.mounted) Navigator.pop(context); // 로딩 닫기

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VoiceRoomScreen(
              voiceRoomId: voiceRoomId,
              title: groupName,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // 로딩 닫기
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('보이스 룸 시작 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (_style) {
      case _ButtonStyle.menuItem:
        return _MenuItemStyle(onTap: () => _start(context));
      case _ButtonStyle.appBarAction:
        return _AppBarActionStyle(onTap: () => _start(context));
      case _ButtonStyle.bigButton:
        return _BigButtonStyle(onTap: () => _start(context));
    }
  }
}

enum _ButtonStyle { menuItem, appBarAction, bigButton }

// ───────────────────────────────────────────────
// 첨부 메뉴 아이템 (그리드 한 칸)
// ───────────────────────────────────────────────
class _MenuItemStyle extends StatelessWidget {
  final VoidCallback onTap;

  const _MenuItemStyle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '보이스 룸',
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────
// AppBar 액션 IconButton
// ───────────────────────────────────────────────
class _AppBarActionStyle extends StatelessWidget {
  final VoidCallback onTap;

  const _AppBarActionStyle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.graphic_eq_rounded,
        color: AppTheme.primary,
      ),
      tooltip: '보이스 룸 시작',
      onPressed: onTap,
    );
  }
}

// ───────────────────────────────────────────────
// 큰 시작 버튼
// ───────────────────────────────────────────────
class _BigButtonStyle extends StatelessWidget {
  final VoidCallback onTap;

  const _BigButtonStyle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.graphic_eq_rounded),
        label: const Text(
          '보이스 룸 시작',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}