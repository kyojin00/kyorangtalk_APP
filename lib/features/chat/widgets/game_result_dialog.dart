import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 🎮 게임 결과 상세 다이얼로그
// ═══════════════════════════════════════════════════

Future<void> showGameResultDialog(
  BuildContext context,
  Map<String, dynamic> gameData,
) {
  return showDialog(
    context: context,
    builder: (_) => _GameResultDialog(gameData: gameData),
  );
}

class _GameResultDialog extends StatelessWidget {
  final Map<String, dynamic> gameData;

  const _GameResultDialog({required this.gameData});

  @override
  Widget build(BuildContext context) {
    final type = gameData['type'] as String?;

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
            _buildGameContent(type),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '닫기',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameContent(String? type) {
    switch (type) {
      case 'dice':
        return _buildDiceResult();
      case 'coin':
        return _buildCoinResult();
      case 'rps':
        return _buildRpsResult();
      case 'roulette':
        return _buildRouletteResult();
      default:
        return Text('알 수 없는 게임',
            style: TextStyle(color: AppTheme.textMain));
    }
  }

  // 🎲 주사위
  Widget _buildDiceResult() {
    final value = gameData['value'] as int? ?? 1;
    const diceFaces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎲', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              '주사위',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          diceFaces[value - 1],
          style: TextStyle(
            fontSize: 140,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // 🪙 동전
  Widget _buildCoinResult() {
    final value = gameData['value'] as String? ?? 'heads';
    final isHeads = value == 'heads';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🪙', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              '동전 던지기',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isHeads
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
                color: (isHeads
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF9CA3AF))
                    .withOpacity(0.4),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Text(
              isHeads ? '앞' : '뒤',
              style: const TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isHeads ? '앞면!' : '뒷면!',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color:
                isHeads ? const Color(0xFFF59E0B) : AppTheme.textMain,
          ),
        ),
      ],
    );
  }

  // ✂️ 가위바위보
  Widget _buildRpsResult() {
    final value = gameData['value'] as String? ?? 'rock';

    const rpsIcons = {
      'rock': '✊',
      'paper': '✋',
      'scissors': '✌️',
    };
    const rpsNames = {
      'rock': '바위',
      'paper': '보',
      'scissors': '가위',
    };
    const rpsColors = {
      'rock': Color(0xFFF472B6),
      'paper': Color(0xFF60A5FA),
      'scissors': Color(0xFFA78BFA),
    };

    final color = rpsColors[value] ?? AppTheme.primary;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('✂️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              '가위바위보',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              rpsIcons[value] ?? '?',
              style: const TextStyle(fontSize: 100),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          rpsNames[value] ?? '?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  // 🎡 룰렛
  Widget _buildRouletteResult() {
    final items = (gameData['items'] as List?)?.cast<String>() ?? [];
    final winner = gameData['winner'] as String? ?? '';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎡', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              '룰렛',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '후보 ${items.length}개',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items.map((item) {
                  final isWinner = item == winner;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isWinner
                          ? AppTheme.primary
                          : AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isWinner
                            ? AppTheme.primary
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 12,
                        color: isWinner
                            ? Colors.white
                            : AppTheme.textSub,
                        fontWeight: isWinner
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '🎉 당첨 🎉',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSub,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Text(
            winner,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}