import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/location_share_model.dart';
import '../services/location_share_service.dart';

// ═══════════════════════════════════════════════════
// 📍 LocationShareStartSheet
//
// 위치: lib/features/location/widgets/location_share_start_sheet.dart
//
// 위치 공유 시작 — 시간 선택 후 startShare() 호출.
//
// 사용
//   final share = await showLocationShareStartSheet(
//     context,
//     roomId: 'xxx',
//     roomType: 'dm',
//   );
//   if (share != null) {
//     // 메시지 전송 등
//   }
// ═══════════════════════════════════════════════════

Future<LocationShareModel?> showLocationShareStartSheet(
  BuildContext context, {
  required String roomId,
  required String roomType,
}) {
  return showModalBottomSheet<LocationShareModel?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LocationShareStartSheet(
      roomId:   roomId,
      roomType: roomType,
    ),
  );
}

class _LocationShareStartSheet extends StatefulWidget {
  final String roomId;
  final String roomType;

  const _LocationShareStartSheet({
    required this.roomId,
    required this.roomType,
  });

  @override
  State<_LocationShareStartSheet> createState() =>
      _LocationShareStartSheetState();
}

class _LocationShareStartSheetState
    extends State<_LocationShareStartSheet> {
  int _selectedMinutes = 60; // 기본 1시간
  bool _starting = false;

  static const List<_DurationOption> _options = [
    _DurationOption(minutes: 15,  label: '15분'),
    _DurationOption(minutes: 60,  label: '1시간'),
    _DurationOption(minutes: 120, label: '2시간'),
    _DurationOption(minutes: 480, label: '8시간'),
  ];

  Future<void> _onStart() async {
    setState(() => _starting = true);

    final share = await LocationShareService.instance.startShare(
      roomId:          widget.roomId,
      roomType:        widget.roomType,
      durationMinutes: _selectedMinutes,
    );

    if (!mounted) return;

    if (share == null) {
      setState(() => _starting = false);
      _showPermissionDialog();
      return;
    }

    Navigator.pop(context, share);
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '위치 권한이 필요해요',
          style: TextStyle(
            color: AppTheme.textMain,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          '위치 공유를 사용하려면 위치 권한과 위치 서비스가 켜져 있어야 해요. '
          '설정에서 권한을 허용해주세요.',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '확인',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 18),

            // 헤더
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '실시간 위치 공유',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '선택한 시간 동안 내 위치가 전송돼요',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 시간 선택
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final opt in _options)
                  _DurationChip(
                    label: opt.label,
                    selected: _selectedMinutes == opt.minutes,
                    onTap: () => setState(
                        () => _selectedMinutes = opt.minutes),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // 안내
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppTheme.textSub,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '언제든지 채팅방의 위치 카드에서 종료할 수 있어요. '
                      '앱을 사용 중일 때만 위치가 전송돼요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSub,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 시작 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _starting ? null : _onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor:
                      AppTheme.primary.withOpacity(0.5),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '공유 시작',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 시간 옵션 칩
// ═══════════════════════════════════════════════════
class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.primary
          : AppTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : AppTheme.border,
              width: 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? Colors.white : AppTheme.textMain,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 시간 옵션 정의
// ═══════════════════════════════════════════════════
class _DurationOption {
  final int minutes;
  final String label;
  const _DurationOption({
    required this.minutes,
    required this.label,
  });
}