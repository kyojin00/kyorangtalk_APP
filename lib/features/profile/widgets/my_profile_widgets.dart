import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════
// 🧩 MyProfileScreen 헬퍼 위젯들
// ⭐ BackdropFilter 제거 (Samsung/MediaTek 렌더 행 방지)
// ⭐ DraggableSticker:
//    - 일반 Container (크기 0 찌부 방지)
//    - 이모지 Text 에 color 미지정 (컬러 이모지 정상 렌더링)
//    - textDirection 명시
//    - behavior: opaque (빈 영역도 탭/드래그)
// ═══════════════════════════════════════════════════

// ───────────────────────────────────────────────────
// 기본 배경
// ───────────────────────────────────────────────────
class DefaultBackground extends StatelessWidget {
  const DefaultBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A1655),
            const Color(0xFF1E1B3A),
            const Color(0xFF0F0F1F),
            AppTheme.bg,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────
// 글래스 효과 원형 아이콘 버튼
// ───────────────────────────────────────────────────
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────
// 글래스 효과 텍스트 버튼
// ───────────────────────────────────────────────────
class GlassTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const GlassTextButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────
// 멀티 프로필 버튼
// ───────────────────────────────────────────────────
class MultiProfileButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const MultiProfileButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton(
          icon: Icons.theater_comedy_outlined,
          onTap: onTap,
        ),
        if (count > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withOpacity(0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.bg, width: 1.5),
              ),
              constraints:
                  const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────
// 필드 라벨
// ───────────────────────────────────────────────────
class FieldLabel extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final bool optional;

  const FieldLabel({
    super.key,
    required this.label,
    required this.count,
    required this.max,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '선택',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const Spacer(),
        Text(
          '$count',
          style: TextStyle(
            color: count > 0
                ? Colors.white.withOpacity(0.8)
                : Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          ' / $max',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────
// 글래스 효과 텍스트 필드
// ───────────────────────────────────────────────────
class GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.maxLines = 1,
    this.textInputAction,
    this.inputFormatters,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(_focused ? 0.55 : 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? AppTheme.primaryLight.withOpacity(0.7)
              : Colors.white.withOpacity(0.15),
          width: _focused ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          cursorColor: AppTheme.primaryLight,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1),
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontWeight: FontWeight.w500,
            ),
            counterText: '',
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────
// 드래그 가능한 스티커
// ───────────────────────────────────────────────────
class DraggableSticker extends StatefulWidget {
  final String emoji;
  final double initialX;
  final double initialY;
  final double scale;
  final bool editMode;
  final void Function(double x, double y) onPositionChanged;
  final VoidCallback? onTap;

  const DraggableSticker({
    super.key,
    required this.emoji,
    required this.initialX,
    required this.initialY,
    required this.scale,
    required this.editMode,
    required this.onPositionChanged,
    this.onTap,
  });

  @override
  State<DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<DraggableSticker> {
  late double _x;
  late double _y;

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;
  }

  @override
  void didUpdateWidget(DraggableSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialX != widget.initialX ||
        oldWidget.initialY != widget.initialY) {
      _x = widget.initialX;
      _y = widget.initialY;
    }
  }

  @override
  Widget build(BuildContext context) {
    double scale = widget.scale;
    if (!scale.isFinite || scale <= 0) scale = 1.0;
    final size = 60.0 * scale;

    final safeX = _x.isFinite ? _x : 0.0;
    final safeY = _y.isFinite ? _y : 0.0;

    return Positioned(
      left: safeX - size / 2,
      top: safeY - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanUpdate: widget.editMode
            ? (details) {
                setState(() {
                  _x += details.delta.dx;
                  _y += details.delta.dy;
                });
              }
            : null,
        onPanEnd: widget.editMode
            ? (_) => widget.onPositionChanged(_x, _y)
            : null,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: widget.editMode
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.primaryLight.withOpacity(0.7),
                      width: 2),
                )
              : null,
          child: Text(
            widget.emoji,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: size * 0.65),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────
// 이모지 리스트 상수
// ───────────────────────────────────────────────────
const List<String> kProfileEmojiList = [
  '❤️', '💖', '💕', '💗', '💓', '💝', '💘', '💞',
  '😀', '😁', '😂', '🤣', '😊', '😇', '🙂', '😉',
  '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛',
  '🤩', '🤗', '🤔', '🤨', '😎', '🥳', '🥺', '😢',
  '🌟', '✨', '💫', '⭐', '🌙', '☀️', '🌈', '🔥',
  '🍀', '🌸', '🌺', '🌷', '🌹', '🌻', '🌼', '💐',
  '🎀', '🎁', '🎂', '🎉', '🎊', '🎈', '🍰', '🍭',
  '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
  '👑', '💎', '💍', '👗', '👠', '🎩', '🕶️', '💄',
  '☕', '🍵', '🧃', '🍹', '🍸', '🥂', '🍷', '🍾',
];