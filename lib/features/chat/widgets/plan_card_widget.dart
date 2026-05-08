import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../models/plan_model.dart';
import '../services/plan_service.dart';

/// ═══════════════════════════════════════════════════
/// 약속 카드 위젯 (채팅방 인라인 표시용)
///
/// onUpdated: 업데이트된 PlanModel 직접 받음 (즉시 반영용)
/// onDismissed: dismiss/삭제 시 호출
/// ═══════════════════════════════════════════════════
class PlanCard extends StatelessWidget {
  final PlanModel plan;
  final VoidCallback? onDismissed;
  final void Function(PlanModel updated)? onUpdated;
  final bool compact;

  const PlanCard({
    super.key,
    required this.plan,
    this.onDismissed,
    this.onUpdated,
    this.compact = false,
  });

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PlanDetailSheet(
        plan: plan,
        onDismissed: onDismissed,
        onUpdated: onUpdated,
      ),
    );
  }

  Color _statusColor() {
    switch (plan.status) {
      case 'completed':
        return const Color(0xFF06B6D4);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return AppTheme.primary;
    }
  }

  String? _statusLabel() {
    switch (plan.status) {
      case 'completed':
        return '완료';
      case 'cancelled':
        return '취소됨';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor();
    final statusLabel = _statusLabel();
    final isDimmed = plan.status != 'upcoming';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: isDimmed ? 0.6 : 1.0,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.12),
                  accent.withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withOpacity(0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    plan.status == 'completed'
                        ? Icons.check_circle_outline
                        : plan.status == 'cancelled'
                            ? Icons.cancel_outlined
                            : Icons.event_note_outlined,
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: accent, size: 11),
                          const SizedBox(width: 3),
                          Text(
                            statusLabel ?? 'AI가 약속을 발견했어요',
                            style: TextStyle(
                              color: accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.title,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          decoration: plan.status == 'cancelled'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              color: AppTheme.textSub, size: 11),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              plan.friendlyTime,
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (plan.location != null) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.place_outlined,
                                color: AppTheme.textSub, size: 11),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                plan.location!,
                                style: TextStyle(
                                  color: AppTheme.textSub,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (plan.status == 'upcoming')
                  GestureDetector(
                    onTap: () async {
                      final ok = await PlanService.dismissPlan(plan.id);
                      if (ok) onDismissed?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: AppTheme.textSub,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 상세 시트
// ═══════════════════════════════════════════════════
class _PlanDetailSheet extends StatefulWidget {
  final PlanModel plan;
  final VoidCallback? onDismissed;
  final void Function(PlanModel updated)? onUpdated;

  const _PlanDetailSheet({
    required this.plan,
    this.onDismissed,
    this.onUpdated,
  });

  @override
  State<_PlanDetailSheet> createState() => _PlanDetailSheetState();
}

class _PlanDetailSheetState extends State<_PlanDetailSheet> {
  bool _busy = false;

  Future<void> _copyToClipboard() async {
    final p = widget.plan;
    final buf = StringBuffer();
    buf.writeln(p.title);
    buf.writeln(p.friendlyTime);
    if (p.location != null) buf.writeln('📍 ${p.location}');
    if (p.attendees.isNotEmpty) {
      buf.writeln('👥 ${p.attendees.join(", ")}');
    }
    if (p.notes != null) buf.writeln(p.notes);

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('약속 정보를 복사했어요'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 즉시 로컬 UI에 반영 + DB 업데이트
  Future<void> _changeStatus(String newStatus, String successMsg) async {
    if (_busy) return;
    setState(() => _busy = true);

    final ok = await PlanService.updateStatus(
      planId: widget.plan.id,
      status: newStatus,
    );

    if (!mounted) return;

    if (ok) {
      // 즉시 부모에 새 PlanModel 전달
      final updated = widget.plan.copyWith(status: newStatus);
      widget.onUpdated?.call(updated);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg)),
      );
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('처리에 실패했어요. 다시 시도해주세요.')),
      );
    }
  }

  Future<void> _markCompleted() => _changeStatus('completed', '약속을 완료로 표시했어요');
  Future<void> _markCancelled() => _changeStatus('cancelled', '약속을 취소로 표시했어요');
  Future<void> _markUpcoming() => _changeStatus('upcoming', '다가오는 약속으로 되돌렸어요');

  Future<void> _delete() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('약속 삭제', style: TextStyle(color: AppTheme.textMain)),
        content: Text(
          '이 약속을 완전히 삭제할까요? 삭제하면 다시 복구할 수 없어요.',
          style: TextStyle(color: AppTheme.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final result = await PlanService.deletePlan(widget.plan.id);
    if (!mounted) return;
    if (result) {
      Navigator.pop(context);
      widget.onDismissed?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약속을 삭제했어요')),
      );
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했어요. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.event_note_outlined,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '약속 자세히',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.title,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (p.status != 'upcoming')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: p.status == 'completed'
                          ? const Color(0xFF06B6D4).withOpacity(0.18)
                          : const Color(0xFFEF4444).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p.status == 'completed' ? '완료' : '취소됨',
                      style: TextStyle(
                        color: p.status == 'completed'
                            ? const Color(0xFF06B6D4)
                            : const Color(0xFFEF4444),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 18),

            _InfoRow(
              icon: Icons.schedule,
              label: '시간',
              value: p.friendlyTime,
            ),
            if (p.location != null) ...[
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.place_outlined,
                label: '장소',
                value: p.location!,
              ),
            ],
            if (p.attendees.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.people_outline,
                label: '참석자',
                value: p.attendees.join(', '),
              ),
            ],
            if (p.notes != null) ...[
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.notes_outlined,
                label: '메모',
                value: p.notes!,
              ),
            ],

            const SizedBox(height: 22),

            // 액션 버튼들 (status에 따라 분기)
            if (p.status == 'upcoming')
              _buildUpcomingActions()
            else
              _buildCompletedOrCancelledActions(),

            const SizedBox(height: 8),

            // 삭제 버튼
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFEF4444), size: 14),
              label: const Text(
                '약속 삭제',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _copyToClipboard,
            icon: Icon(Icons.copy_outlined,
                color: AppTheme.textMain, size: 16),
            label: Text(
              '복사',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _markCompleted,
            icon: const Icon(Icons.check_circle_outline,
                color: Color(0xFF06B6D4), size: 16),
            label: const Text(
              '완료',
              style: TextStyle(
                color: Color(0xFF06B6D4),
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF06B6D4), width: 1),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _markCancelled,
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFFEF4444), size: 16),
            label: const Text(
              '취소',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFEF4444), width: 1),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedOrCancelledActions() {
    // 완료/취소된 약속은 "되돌리기" 버튼 표시
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _copyToClipboard,
            icon: Icon(Icons.copy_outlined,
                color: AppTheme.textMain, size: 16),
            label: Text(
              '복사',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _markUpcoming,
            icon: Icon(Icons.refresh,
                color: AppTheme.primary, size: 16),
            label: Text(
              '되돌리기',
              style: TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primary, width: 1),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, color: AppTheme.textSub, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}