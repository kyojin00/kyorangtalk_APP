import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'game_result_dialog.dart';

// ═══════════════════════════════════════════════════
// 🎮 게임 메시지 버블 (DM + 그룹 공통)
// ═══════════════════════════════════════════════════
//
// 사용법:
// GameBubble(
//   gameData: msg.gameData!,
//   isMe: isMe,
//   content: msg.content,
// )
//
// 지원 게임:
// - dice     : 🎲 주사위
// - coin     : 🪙 동전
// - rps      : ✂️ 가위바위보
// - roulette : 🎡 룰렛
// ═══════════════════════════════════════════════════

class GameBubble extends StatelessWidget {
  final Map<String, dynamic> gameData;
  final bool isMe;
  final String content;

  const GameBubble({
    super.key,
    required this.gameData,
    required this.isMe,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final type = gameData['type'] as String?;
    
    return GestureDetector(
      onTap: () => showGameResultDialog(context, gameData),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isMe
                ? [const Color(0xFFA78BFA), AppTheme.primary]
                : [const Color(0xFF2D2D3E), const Color(0xFF1E1B3A)],
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: Border.all(
            color: isMe
                ? Colors.white.withOpacity(0.3)
                : AppTheme.primary.withOpacity(0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 게임 이름 헤더
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getEmoji(type),
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(
                  _getName(type),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isMe ? Colors.white : AppTheme.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 게임별 프리뷰
            _buildPreview(type),

            const SizedBox(height: 10),

            // 탭하여 자세히
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 11,
                    color: isMe
                        ? Colors.white.withOpacity(0.7)
                        : AppTheme.textSub),
                const SizedBox(width: 3),
                Text(
                  '탭하여 자세히',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withOpacity(0.7)
                        : AppTheme.textSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getEmoji(String? type) {
    switch (type) {
      case 'dice':     return '🎲';
      case 'coin':     return '🪙';
      case 'rps':      return '✂️';
      case 'roulette': return '🎡';
      default:         return '🎮';
    }
  }

  String _getName(String? type) {
    switch (type) {
      case 'dice':     return '주사위';
      case 'coin':     return '동전';
      case 'rps':      return '가위바위보';
      case 'roulette': return '룰렛';
      default:         return '게임';
    }
  }

  Widget _buildPreview(String? type) {
    switch (type) {
      case 'dice':
        return _buildDicePreview();
      case 'coin':
        return _buildCoinPreview();
      case 'rps':
        return _buildRpsPreview();
      case 'roulette':
        return _buildRoulettePreview();
      default:
        return Text(
          content,
          style: TextStyle(
            fontSize: 14,
            color: isMe ? Colors.white : AppTheme.textMain,
          ),
        );
    }
  }

  // ═══════════════════════════════════════════════
  // 🎲 주사위 프리뷰
  // ═══════════════════════════════════════════════
  Widget _buildDicePreview() {
    final value = gameData['value'] as int? ?? 1;
    const diceFaces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

    return Column(
      children: [
        Text(
          diceFaces[value - 1],
          style: TextStyle(
            fontSize: 44,
            color: isMe ? Colors.white : AppTheme.primaryLight,
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isMe ? Colors.white : AppTheme.textMain,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  // 🪙 동전 프리뷰
  // ═══════════════════════════════════════════════
  Widget _buildCoinPreview() {
    final value = gameData['value'] as String? ?? 'heads';
    final isHeads = value == 'heads';

    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isHeads
              ? [const Color(0xFFFBBF24), const Color(0xFFF59E0B)]
              : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
        ),
      ),
      child: Center(
        child: Text(
          isHeads ? '앞' : '뒤',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // ✂️ 가위바위보 프리뷰
  // ═══════════════════════════════════════════════
  Widget _buildRpsPreview() {
    final value = gameData['value'] as String? ?? 'rock';
    const rpsIcons = {'rock': '✊', 'paper': '✋', 'scissors': '✌️'};
    const rpsNames = {'rock': '바위', 'paper': '보', 'scissors': '가위'};

    return Column(
      children: [
        Text(
          rpsIcons[value] ?? '?',
          style: const TextStyle(fontSize: 48),
        ),
        Text(
          rpsNames[value] ?? '?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isMe ? Colors.white : AppTheme.textMain,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  // 🎡 룰렛 프리뷰
  // ═══════════════════════════════════════════════
  Widget _buildRoulettePreview() {
    final winner = gameData['winner'] as String? ?? '';
    final items = (gameData['items'] as List?)?.cast<String>() ?? [];

    return Column(
      children: [
        Text(
          '후보 ${items.length}개 중',
          style: TextStyle(
            fontSize: 11,
            color: isMe
                ? Colors.white.withOpacity(0.8)
                : AppTheme.textSub,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.25)
                : AppTheme.primary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isMe
                  ? Colors.white.withOpacity(0.4)
                  : AppTheme.primary,
            ),
          ),
          child: Text(
            '🎉 $winner',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isMe
                  ? Colors.white
                  : AppTheme.primaryLight,
            ),
          ),
        ),
      ],
    );
  }
}