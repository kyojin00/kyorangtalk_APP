import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/report_provider.dart';

/// 사용자 신고 다이얼로그
Future<bool?> showReportUserDialog({
  required BuildContext context,
  required String reportedUserId,
  required String reportedNickname,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ReportDialog(
      type: ReportType.user,
      targetId: reportedUserId,
      targetName: reportedNickname,
    ),
  );
}

/// 메시지 신고 다이얼로그
Future<bool?> showReportMessageDialog({
  required BuildContext context,
  required String messageId,
  required String senderId,
  required String roomId,
  required String messageContent,
  required String senderNickname,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ReportDialog(
      type: ReportType.message,
      targetId: messageId,
      targetName: senderNickname,
      messageContent: messageContent,
      senderId: senderId,
      roomId: roomId,
    ),
  );
}

class ReportDialog extends ConsumerStatefulWidget {
  final ReportType type;
  final String targetId;
  final String targetName;
  final String? messageContent;
  final String? senderId;
  final String? roomId;

  const ReportDialog({
    super.key,
    required this.type,
    required this.targetId,
    required this.targetName,
    this.messageContent,
    this.senderId,
    this.roomId,
  });

  @override
  ConsumerState<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<ReportDialog> {
  ReportReason? _selectedReason;
  final _descController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;

    setState(() => _submitting = true);

    try {
      final service = ref.read(reportServiceProvider);

      if (widget.type == ReportType.user) {
        await service.reportUser(
          reportedUserId: widget.targetId,
          reason: _selectedReason!,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
        );
      } else if (widget.type == ReportType.message) {
        await service.reportMessage(
          messageId: widget.targetId,
          senderId: widget.senderId!,
          roomId: widget.roomId!,
          messageContent: widget.messageContent ?? '',
          reason: _selectedReason!,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('신고가 접수되었어요. 빠르게 처리하겠습니다'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'.replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flag_outlined,
                        color: Color(0xFFEF4444), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.type == ReportType.user
                              ? '사용자 신고'
                              : '메시지 신고',
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.targetName,
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppTheme.textSub, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: AppTheme.border),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.messageContent != null &&
                        widget.messageContent!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '신고할 메시지',
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.messageContent!.length > 100
                                  ? '${widget.messageContent!.substring(0, 100)}...'
                                  : widget.messageContent!,
                              style: TextStyle(
                                color: AppTheme.textMain,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Text(
                      '신고 사유를 선택해주세요',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ...ReportReason.values.map((reason) {
                      final isSelected = _selectedReason == reason;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => setState(
                              () => _selectedReason = reason),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEF4444).withOpacity(0.1)
                                  : AppTheme.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFEF4444)
                                    : AppTheme.border,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 18, height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFEF4444)
                                          : AppTheme.textMuted,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Container(
                                            width: 8, height: 8,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  reason.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? const Color(0xFFEF4444)
                                        : AppTheme.textMain,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),

                    Text(
                      '상세 설명 (선택)',
                      style: TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: TextField(
                        controller: _descController,
                        maxLines: 3,
                        maxLength: 200,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: '신고 내용을 자세히 설명해주세요',
                          hintStyle: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.all(12),
                          counterStyle: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              color: AppTheme.primary, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '허위 신고는 제재 대상이 될 수 있어요. 신고하신 내용은 24시간 이내 검토됩니다.',
                              style: TextStyle(
                                color: AppTheme.textSub,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: AppTheme.border),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: Text(
                        '취소',
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          _selectedReason == null || _submitting
                              ? null
                              : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '신고하기',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}