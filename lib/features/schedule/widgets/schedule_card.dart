import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../services/schedule_service.dart';

// ═══════════════════════════════════════════════════
// 📅 ScheduleCard — 단순화 (Container width 만)
// ═══════════════════════════════════════════════════

class ScheduleCard extends StatefulWidget {
  final String eventId;
  final VoidCallback? onTap;
  final double? maxWidth;

  const ScheduleCard({
    super.key,
    required this.eventId,
    this.onTap,
    this.maxWidth,
  });

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  ScheduleEvent? _event;
  int _participantCount = 0;
  bool _loading = true;

  static const double _kCardWidth = 260;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) _load();
  }

  Future<void> _load() async {
    final summary =
        await ScheduleService.instance.getSummary(widget.eventId);
    if (!mounted) return;
    setState(() {
      _event = summary?.event;
      _participantCount = summary?.participants.length ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = widget.maxWidth ?? _kCardWidth;

    // 🔑 최외곽을 단순한 Container(width)로 — 모든 부모 제약 무시
    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: _buildContent(cardWidth),
      ),
    );
  }

  Widget _buildContent(double cardWidth) {
    if (_loading) {
      return Container(
        width: cardWidth,
        height: 96,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      );
    }

    final event = _event;
    if (event == null) {
      return Container(
        width: cardWidth,
        padding: const EdgeInsets.all(16),
        child: Text(
          '일정을 불러올 수 없어요',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13),
        ),
      );
    }

    // 헤더 + 본문 두 개를 단순 Column 으로 (stretch X)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(event, cardWidth),
        _buildBody(event, cardWidth),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 헤더
  // ═══════════════════════════════════════════════════
  Widget _buildHeader(ScheduleEvent event, double width) {
    final Color accent;
    final IconData icon;
    final String stateLabel;

    if (event.isConfirmed) {
      accent = AppTheme.primary;
      icon = Icons.check_circle_rounded;
      stateLabel = '확정됨';
    } else if (event.isExpired) {
      accent = AppTheme.textMuted;
      icon = Icons.event_busy_rounded;
      stateLabel = '만료됨';
    } else {
      accent = AppTheme.primary;
      icon = Icons.calendar_today_rounded;
      stateLabel = '응답 모집 중';
    }

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.18),
            accent.withOpacity(0.06),
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          SizedBox(
            // 헤더 width - 아이콘(32) - gap(10) - padding(14*2) = width - 84
            width: width - 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stateLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 본문
  // ═══════════════════════════════════════════════════
  Widget _buildBody(ScheduleEvent event, double width) {
    if (event.isConfirmed) {
      return _confirmedBody(event, width);
    }
    return _pollingBody(event, width);
  }

  Widget _confirmedBody(ScheduleEvent event, double width) {
    final start = event.confirmedStart!;
    final end = event.confirmedEnd!;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final w = days[start.weekday - 1];

    final contentWidth = width - 28; // padding 14*2

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: SizedBox(
        width: contentWidth,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_rounded,
              color: AppTheme.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: contentWidth - 22,
              child: Text(
                '${start.month}월 ${start.day}일 ($w) '
                '${_hhmm(start)} ~ ${_hhmm(end)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pollingBody(ScheduleEvent event, double width) {
    final expired = event.isExpired;
    final contentWidth = width - 28;

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜
          SizedBox(
            width: contentWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  color: AppTheme.textSub,
                  size: 14,
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: contentWidth - 19,
                  child: Text(
                    _dateRangeText(event),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // 시간
          SizedBox(
            width: contentWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  color: AppTheme.textSub,
                  size: 14,
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: contentWidth - 19,
                  child: Text(
                    '${event.timeFrom} ~ ${event.timeTo} · '
                    '${event.slotMinutes}분 단위',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSub,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 응답자 + CTA
          SizedBox(
            width: contentWidth,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: expired
                        ? AppTheme.bg
                        : AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: expired
                          ? AppTheme.border
                          : AppTheme.primary.withOpacity(0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 11,
                        color: expired
                            ? AppTheme.textMuted
                            : AppTheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$_participantCount명 응답',
                        style: TextStyle(
                          fontSize: 11,
                          color: expired
                              ? AppTheme.textMuted
                              : AppTheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!expired)
                  Text(
                    '응답하기 →',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  Text(
                    '만료됨',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateRangeText(ScheduleEvent event) {
    final from = event.dateFrom;
    final to = event.dateTo;
    if (from.year == to.year &&
        from.month == to.month &&
        from.day == to.day) {
      return '${from.month}월 ${from.day}일';
    }
    return '${from.month}/${from.day} ~ ${to.month}/${to.day}';
  }

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}