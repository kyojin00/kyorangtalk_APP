import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../models/schedule_models.dart';
import '../services/schedule_service.dart';

// ═══════════════════════════════════════════════════
// 📅 ScheduleResponseScreen
// ═══════════════════════════════════════════════════

class ScheduleResponseScreen extends StatefulWidget {
  final String eventId;

  const ScheduleResponseScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<ScheduleResponseScreen> createState() =>
      _ScheduleResponseScreenState();
}

class _ScheduleResponseScreenState extends State<ScheduleResponseScreen>
    with SingleTickerProviderStateMixin {
  ScheduleSummary? _summary;
  bool _loading = true;
  bool _showResult = false;
  bool _saving = false;
  bool _dirty = false;

  final Set<DateTime> _mySelectedSlots = {};

  String get _myId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  ScheduleEvent? get _event => _summary?.event;
  bool get _amICreator => _event?.creatorId == _myId;

  // ─── 디자인 토큰 ───
  static const double _hourLabelWidth = 36;
  static const double _cellHeight = 32;
  static const double _headerHeight = 48;
  static const double _cellGap = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary =
          await ScheduleService.instance.getSummary(widget.eventId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _mySelectedSlots
          ..clear()
          ..addAll(summary?.mySlots ?? {});
        _loading = false;
      });
    } catch (e) {
      print('🔴 일정 로드 실패: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final summary =
        await ScheduleService.instance.getSummary(widget.eventId);
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  Future<void> _saveResponse() async {
    if (_event == null || _saving) return;
    setState(() => _saving = true);
    final ok = await ScheduleService.instance.submitResponse(
      eventId: _event!.id,
      selectedSlots: _mySelectedSlots,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _dirty = false;
    });
    if (ok) {
      _showSnack('응답을 저장했어요', success: true);
      await _refresh();
    } else {
      _showSnack('저장에 실패했어요');
    }
  }

  Future<void> _confirmSlot(DateTime start) async {
    if (_event == null) return;
    final end = start.add(Duration(minutes: _event!.slotMinutes));

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        ctx: ctx,
        icon: Icons.event_available_rounded,
        iconColor: AppTheme.primary,
        title: '일정 확정',
        content: '${_fmtFull(start)}\n이 시간으로 확정할까요?',
        primaryLabel: '확정',
        primaryColor: AppTheme.primary,
      ),
    );

    if (confirm != true) return;

    final ok = await ScheduleService.instance.confirmSchedule(
      eventId: _event!.id,
      start: start,
      end: end,
    );

    if (!mounted) return;
    if (ok) {
      _showSnack('일정이 확정됐어요', success: true);
      await _refresh();
    } else {
      _showSnack('확정에 실패했어요');
    }
  }

  Future<void> _unconfirm() async {
    if (_event == null) return;
    final ok =
        await ScheduleService.instance.unconfirmSchedule(_event!.id);
    if (!mounted) return;
    if (ok) {
      _showSnack('확정을 해제했어요');
      await _refresh();
    }
  }

  Future<void> _showSlotUsers(DateTime slot) async {
    if (_event == null) return;
    final users = await ScheduleService.instance.getSlotUsers(
      eventId: _event!.id,
      slotStart: slot,
    );

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SlotUsersSheet(
        slot: slot,
        users: users,
        canConfirm: _amICreator && !_event!.isConfirmed,
        onConfirm: () {
          Navigator.pop(context);
          _confirmSlot(slot);
        },
        fmtFull: _fmtFull,
      ),
    );
  }

  void _toggleSlot(DateTime slot) {
    setState(() {
      if (_mySelectedSlots.contains(slot)) {
        _mySelectedSlots.remove(slot);
      } else {
        _mySelectedSlots.add(slot);
      }
      _dirty = true;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _onDeleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        ctx: ctx,
        icon: Icons.delete_outline_rounded,
        iconColor: const Color(0xFFEF4444),
        title: '일정 삭제',
        content: '일정을 삭제하면 모든 응답도 함께 사라져요.\n계속할까요?',
        primaryLabel: '삭제',
        primaryColor: const Color(0xFFEF4444),
      ),
    );
    if (confirm != true || _event == null) return;
    final ok =
        await ScheduleService.instance.deleteEvent(_event!.id);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      _showSnack('삭제에 실패했어요');
    }
  }

  // ─── 다이얼로그 빌더 ───
  Widget _buildDialog({
    required BuildContext ctx,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    required String primaryLabel,
    required Color primaryColor,
  }) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              content,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _dialogButton(
                    label: '취소',
                    onTap: () => Navigator.pop(ctx, false),
                    isPrimary: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dialogButton(
                    label: primaryLabel,
                    onTap: () => Navigator.pop(ctx, true),
                    isPrimary: true,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isPrimary
              ? (color ?? AppTheme.primary)
              : AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: isPrimary
              ? null
              : Border.all(color: AppTheme.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? Colors.white : AppTheme.textSub,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: success ? AppTheme.primary : AppTheme.textSub,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(msg,
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
        backgroundColor: AppTheme.bgCard,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.border),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 0,
      ),
    );
  }

  String _fmtFull(DateTime dt) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final w = days[dt.weekday - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}월 ${dt.day}일 ($w) $h:$m';
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 48,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textMain, size: 18),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      title: _event == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _event!.title,
                  style: TextStyle(
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _eventSubtitle(),
                  style: TextStyle(
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    letterSpacing: -0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
      titleSpacing: 0,
      actions: [
        if (_amICreator && _event != null && !_event!.isConfirmed)
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: const Color(0xFFEF4444), size: 22),
            onPressed: _onDeleteEvent,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _eventSubtitle() {
    final e = _event!;
    final from = e.dateFrom;
    final to = e.dateTo;
    if (from.year == to.year &&
        from.month == to.month &&
        from.day == to.day) {
      return '${from.month}월 ${from.day}일 · ${e.timeFrom}–${e.timeTo}';
    }
    return '${from.month}/${from.day} – ${to.month}/${to.day} · ${e.timeFrom}–${e.timeTo}';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_summary == null || _event == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded,
                color: AppTheme.textMuted, size: 36),
            const SizedBox(height: 12),
            Text('일정을 불러올 수 없어요',
                style: TextStyle(
                    color: AppTheme.textSub,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final event = _event!;
    final summary = _summary!;
    final dayCount = event.dayCount;
    final slotsPerDay = event.slotsPerDay;

    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 32 - _hourLabelWidth;
    final cellWidth = (availableWidth / dayCount).clamp(28.0, 70.0);

    return Column(
      children: [
        // 토글
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildToggle(),
        ),

        // 확정 배너
        if (event.isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _ConfirmedBanner(
              event: event,
              canUnconfirm: _amICreator,
              onUnconfirm: _unconfirm,
            ),
          ),

        // 최적 시간
        if (_showResult && summary.bestSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _BestSlotsCard(
              bestSlots: summary.bestSlots,
              maxCount: summary.maxCount,
              total: summary.participants.length,
              canConfirm: _amICreator && !event.isConfirmed,
              onConfirm: _confirmSlot,
            ),
          ),

        // 안내
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildHint(summary.participants.length),
        ),

        // 그리드
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: slotsPerDay + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildHeaderRow(dayCount, cellWidth);
              }
              return _buildGridRow(index - 1, dayCount, cellWidth);
            },
          ),
        ),

        // 히트맵 범례
        if (_showResult && summary.participants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _HeatmapLegend(
                total: summary.participants.length),
          ),
      ],
    );
  }

  Widget _buildHint(int participantCount) {
    final isEmptyResult = _showResult && participantCount == 0;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.border.withOpacity(0.6), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            _showResult
                ? Icons.people_outline_rounded
                : Icons.touch_app_outlined,
            size: 14,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _showResult
                  ? (isEmptyResult
                      ? '아직 응답한 사람이 없어요'
                      : '$participantCount명 응답 · 셀을 탭하면 응답자가 보여요')
                  : '가능한 시간을 탭하세요',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSub,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 토글 ───
  Widget _buildToggle() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.8),
      ),
      child: Stack(
        children: [
          // 슬라이딩 인디케이터
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: _showResult
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 라벨
          Row(
            children: [
              _toggleLabel('내 가능 시간',
                  Icons.touch_app_outlined, !_showResult, () {
                setState(() => _showResult = false);
              }),
              _toggleLabel('모두의 결과',
                  Icons.people_outline_rounded, _showResult, () {
                setState(() => _showResult = true);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleLabel(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSub,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: selected
                      ? Colors.white
                      : AppTheme.textSub,
                ),
                const SizedBox(width: 5),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 요일 헤더 ───
  Widget _buildHeaderRow(int dayCount, double cellWidth) {
    final event = _event!;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: _hourLabelWidth),
          for (int d = 0; d < dayCount; d++)
            SizedBox(
              width: cellWidth,
              child: () {
                final day = event.dateFrom.add(Duration(days: d));
                final isToday = day.year == todayDate.year &&
                    day.month == todayDate.month &&
                    day.day == todayDate.day;
                final weekend = day.weekday >= 6;
                final dayColor = isToday
                    ? AppTheme.primary
                    : (weekend
                        ? const Color(0xFFEF4444)
                        : AppTheme.textSub);
                final dateColor = isToday
                    ? AppTheme.primary
                    : (weekend
                        ? const Color(0xFFEF4444)
                        : AppTheme.textMain);

                return Container(
                  margin: EdgeInsets.symmetric(
                      horizontal: _cellGap / 2),
                  decoration: isToday
                      ? BoxDecoration(
                          color:
                              AppTheme.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        days[day.weekday - 1],
                        style: TextStyle(
                          fontSize: 10,
                          color: dayColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          color: dateColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                );
              }(),
            ),
        ],
      ),
    );
  }

  // ─── 그리드 행 ───
  Widget _buildGridRow(int slotIndex, int dayCount, double cellWidth) {
    final event = _event!;
    final slot0 = event.slotAt(dayIndex: 0, slotIndex: slotIndex);
    final isHour = slot0.minute == 0;
    final heatmap = _summary!.heatmapMap;
    final total = _summary!.participants.length;

    return Container(
      height: _cellHeight + _cellGap,
      padding: EdgeInsets.only(top: _cellGap),
      child: Row(
        children: [
          SizedBox(
            width: _hourLabelWidth,
            child: isHour
                ? Padding(
                    padding: const EdgeInsets.only(right: 8, top: 0),
                    child: Text(
                      slot0.hour.toString().padLeft(2, '0'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSub,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          for (int d = 0; d < dayCount; d++)
            _buildCell(d, slotIndex, cellWidth, heatmap, total),
        ],
      ),
    );
  }

  Widget _buildCell(
    int dayIndex,
    int slotIndex,
    double cellWidth,
    Map<DateTime, int> heatmap,
    int total,
  ) {
    final event = _event!;
    final slot =
        event.slotAt(dayIndex: dayIndex, slotIndex: slotIndex);
    final selected = _mySelectedSlots.contains(slot);
    final count = heatmap[slot] ?? 0;

    Color color;
    Color? borderColor;
    Widget? content;

    if (_showResult) {
      if (total == 0 || count == 0) {
        color = AppTheme.bgCard.withOpacity(0.4);
        borderColor = AppTheme.border.withOpacity(0.4);
      } else {
        final ratio = count / total;
        color = Color.lerp(
          AppTheme.primary.withOpacity(0.18),
          AppTheme.primary,
          ratio,
        )!;
        borderColor = AppTheme.primary.withOpacity(0.3);
      }
      if (count > 0) {
        content = Center(
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: count >= total / 2
                  ? Colors.white
                  : AppTheme.textMain,
            ),
          ),
        );
      }
    } else {
      if (selected) {
        color = AppTheme.primary;
        borderColor = AppTheme.primary;
        content = const Center(
          child: Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 14,
          ),
        );
      } else {
        color = AppTheme.bgCard.withOpacity(0.5);
        borderColor = AppTheme.border.withOpacity(0.5);
      }
    }

    return SizedBox(
      width: cellWidth,
      height: _cellHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _cellGap / 2),
        child: GestureDetector(
          onTap: () {
            if (_showResult) {
              if (count > 0) _showSlotUsers(slot);
            } else {
              _toggleSlot(slot);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: borderColor ?? AppTheme.border,
                width: 0.6,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  // ─── 하단 저장 바 ───
  Widget? _buildBottomBar() {
    if (_event == null) return null;
    if (_event!.isConfirmed || _event!.isExpired) return null;
    if (_showResult) return null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          border: Border(
            top: BorderSide(
                color: AppTheme.border.withOpacity(0.6), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 선택 카운트 칩
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _dirty
                    ? const Color(0xFFEF4444).withOpacity(0.12)
                    : AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _dirty
                        ? Icons.circle
                        : Icons.check_circle_rounded,
                    size: 11,
                    color: _dirty
                        ? const Color(0xFFEF4444)
                        : AppTheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _dirty
                        ? '변경됨'
                        : '${_mySelectedSlots.length}개 선택',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _dirty
                          ? const Color(0xFFEF4444)
                          : AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // 저장 버튼
            GestureDetector(
              onTap: (_dirty && !_saving) ? _saveResponse : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 11),
                decoration: BoxDecoration(
                  gradient: (_dirty && !_saving)
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.85),
                          ],
                        )
                      : null,
                  color: (_dirty && !_saving)
                      ? null
                      : AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: (_dirty && !_saving)
                      ? null
                      : Border.all(color: AppTheme.border),
                  boxShadow: (_dirty && !_saving)
                      ? [
                          BoxShadow(
                            color:
                                AppTheme.primary.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        '저장',
                        style: TextStyle(
                          color: (_dirty && !_saving)
                              ? Colors.white
                              : AppTheme.textMuted,
                          fontSize: 13,
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
// 확정 배너
// ═══════════════════════════════════════════════════
class _ConfirmedBanner extends StatelessWidget {
  final ScheduleEvent event;
  final bool canUnconfirm;
  final VoidCallback onUnconfirm;

  const _ConfirmedBanner({
    required this.event,
    required this.canUnconfirm,
    required this.onUnconfirm,
  });

  @override
  Widget build(BuildContext context) {
    final start = event.confirmedStart!;
    final end = event.confirmedEnd!;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final w = days[start.weekday - 1];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.22),
            AppTheme.primary.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '확정됨',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${start.month}월 ${start.day}일 ($w) '
                  '${start.hour.toString().padLeft(2, '0')}:'
                  '${start.minute.toString().padLeft(2, '0')} ~ '
                  '${end.hour.toString().padLeft(2, '0')}:'
                  '${end.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMain,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (canUnconfirm)
            GestureDetector(
              onTap: onUnconfirm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text('해제',
                    style: TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2)),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 최적 시간 카드
// ═══════════════════════════════════════════════════
class _BestSlotsCard extends StatelessWidget {
  final List<DateTime> bestSlots;
  final int maxCount;
  final int total;
  final bool canConfirm;
  final ValueChanged<DateTime> onConfirm;

  const _BestSlotsCard({
    required this.bestSlots,
    required this.maxCount,
    required this.total,
    required this.canConfirm,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.15),
            AppTheme.primary.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded,
                  color: AppTheme.primary, size: 15),
              const SizedBox(width: 5),
              Text(
                '가장 많이 가능한 시간',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$maxCount/$total',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final slot in bestSlots.take(6))
                _BestChip(
                  slot: slot,
                  canConfirm: canConfirm,
                  onTap: () => onConfirm(slot),
                ),
            ],
          ),
          if (bestSlots.length > 6) ...[
            const SizedBox(height: 6),
            Text(
              '외 ${bestSlots.length - 6}개',
              style: TextStyle(
                fontSize: 10.5,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BestChip extends StatelessWidget {
  final DateTime slot;
  final bool canConfirm;
  final VoidCallback onTap;

  const _BestChip({
    required this.slot,
    required this.canConfirm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final w = days[slot.weekday - 1];
    final h = slot.hour.toString().padLeft(2, '0');
    final m = slot.minute.toString().padLeft(2, '0');
    final label = '${slot.month}/${slot.day}($w) $h:$m';

    return GestureDetector(
      onTap: canConfirm ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppTheme.border.withOpacity(0.7), width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMain,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            if (canConfirm) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded,
                  size: 11, color: AppTheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 히트맵 범례
// ═══════════════════════════════════════════════════
class _HeatmapLegend extends StatelessWidget {
  final int total;
  const _HeatmapLegend({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '0명',
            style: TextStyle(
                fontSize: 10,
                color: AppTheme.textSub,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          for (int i = 0; i <= total; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 18,
                height: 14,
                decoration: BoxDecoration(
                  color: i == 0
                      ? AppTheme.bgCard.withOpacity(0.4)
                      : Color.lerp(
                          AppTheme.primary.withOpacity(0.18),
                          AppTheme.primary,
                          i / total,
                        )!,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: i == 0
                        ? AppTheme.border.withOpacity(0.5)
                        : AppTheme.primary.withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            '$total명',
            style: TextStyle(
                fontSize: 10,
                color: AppTheme.textSub,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 응답자 시트
// ═══════════════════════════════════════════════════
class _SlotUsersSheet extends StatelessWidget {
  final DateTime slot;
  final List<Map<String, dynamic>> users;
  final bool canConfirm;
  final VoidCallback onConfirm;
  final String Function(DateTime) fmtFull;

  const _SlotUsersSheet({
    required this.slot,
    required this.users,
    required this.canConfirm,
    required this.onConfirm,
    required this.fmtFull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 헤더
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.schedule_rounded,
                        color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmtFull(slot),
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMain,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${users.length}명이 가능해요',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSub,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (users.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('응답한 사람이 없어요',
                        style: TextStyle(
                            color: AppTheme.textSub, fontSize: 13)),
                  ),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final u in users)
                      Container(
                        padding:
                            const EdgeInsets.fromLTRB(4, 4, 12, 4),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: AppTheme.border, width: 0.6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AvatarWidget(
                              url: u['avatar_url'] as String?,
                              name: u['nickname'] as String?,
                              size: 24,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              (u['nickname'] as String?) ?? '...',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMain,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (canConfirm && users.isNotEmpty) ...[
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: onConfirm,
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.event_available_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 7),
                        Text(
                          '이 시간으로 확정',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}