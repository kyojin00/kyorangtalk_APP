import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// 생일 선택 다이얼로그 표시
Future<DateTime?> showBirthdayPicker({
  required BuildContext context,
  DateTime? initialDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => BirthdayPickerSheet(initialDate: initialDate),
  );
}

class BirthdayPickerSheet extends StatefulWidget {
  final DateTime? initialDate;

  const BirthdayPickerSheet({super.key, this.initialDate});

  @override
  State<BirthdayPickerSheet> createState() => _BirthdayPickerSheetState();
}

class _BirthdayPickerSheetState extends State<BirthdayPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  final _yearController = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController = TextEditingController();

  late FixedExtentScrollController _yearScrollController;
  late FixedExtentScrollController _monthScrollController;
  late FixedExtentScrollController _dayScrollController;

  final int _minYear = 1920;
  final int _maxYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final init = widget.initialDate ?? DateTime(2000, 1, 1);
    _selectedYear = init.year;
    _selectedMonth = init.month;
    _selectedDay = init.day;

    _yearController.text = _selectedYear.toString();
    _monthController.text = _selectedMonth.toString().padLeft(2, '0');
    _dayController.text = _selectedDay.toString().padLeft(2, '0');

    _yearScrollController = FixedExtentScrollController(
        initialItem: _selectedYear - _minYear);
    _monthScrollController =
        FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _dayScrollController =
        FixedExtentScrollController(initialItem: _selectedDay - 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _yearScrollController.dispose();
    _monthScrollController.dispose();
    _dayScrollController.dispose();
    super.dispose();
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  void _syncFromTyping() {
    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);
    final day = int.tryParse(_dayController.text);

    if (year != null &&
        year >= _minYear &&
        year <= _maxYear &&
        month != null &&
        month >= 1 &&
        month <= 12 &&
        day != null &&
        day >= 1 &&
        day <= _daysInMonth(year, month)) {
      setState(() {
        _selectedYear = year;
        _selectedMonth = month;
        _selectedDay = day;
      });
    }
  }

  void _syncToTyping() {
    _yearController.text = _selectedYear.toString();
    _monthController.text = _selectedMonth.toString().padLeft(2, '0');
    _dayController.text = _selectedDay.toString().padLeft(2, '0');
  }

  bool get _isValid {
    if (_selectedYear < _minYear || _selectedYear > _maxYear) return false;
    if (_selectedMonth < 1 || _selectedMonth > 12) return false;
    final maxDay = _daysInMonth(_selectedYear, _selectedMonth);
    if (_selectedDay < 1 || _selectedDay > maxDay) return false;

    final picked = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    if (picked.isAfter(DateTime.now())) return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  Icon(Icons.cake_outlined,
                      color: AppTheme.primary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    '생일 선택',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isValid
                          ? AppTheme.primary.withOpacity(0.15)
                          : AppTheme.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _isValid
                          ? '${_selectedYear}.${_selectedMonth.toString().padLeft(2, '0')}.${_selectedDay.toString().padLeft(2, '0')}'
                          : '유효하지 않음',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isValid
                            ? AppTheme.primary
                            : AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    if (index == 0) {
                      _syncToTyping();
                    } else {
                      _syncFromTyping();
                      _yearScrollController
                          .jumpToItem(_selectedYear - _minYear);
                      _monthScrollController
                          .jumpToItem(_selectedMonth - 1);
                      _dayScrollController
                          .jumpToItem(_selectedDay - 1);
                    }
                  },
                  indicator: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSub,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.keyboard, size: 16),
                          SizedBox(width: 6),
                          Text('직접 입력'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swipe_vertical, size: 16),
                          SizedBox(width: 6),
                          Text('휠 선택'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              height: 260,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTypingTab(),
                  _buildWheelTab(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Center(
                            child: Text(
                              '취소',
                              style: TextStyle(
                                color: AppTheme.textMain,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _isValid
                            ? LinearGradient(
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primaryLight,
                                ],
                              )
                            : null,
                        color: _isValid ? null : AppTheme.border,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _isValid
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary
                                      .withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isValid
                              ? () {
                                  Navigator.pop(
                                      context,
                                      DateTime(_selectedYear,
                                          _selectedMonth, _selectedDay));
                                }
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: Center(
                            child: Text(
                              '확인',
                              style: TextStyle(
                                color: _isValid
                                    ? Colors.white
                                    : AppTheme.textSub,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
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

  Widget _buildTypingTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '숫자로 직접 입력하세요',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMain,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: _buildTypingField(
                  label: '년',
                  controller: _yearController,
                  hint: '2000',
                  maxLength: 4,
                  onChanged: (v) => _syncFromTyping(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildTypingField(
                  label: '월',
                  controller: _monthController,
                  hint: '01',
                  maxLength: 2,
                  onChanged: (v) => _syncFromTyping(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildTypingField(
                  label: '일',
                  controller: _dayController,
                  hint: '15',
                  maxLength: 2,
                  onChanged: (v) => _syncFromTyping(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '예: 2000년 1월 15일',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSub,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: maxLength,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(maxLength),
            ],
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildWheelTab() {
    final daysInMonth = _daysInMonth(_selectedYear, _selectedMonth);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        children: [
          Center(
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.3),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildWheelPicker(
                  controller: _yearScrollController,
                  itemCount: _maxYear - _minYear + 1,
                  onChanged: (index) {
                    setState(() {
                      _selectedYear = _minYear + index;
                      final maxDay = _daysInMonth(
                          _selectedYear, _selectedMonth);
                      if (_selectedDay > maxDay) {
                        _selectedDay = maxDay;
                        _dayScrollController.jumpToItem(maxDay - 1);
                      }
                    });
                  },
                  itemBuilder: (index) {
                    final year = _minYear + index;
                    final isSelected = year == _selectedYear;
                    return Center(
                      child: Text(
                        '$year',
                        style: TextStyle(
                          fontSize: isSelected ? 20 : 16,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSub,
                        ),
                      ),
                    );
                  },
                  suffix: '년',
                ),
              ),
              Expanded(
                flex: 2,
                child: _buildWheelPicker(
                  controller: _monthScrollController,
                  itemCount: 12,
                  onChanged: (index) {
                    setState(() {
                      _selectedMonth = index + 1;
                      final maxDay = _daysInMonth(
                          _selectedYear, _selectedMonth);
                      if (_selectedDay > maxDay) {
                        _selectedDay = maxDay;
                        _dayScrollController.jumpToItem(maxDay - 1);
                      }
                    });
                  },
                  itemBuilder: (index) {
                    final month = index + 1;
                    final isSelected = month == _selectedMonth;
                    return Center(
                      child: Text(
                        '$month',
                        style: TextStyle(
                          fontSize: isSelected ? 20 : 16,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSub,
                        ),
                      ),
                    );
                  },
                  suffix: '월',
                ),
              ),
              Expanded(
                flex: 2,
                child: _buildWheelPicker(
                  controller: _dayScrollController,
                  itemCount: daysInMonth,
                  onChanged: (index) {
                    setState(() {
                      _selectedDay = index + 1;
                    });
                  },
                  itemBuilder: (index) {
                    final day = index + 1;
                    final isSelected = day == _selectedDay;
                    return Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: isSelected ? 20 : 16,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSub,
                        ),
                      ),
                    );
                  },
                  suffix: '일',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheelPicker({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Function(int) onChanged,
    required Widget Function(int) itemBuilder,
    required String suffix,
  }) {
    return Stack(
      children: [
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 44,
          perspective: 0.003,
          diameterRatio: 1.5,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) => itemBuilder(index),
          ),
        ),
        Positioned(
          right: 4, top: 0, bottom: 0,
          child: Center(
            child: Text(
              suffix,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}