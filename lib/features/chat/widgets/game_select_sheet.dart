import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════
// 🎮 게임 선택 + 실행 시트
// ═══════════════════════════════════════════════

Future<Map<String, dynamic>?> showGameSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _GameSelectSheet(),
  );
}

class _GameSelectSheet extends StatelessWidget {
  const _GameSelectSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                '🎮 미니게임',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '채팅방에서 재미있는 게임을 즐겨보세요',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSub,
                ),
              ),
              const SizedBox(height: 24),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _GameCard(
                    emoji: '🎲',
                    title: '주사위',
                    subtitle: '1부터 6까지',
                    color: const Color(0xFFF472B6),
                    onTap: () async {
                      final result = await _rollDice(context);
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                  _GameCard(
                    emoji: '🪙',
                    title: '동전',
                    subtitle: '앞면 or 뒷면',
                    color: const Color(0xFFFBBF24),
                    onTap: () async {
                      final result = await _flipCoin(context);
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                  _GameCard(
                    emoji: '✂️',
                    title: '가위바위보',
                    subtitle: '운에 맡겨요',
                    color: const Color(0xFF60A5FA),
                    onTap: () async {
                      final result = await _playRps(context);
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                  _GameCard(
                    emoji: '🎡',
                    title: '룰렛',
                    subtitle: '항목 중 하나',
                    color: const Color(0xFFA78BFA),
                    onTap: () async {
                      final result = await _spinRoulette(context);
                      if (result != null && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> _rollDice(BuildContext context) async {
    final value = Random().nextInt(6) + 1;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DiceAnimation(finalValue: value),
    );

    return {
      'type': 'dice',
      'value': value,
    };
  }

  static Future<Map<String, dynamic>?> _flipCoin(BuildContext context) async {
    final isHeads = Random().nextBool();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CoinAnimation(isHeads: isHeads),
    );

    return {
      'type': 'coin',
      'value': isHeads ? 'heads' : 'tails',
    };
  }

  static Future<Map<String, dynamic>?> _playRps(BuildContext context) async {
    final choices = ['rock', 'paper', 'scissors'];
    final value = choices[Random().nextInt(3)];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RpsAnimation(finalValue: value),
    );

    return {
      'type': 'rps',
      'value': value,
    };
  }

  static Future<Map<String, dynamic>?> _spinRoulette(BuildContext context) async {
    final items = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _RouletteInputDialog(),
    );

    if (items == null || items.isEmpty) return null;

    final winner = items[Random().nextInt(items.length)];

    if (!context.mounted) return null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RouletteAnimation(items: items, winner: winner),
    );

    return {
      'type': 'roulette',
      'items': items,
      'winner': winner,
    };
  }
}

class _GameCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                )),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSub,
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 🎲 주사위 애니메이션
// ═══════════════════════════════════════════════
class _DiceAnimation extends StatefulWidget {
  final int finalValue;
  const _DiceAnimation({required this.finalValue});

  @override
  State<_DiceAnimation> createState() => _DiceAnimationState();
}

class _DiceAnimationState extends State<_DiceAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentValue = 1;
  bool _finished = false;

  static const _diceFaces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _controller.addListener(() {
      if (_controller.value < 0.9) {
        setState(() {
          _currentValue = Random().nextInt(6) + 1;
        });
      } else if (!_finished) {
        setState(() {
          _currentValue = widget.finalValue;
          _finished = true;
        });
      }
    });

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _finished ? '결과!' : '🎲 굴리는 중...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedRotation(
              turns: _finished ? 0 : _controller.value * 4,
              duration: const Duration(milliseconds: 100),
              child: Text(
                _diceFaces[_currentValue - 1],
                style: TextStyle(
                  fontSize: 100,
                  color: _finished
                      ? AppTheme.primary
                      : AppTheme.textMain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_finished)
              Text(
                '$_currentValue',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 🪙 동전 애니메이션 (⭐ 수정! 뒤집히면서 앞/뒤 계속 바뀜)
// ═══════════════════════════════════════════════
class _CoinAnimation extends StatefulWidget {
  final bool isHeads;
  const _CoinAnimation({required this.isHeads});

  @override
  State<_CoinAnimation> createState() => _CoinAnimationState();
}

class _CoinAnimationState extends State<_CoinAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _finished = false;
  // ✨ 현재 보이는 면 (애니메이션 중 계속 바뀜)
  bool _showingHeads = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ✨ 회전하면서 앞/뒤 전환 감지
    _controller.addListener(() {
      if (_finished) return;
      
      // 회전 각도 기반으로 앞/뒤 결정
      // 0~0.25: 앞, 0.25~0.75: 뒤, 0.75~1: 앞 (이런 식으로 반복)
      final rotations = _controller.value * 6;  // 6번 회전
      final faceIndex = (rotations * 2).floor() % 2;
      final newShowing = faceIndex == 0;
      
      if (newShowing != _showingHeads) {
        setState(() => _showingHeads = newShowing);
      }
    });

    _controller.forward().then((_) {
      setState(() {
        _finished = true;
        _showingHeads = widget.isHeads;  // ⭐ 끝나면 진짜 결과로!
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) Navigator.pop(context);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _finished ? '결과!' : '🪙 던지는 중...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                // ✨ Y축 회전 애니메이션
                final rotateY = _finished 
                    ? 0.0 
                    : _controller.value * pi * 12;  // 6번 회전
                
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(rotateY),
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _showingHeads
                            ? [
                                const Color(0xFFFEF3C7),
                                const Color(0xFFFBBF24),
                                const Color(0xFFF59E0B),
                              ]
                            : [
                                const Color(0xFFE5E7EB),
                                const Color(0xFF9CA3AF),
                                const Color(0xFF6B7280),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        // ⭐ 애니메이션 중에는 현재 보이는 면 표시
                        _showingHeads ? '앞' : '뒤',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            if (_finished)
              Text(
                widget.isHeads ? '앞면!' : '뒷면!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: widget.isHeads
                      ? const Color(0xFFF59E0B)
                      : AppTheme.textMain,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// ✂️ 가위바위보 애니메이션
// ═══════════════════════════════════════════════
class _RpsAnimation extends StatefulWidget {
  final String finalValue;
  const _RpsAnimation({required this.finalValue});

  @override
  State<_RpsAnimation> createState() => _RpsAnimationState();
}

class _RpsAnimationState extends State<_RpsAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _current = 'rock';
  bool _finished = false;

  static const _rpsIcons = {
    'rock': '✊',
    'paper': '✋',
    'scissors': '✌️',
  };
  static const _rpsNames = {
    'rock': '바위',
    'paper': '보',
    'scissors': '가위',
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final choices = ['rock', 'paper', 'scissors'];
    _controller.addListener(() {
      if (_controller.value < 0.85) {
        setState(() {
          _current = choices[Random().nextInt(3)];
        });
      } else if (!_finished) {
        setState(() {
          _current = widget.finalValue;
          _finished = true;
        });
      }
    });

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _finished ? '결과!' : '가위바위보!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _rpsIcons[_current]!,
              style: const TextStyle(fontSize: 100),
            ),
            const SizedBox(height: 16),
            if (_finished)
              Text(
                _rpsNames[_current]!,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 🎡 룰렛: 항목 입력 다이얼로그
// ═══════════════════════════════════════════════
class _RouletteInputDialog extends StatefulWidget {
  const _RouletteInputDialog();

  @override
  State<_RouletteInputDialog> createState() => _RouletteInputDialogState();
}

class _RouletteInputDialogState extends State<_RouletteInputDialog> {
  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  void _addItem() {
    if (_controllers.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 8개까지 추가 가능해요')),
      );
      return;
    }
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeItem(int index) {
    if (_controllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 2개는 필요해요')),
      );
      return;
    }
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
  }

  void _spin() {
    final items = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 2개의 항목을 입력해주세요')),
      );
      return;
    }

    Navigator.pop(context, items);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎡', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  '룰렛 항목 입력',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '선택할 항목 2~8개를 입력하세요',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSub,
              ),
            ),
            const SizedBox(height: 16),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _controllers.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
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
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _controllers[i],
                          style: TextStyle(color: AppTheme.textMain),
                          maxLength: 15,
                          decoration: InputDecoration(
                            hintText: '항목 ${i + 1}',
                            hintStyle: TextStyle(color: AppTheme.textMuted),
                            isDense: true,
                            counterText: '',
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: AppTheme.primary),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color: AppTheme.textSub, size: 20),
                        onPressed: () => _removeItem(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, color: AppTheme.primary, size: 18),
              label: Text(
                '항목 추가 (${_controllers.length}/8)',
                style: const TextStyle(color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('취소',
                        style: TextStyle(color: AppTheme.textMain)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _spin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('🎡 룰렛 돌리기',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 🎡 룰렛 애니메이션
// ═══════════════════════════════════════════════
class _RouletteAnimation extends StatefulWidget {
  final List<String> items;
  final String winner;

  const _RouletteAnimation({
    required this.items,
    required this.winner,
  });

  @override
  State<_RouletteAnimation> createState() => _RouletteAnimationState();
}

class _RouletteAnimationState extends State<_RouletteAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentIndex = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    final winnerIndex = widget.items.indexOf(widget.winner);

    _controller.addListener(() {
      final progress = _controller.value;
      
      if (progress < 0.85) {
        final newIdx = (DateTime.now().millisecondsSinceEpoch / 
            (100 + (progress * 300)).round()).floor() % widget.items.length;
        if (newIdx != _currentIndex) {
          setState(() => _currentIndex = newIdx);
        }
      } else if (!_finished) {
        setState(() {
          _currentIndex = winnerIndex;
          _finished = true;
        });
      }
    });

    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.pop(context);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _finished ? '🎉 당첨!' : '🎡 룰렛 중...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                gradient: _finished
                    ? const LinearGradient(
                        colors: [
                          Color(0xFFA78BFA),
                          Color(0xFF7C3AED),
                        ],
                      )
                    : null,
                color: _finished ? null : AppTheme.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _finished
                      ? AppTheme.primary
                      : AppTheme.border,
                  width: 2,
                ),
                boxShadow: _finished
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                widget.items[_currentIndex],
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _finished ? Colors.white : AppTheme.textMain,
                ),
              ),
            ),
            if (_finished) ...[
              const SizedBox(height: 16),
              Text(
                '선택 완료!',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSub,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}