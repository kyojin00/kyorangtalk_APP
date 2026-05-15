import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../services/schedule_service.dart';

// ═══════════════════════════════════════════════════
// 📅 ScheduleCreateSheet — TextField 무한 너비 방어 강화
// ═══════════════════════════════════════════════════

Future<ScheduleEvent?> showScheduleCreateSheet(
  BuildContext context, {
  required String roomId,
  required String roomType,
}) {
  return showModalBottomSheet<ScheduleEvent?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ScheduleCreateSheet(
      roomId:   roomId,
      roomType: roomType,
    ),
  );
}

class _ScheduleCreateSheet extends StatefulWidget {
  final String roomId;
  final String roomType;

  const _ScheduleCreateSheet({
    required this.roomId,
    required this.roomType,
  });

  @override
  State<_ScheduleCreateSheet> createState() =>
      _ScheduleCreateSheetState();
}

class _ScheduleCreateSheetState extends State<_ScheduleCreateSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  late DateTime _dateFrom;
  late DateTime _dateTo;

  int _timeFromMin = 18 * 60;
  int _timeToMin   = 23 * 60;
  int _slotMinutes = 60;

  bool _creating = false;

  static const int _maxDays = 14;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dateFrom = DateTime(today.year, today.month, today.day);
    _dateTo   = _dateFrom.add(const Duration(days: 6));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDateRange:
          DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppTheme.primary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    var from = DateTime(picked.start.year, picked.start.month,
        picked.start.day);
    var to = DateTime(picked.end.year, picked.end.month, picked.end.day);

    final days = to.difference(from).inDays + 1;
    if (days > _maxDays) {
      to = from.add(const Duration(days: _maxDays - 1));
      _showSnack('최대 $_maxDays일까지 선택할 수 있어요');
    }

    setState(() {
      _dateFrom = from;
      _dateTo   = to;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initialMin = isStart ? _timeFromMin : _timeToMin;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMin ~/ 60,
        minute: initialMin % 60,
      ),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppTheme.primary,
                ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              alwaysUse24HourFormat: true,
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked == null) return;

    final newMin = picked.hour * 60 + picked.minute;
    final aligned = (newMin / 30).round() * 30;

    setState(() {
      if (isStart) {
        _timeFromMin = aligned;
        if (_timeToMin <= _timeFromMin) {
          _timeToMin = _timeFromMin + _slotMinutes;
        }
      } else {
        if (aligned <= _timeFromMin) {
          _showSnack('종료 시간은 시작 시간보다 커야 해요');
          return;
        }
        _timeToMin = aligned;
      }
    });
  }

  String _fmtTime(int totalMin) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtDate(DateTime d) {
    return '${d.month}월 ${d.day}일 (${_weekday(d.weekday)})';
  }

  String _weekday(int w) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[w - 1];
  }

  Future<void> _onCreate() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('제목을 입력해주세요');
      return;
    }

    final rangeMin = _timeToMin - _timeFromMin;
    if (rangeMin <= 0) {
      _showSnack('시간 범위를 확인해주세요');
      return;
    }
    if (rangeMin < _slotMinutes) {
      _showSnack('시간 범위가 슬롯 단위보다 작아요');
      return;
    }

    setState(() => _creating = true);

    final event = await ScheduleService.instance.createEvent(
      roomId:      widget.roomId,
      roomType:    widget.roomType,
      title:       _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      dateFrom:    _dateFrom,
      dateTo:      _dateTo,
      timeFrom:    _fmtTime(_timeFromMin),
      timeTo:      _fmtTime(_timeToMin),
      slotMinutes: _slotMinutes,
    );

    if (!mounted) return;

    if (event == null) {
      setState(() => _creating = false);
      _showSnack('일정 생성에 실패했어요');
      return;
    }

    Navigator.pop(context, event);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // ⭐ 명시 너비: 화면 너비 - 좌우 마진 16px (양쪽 8px씩)
    final sheetWidth = screenWidth - 16;
    final contentWidth = sheetWidth - 40; // 좌우 padding 20px*2

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Center(
          child: Container(
            width: sheetWidth,                         // ⭐ tight width
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  // ⭐ start (stretch X — 자식 각자 명시 너비)
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 헤더 — Row (자식 명시 너비 + Expanded)
                    SizedBox(
                      width: contentWidth,
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.calendar_today_rounded,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '일정 잡기',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textMain,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '가능한 시간을 모아 최적 시간을 찾아요',
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
                    ),

                    const SizedBox(height: 22),

                    // 제목
                    _label('제목'),
                    const SizedBox(height: 6),
                    // ⭐ TextField를 명시 너비 SizedBox로 감쌈
                    SizedBox(
                      width: contentWidth,
                      child: _TextInput(
                        controller: _titleCtrl,
                        hint: '예: 이번 주 모임',
                        maxLength: 50,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 설명
                    _label('설명 (선택)'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: contentWidth,
                      child: _TextInput(
                        controller: _descCtrl,
                        hint: '간단한 설명을 적어주세요',
                        maxLength: 200,
                        maxLines: 2,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 날짜 범위
                    _label('날짜 범위 (최대 $_maxDays일)'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: contentWidth,
                      child: _SelectRow(
                        icon: Icons.calendar_month_rounded,
                        text:
                            '${_fmtDate(_dateFrom)} → ${_fmtDate(_dateTo)}',
                        onTap: _pickDateRange,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 시간 범위
                    _label('시간 범위'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: contentWidth,
                      child: Row(
                        children: [
                          Expanded(
                            child: _SelectRow(
                              icon: Icons.access_time_rounded,
                              text: _fmtTime(_timeFromMin),
                              onTap: () => _pickTime(isStart: true),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                            child: Text(
                              '~',
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _SelectRow(
                              icon: Icons.access_time_rounded,
                              text: _fmtTime(_timeToMin),
                              onTap: () => _pickTime(isStart: false),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 슬롯 단위
                    _label('시간 단위'),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: contentWidth,
                      child: Row(
                        children: [
                          Expanded(
                            child: _Chip(
                              label: '30분 단위',
                              selected: _slotMinutes == 30,
                              onTap: () =>
                                  setState(() => _slotMinutes = 30),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Chip(
                              label: '1시간 단위',
                              selected: _slotMinutes == 60,
                              onTap: () =>
                                  setState(() => _slotMinutes = 60),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // 생성 버튼
                    SizedBox(
                      width: contentWidth,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _onCreate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          disabledBackgroundColor:
                              AppTheme.primary.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '만들기',
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: AppTheme.textSub,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 텍스트 입력 — 부모가 너비 강제
// ═══════════════════════════════════════════════════
class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int maxLines;

  const _TextInput({
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: TextStyle(
        color: AppTheme.textMain,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: TextStyle(
          color: AppTheme.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: AppTheme.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 선택 row
// ═══════════════════════════════════════════════════
class _SelectRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _SelectRow({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 선택 칩
// ═══════════════════════════════════════════════════
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primary : AppTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
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
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textMain,
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