import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../services/chat_summary_service.dart';

/// ═══════════════════════════════════════════════════
/// 안 읽은 메시지 AI 요약 바텀시트
/// 사용법: showSummarySheet(context, roomId: ..., isGroup: ...)
/// ═══════════════════════════════════════════════════
Future<void> showSummarySheet(
  BuildContext context, {
  required String roomId,
  required bool isGroup,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SummarySheet(roomId: roomId, isGroup: isGroup),
  );
}

class _SummarySheet extends StatefulWidget {
  final String roomId;
  final bool isGroup;

  const _SummarySheet({
    required this.roomId,
    required this.isGroup,
  });

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _loading = true;
  SummaryResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ChatSummaryService.summarize(
        roomId: widget.roomId,
        isGroup: widget.isGroup,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on SummaryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _copy() {
    if (_result?.summary == null) return;
    Clipboard.setData(ClipboardData(text: _result!.summary!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('요약을 복사했어요'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.25),
                          AppTheme.primary.withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'AI 요약',
                          style: TextStyle(
                            color: AppTheme.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _loading
                              ? '안 읽은 메시지를 정리하고 있어요'
                              : (_result != null && !_result!.isEmpty
                                  ? '안 읽은 메시지 ${_result!.messageCount}개 요약'
                                  : '안 읽은 메시지'),
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_loading &&
                      _result != null &&
                      !_result!.isEmpty)
                    IconButton(
                      icon: Icon(Icons.copy_rounded,
                          color: AppTheme.textSub, size: 18),
                      onPressed: _copy,
                      tooltip: '복사',
                    ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppTheme.textSub, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: AppTheme.border),

            // 본문
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoading();
    }

    if (_error != null) {
      return _buildError();
    }

    if (_result == null || _result!.isEmpty) {
      return _buildEmpty();
    }

    return _buildSummary();
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'GPT-4o가 대화를 정리 중...',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '잠시만 기다려주세요',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline,
              color: const Color(0xFFEF4444), size: 32),
          const SizedBox(height: 12),
          Text(
            '요약을 가져오지 못했어요',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('다시 시도'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          Text(
            '요약할 메시지가 충분하지 않아요',
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '안 읽은 메시지가 3개 이상일 때 요약할 수 있어요',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final lines = _result!.summary!
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withOpacity(0.10),
                AppTheme.primary.withOpacity(0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.asMap().entries.map((entry) {
              final i = entry.key;
              final line = entry.value;
              final isBullet =
                  line.startsWith('-') || line.startsWith('•');
              final clean = isBullet
                  ? line.replaceFirst(RegExp(r'^[-•]\s*'), '')
                  : line;

              return Padding(
                padding: EdgeInsets.only(
                    top: i == 0 ? 0 : 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7, right: 10),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        clean,
                        style: TextStyle(
                          color: AppTheme.textMain,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline,
                color: AppTheme.textMuted, size: 12),
            const SizedBox(width: 4),
            Text(
              _result!.cached
                  ? '캐시된 요약이에요'
                  : 'AI 요약이라 실제와 다를 수 있어요',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}