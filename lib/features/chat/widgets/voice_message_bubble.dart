import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/audio_service.dart';

/// 음성 메시지 재생 버블
class VoiceMessageBubble extends StatefulWidget {
  final String messageId;
  final String audioUrl;
  final int duration;
  final bool isMe;

  const VoiceMessageBubble({
    super.key,
    required this.messageId,
    required this.audioUrl,
    required this.duration,
    required this.isMe,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  StreamSubscription<String?>? _playingSub;
  StreamSubscription<Duration>? _positionSub;

  bool _isPlaying = false;
  double _playSpeed = 1.0;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();

    final service = AudioPlayerService();
    _playingSub = service.playingStream.listen((playingId) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playingId == widget.messageId;
        if (!_isPlaying) {
          _position = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final service = AudioPlayerService();

    if (_isPlaying) {
      await service.pause();
      setState(() => _isPlaying = false);
    } else {
      await service.play(
        widget.messageId,
        widget.audioUrl,
        speed: _playSpeed,
      );

      _positionSub?.cancel();
      _positionSub = service.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
      });
    }
  }

  void _changeSpeed() async {
    setState(() {
      if (_playSpeed == 1.0) {
        _playSpeed = 1.5;
      } else if (_playSpeed == 1.5) {
        _playSpeed = 2.0;
      } else {
        _playSpeed = 1.0;
      }
    });

    if (_isPlaying) {
      await AudioPlayerService().setSpeed(_playSpeed);
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress {
    if (widget.duration == 0) return 0;
    final pos = _position.inSeconds;
    final total = widget.duration;
    return (pos / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMe ? AppTheme.primary : AppTheme.border;
    final iconColor = widget.isMe ? Colors.white : AppTheme.primary;
    final textColor = widget.isMe ? Colors.white : AppTheme.textMain;
    final progressColor =
        widget.isMe ? Colors.white : AppTheme.primary;
    final progressBgColor = widget.isMe
        ? Colors.white.withOpacity(0.3)
        : AppTheme.textMuted.withOpacity(0.3);

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withOpacity(0.2)
                    : AppTheme.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: iconColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 24,
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      _buildWaveform(progressBgColor, 1.0),
                      if (_progress > 0)
                        ClipRect(
                          clipper: _ProgressClipper(_progress),
                          child: _buildWaveform(progressColor, 1.0),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatDuration(_isPlaying
                          ? _position.inSeconds
                          : widget.duration),
                      style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _changeSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.isMe
                              ? Colors.white.withOpacity(0.2)
                              : AppTheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_playSpeed}x',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(Color color, double opacity) {
    final heights = [
      0.3, 0.5, 0.7, 0.9, 0.6, 0.4, 0.8, 1.0, 0.7, 0.5,
      0.3, 0.6, 0.9, 0.7, 0.4, 0.8, 0.6, 0.3, 0.5, 0.4,
      0.7, 0.9, 0.5, 0.3, 0.6, 0.8, 0.4, 0.7, 0.5, 0.3,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(heights.length, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            width: 2.5,
            height: 20 * heights[index],
            decoration: BoxDecoration(
              color: color.withOpacity(opacity),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        );
      }),
    );
  }
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;

  _ProgressClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_ProgressClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}