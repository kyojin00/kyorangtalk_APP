import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/smart_reply_service.dart';
import '../services/subscription_service.dart';
import 'pro_upgrade_modal.dart';

/// ═══════════════════════════════════════════════════
/// 입력창 위에 표시되는 답장 후보 칩 모음
///
/// - 자동 트리거 조건은 호출부(채팅방 화면)에서 판단
/// - 이 위젯은 단순히: 메시지 ID + 본문 + 보낸이 받아서 → 후보 fetch → 표시
/// - 칩 탭 → onSelected 콜백
/// - X 버튼 → onDismiss 콜백
/// - 한도 초과 시 → 자동 dismiss (배너 자체가 안 보임)
/// ═══════════════════════════════════════════════════
class SmartReplyBar extends StatefulWidget {
  final String roomId;
  final bool isGroup;
  final String lastMessageId;
  final String lastMessageText;
  final String senderName;
  final List<String> contextMessages;
  final void Function(String text) onSelected;
  final VoidCallback onDismiss;

  const SmartReplyBar({
    super.key,
    required this.roomId,
    required this.isGroup,
    required this.lastMessageId,
    required this.lastMessageText,
    required this.senderName,
    required this.contextMessages,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<SmartReplyBar> createState() => _SmartReplyBarState();
}

class _SmartReplyBarState extends State<SmartReplyBar> {
  bool _loading = true;
  List<SmartReplySuggestion> _suggestions = [];
  bool _quotaExceeded = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant SmartReplyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastMessageId != oldWidget.lastMessageId) {
      setState(() {
        _loading = true;
        _suggestions = [];
        _quotaExceeded = false;
      });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final result = await SmartReplyService.generate(
      roomId: widget.roomId,
      isGroup: widget.isGroup,
      lastMessageId: widget.lastMessageId,
      lastMessageText: widget.lastMessageText,
      senderName: widget.senderName,
      context: widget.contextMessages,
    );

    if (!mounted) return;

    // ⭐ 한도 초과: 배너 안 보이게 + 부모에게 dismiss 알림
    // (자동 트리거라 모달은 띄우지 않음 - 자연스럽게 사라지게)
    if (result.isQuotaExceeded) {
      setState(() {
        _loading = false;
        _quotaExceeded = true;
      });
      // 부모에게도 알림 (Smart Reply 자동 닫기)
      widget.onDismiss();
      return;
    }

    setState(() {
      _loading = false;
      _suggestions = result.suggestions;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ 한도 초과면 아무것도 표시 X (사용자 경험 보호)
    if (_quotaExceeded) return const SizedBox.shrink();

    if (_loading) {
      return _buildLoading();
    }

    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildBar();
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '답장 후보 만드는 중...',
              style: TextStyle(
                color: AppTheme.textSub,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: AppTheme.primary, size: 12),
                const SizedBox(width: 4),
                Text(
                  '답장 후보',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        color: AppTheme.textSub, size: 14),
                  ),
                ),
              ],
            ),
          ),

          // 가로 스크롤 칩들
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _suggestions.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SuggestionChip(
                    suggestion: s,
                    onTap: () => widget.onSelected(s.text),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final SmartReplySuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.suggestion,
    required this.onTap,
  });

  Color _labelColor() {
    switch (suggestion.label) {
      case '공감하기':
        return const Color(0xFF8B5CF6); // 보라
      case '위로하기':
        return const Color(0xFFF472A0); // 핑크
      case '가볍게':
        return const Color(0xFF06B6D4); // 청록
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _labelColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                suggestion.text,
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 12.5,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}