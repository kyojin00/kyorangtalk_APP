import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/poll_provider.dart';

// ═══════════════════════════════════════════════════
// 📊 투표 만들기 다이얼로그
// ═══════════════════════════════════════════════════
// 
// 사용법:
// final pollId = await showCreatePollDialog(
//   context,
//   roomId: widget.room.roomId,
//   roomType: 'dm',  // or 'group'
// );
// 
// pollId가 있으면 투표가 성공적으로 생성됨
// ═══════════════════════════════════════════════════

Future<String?> showCreatePollDialog(
  BuildContext context, {
  required String roomId,
  required String roomType,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CreatePollSheet(
      roomId: roomId,
      roomType: roomType,
    ),
  );
}

class _CreatePollSheet extends StatefulWidget {
  final String roomId;
  final String roomType;

  const _CreatePollSheet({
    required this.roomId,
    required this.roomType,
  });

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _allowMultiple = false;
  bool _isAnonymous = false;
  int _durationIndex = 2;  // 기본: 24시간
  bool _creating = false;

  // 마감 시간 옵션
  static const _durationOptions = [
    {'label': '1시간', 'hours': 1},
    {'label': '12시간', 'hours': 12},
    {'label': '24시간', 'hours': 24},
    {'label': '3일', 'hours': 72},
    {'label': '1주일', 'hours': 168},
    {'label': '무기한', 'hours': 0},
  ];

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 10) {
      _showSnack('최대 10개까지 추가 가능해요');
      return;
    }
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      _showSnack('최소 2개는 필요해요');
      return;
    }
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _submit() async {
    // 검증
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      _showSnack('질문을 입력해주세요');
      return;
    }
    if (question.length > 100) {
      _showSnack('질문은 100자 이하로 입력해주세요');
      return;
    }

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (options.length < 2) {
      _showSnack('옵션을 2개 이상 입력해주세요');
      return;
    }

    // 중복 체크
    final uniqueOptions = options.toSet().toList();
    if (uniqueOptions.length != options.length) {
      _showSnack('중복된 옵션이 있어요');
      return;
    }

    setState(() => _creating = true);

    try {
      // 마감 시간
      final hours = _durationOptions[_durationIndex]['hours'] as int;
      final duration = hours > 0 ? Duration(hours: hours) : null;

      final pollId = await createPoll(
        roomId:        widget.roomId,
        roomType:      widget.roomType,
        question:      question,
        options:       options,
        allowMultiple: _allowMultiple,
        isAnonymous:   _isAnonymous,
        duration:      duration,
      );

      if (mounted) {
        Navigator.pop(context, pollId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        _showSnack('투표 생성 실패: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 키보드 높이에 따라 조정
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Text(
                      '📊 투표 만들기',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: AppTheme.textSub, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // 본문 (스크롤)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── 질문 ───
                      Text(
                        '질문',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _questionController,
                        maxLength: 100,
                        maxLines: 2,
                        style: TextStyle(
                            color: AppTheme.textMain, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: '예: 다음 주 모임 언제가 좋을까?',
                          hintStyle: TextStyle(
                              color: AppTheme.textMuted, fontSize: 14),
                          filled: true,
                          fillColor: AppTheme.bg,
                          counterStyle: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
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
                            borderSide: const BorderSide(
                                color: AppTheme.primary, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ─── 옵션 ───
                      Row(
                        children: [
                          Text(
                            '옵션',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSub,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${_optionControllers.length}/10)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 옵션 입력 필드들
                      ..._buildOptionFields(),

                      const SizedBox(height: 8),

                      // 옵션 추가 버튼
                      TextButton.icon(
                        onPressed: _optionControllers.length >= 10
                            ? null
                            : _addOption,
                        icon: const Icon(Icons.add_circle_outline,
                            size: 18, color: AppTheme.primary),
                        label: const Text(
                          '옵션 추가',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── 설정 ───
                      Text(
                        '설정',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 복수 선택
                      _buildToggleRow(
                        icon: Icons.check_box_outlined,
                        title: '복수 선택',
                        subtitle: '여러 옵션을 선택할 수 있어요',
                        value: _allowMultiple,
                        onChanged: (v) => setState(() => _allowMultiple = v),
                      ),
                      const SizedBox(height: 10),

                      // 익명 투표
                      _buildToggleRow(
                        icon: Icons.visibility_off_outlined,
                        title: '익명 투표',
                        subtitle: '누가 투표했는지 보이지 않아요',
                        value: _isAnonymous,
                        onChanged: (v) => setState(() => _isAnonymous = v),
                      ),
                      const SizedBox(height: 16),

                      // ─── 마감 ───
                      Text(
                        '마감',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSub,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          _durationOptions.length,
                          (i) => _buildDurationChip(i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 하단 버튼
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _creating
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '취소',
                          style: TextStyle(
                              color: AppTheme.textMain,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                '투표 만들기',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 위젯 빌더 헬퍼
  // ═══════════════════════════════════════════════

  List<Widget> _buildOptionFields() {
    return List.generate(_optionControllers.length, (i) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            // 번호 뱃지
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // 입력 필드
            Expanded(
              child: TextField(
                controller: _optionControllers[i],
                maxLength: 50,
                style: TextStyle(
                    color: AppTheme.textMain, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '옵션 ${i + 1}',
                  hintStyle: TextStyle(
                      color: AppTheme.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.bg,
                  isDense: true,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            // 삭제 버튼
            if (_optionControllers.length > 2)
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    color: AppTheme.textSub, size: 20),
                onPressed: () => _removeOption(i),
                padding: const EdgeInsets.only(left: 4),
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: value
              ? AppTheme.primary.withOpacity(0.08)
              : AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? AppTheme.primary.withOpacity(0.3)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: value ? AppTheme.primary : AppTheme.textSub,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip(int index) {
    final isSelected = _durationIndex == index;
    final label = _durationOptions[index]['label'] as String;

    return GestureDetector(
      onTap: () => setState(() => _durationIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary
              : AppTheme.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textMain,
          ),
        ),
      ),
    );
  }
}