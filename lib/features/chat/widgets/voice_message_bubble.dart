import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/audio_service.dart';
import '../services/subscription_service.dart';
import '../services/transcribe_service.dart';
import 'pro_upgrade_modal.dart';

/// 음성 메시지 재생 버블 + STT 토글
class VoiceMessageBubble extends StatefulWidget {
  final String messageId;
  final String audioUrl;
  final int duration;
  final bool isMe;

  final bool isGroup;
  final String? initialTranscript;
  final String? initialStatus;

  const VoiceMessageBubble({
    super.key,
    required this.messageId,
    required this.audioUrl,
    required this.duration,
    required this.isMe,
    this.isGroup = false,
    this.initialTranscript,
    this.initialStatus,
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

  bool _showTranscript = false;
  bool _isTranscribing = false;
  String? _transcript;
  String? _transcriptError;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    _transcript = widget.initialTranscript;

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
  void didUpdateWidget(covariant VoiceMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTranscript != oldWidget.initialTranscript &&
        widget.initialTranscript != null) {
      setState(() {
        _transcript = widget.initialTranscript;
        _isTranscribing = false;
        _transcriptError = null;
      });
      _pollingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _pollingTimer?.cancel();
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

  // ═══════════════════════════════════════════════════
  // STT 토글 (⭐ 사용량 가드 추가)
  // ═══════════════════════════════════════════════════
  Future<void> _toggleTranscript() async {
    // 이미 변환된 경우: 표시 토글만 (캐시 hit이라 카운트 X)
    if (_transcript != null && _transcript!.isNotEmpty) {
      setState(() => _showTranscript = !_showTranscript);
      return;
    }

    // ⭐ 변환 시작 전 사용량 체크 (캐시 없는 신규 변환만)
    final ok = await ensureUsageAllowed(context, AiFeature.stt);
    if (!ok) return;

    setState(() {
      _showTranscript = true;
      _isTranscribing = true;
      _transcriptError = null;
    });

    try {
      final result = await TranscribeService.transcribe(
        messageId: widget.messageId,
        isGroup: widget.isGroup,
      );

      if (!mounted) return;
      setState(() {
        _transcript = result;
        _isTranscribing = false;
      });
    } on TranscribeException catch (e) {
      if (!mounted) return;

      // ⭐ 한도 초과 처리
      if (e.isQuotaExceeded) {
        setState(() {
          _isTranscribing = false;
          _showTranscript = false;
        });
        if (context.mounted) {
          await showProUpgradeModal(context, feature: AiFeature.stt);
        }
        return;
      }

      // 이미 진행 중 → polling
      if (e.isProcessing) {
        _startPolling();
        return;
      }

      setState(() {
        _isTranscribing = false;
        _transcriptError = e.message;
      });
    } catch (e) {
      if (!mounted) return;

      // ⭐ 일반 catch에서도 quota 체크
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('quota_exceeded') || errStr.contains('429')) {
        setState(() {
          _isTranscribing = false;
          _showTranscript = false;
        });
        if (context.mounted) {
          await showProUpgradeModal(context, feature: AiFeature.stt);
        }
        return;
      }

      setState(() {
        _isTranscribing = false;
        _transcriptError = '변환 실패';
      });
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    int attempts = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      attempts++;
      if (attempts > 15) {
        t.cancel();
        if (mounted) {
          setState(() {
            _isTranscribing = false;
            _transcriptError = '변환 시간이 너무 오래 걸려요';
          });
        }
        return;
      }

      final status = await TranscribeService.fetchStatus(
        messageId: widget.messageId,
        isGroup: widget.isGroup,
      );

      if (status == null) return;

      if (status['status'] == 'done' && status['transcript'] != null) {
        t.cancel();
        if (mounted) {
          setState(() {
            _transcript = status['transcript'] as String;
            _isTranscribing = false;
          });
        }
      } else if (status['status'] == 'failed') {
        t.cancel();
        if (mounted) {
          setState(() {
            _isTranscribing = false;
            _transcriptError = '변환 실패';
          });
        }
      }
    });
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
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

              const SizedBox(height: 8),
              Container(
                height: 1,
                color: widget.isMe
                    ? Colors.white.withOpacity(0.18)
                    : AppTheme.textMuted.withOpacity(0.2),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: _isTranscribing ? null : _toggleTranscript,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isTranscribing)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              textColor.withOpacity(0.8),
                            ),
                          ),
                        )
                      else
                        Icon(
                          _showTranscript &&
                                  _transcript != null &&
                                  _transcript!.isNotEmpty
                              ? Icons.keyboard_arrow_up
                              : Icons.text_fields_rounded,
                          color: textColor.withOpacity(0.85),
                          size: 14,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _isTranscribing
                            ? '변환 중...'
                            : (_transcript != null &&
                                    _transcript!.isNotEmpty
                                ? (_showTranscript
                                    ? '텍스트 숨기기'
                                    : '텍스트로 보기')
                                : '텍스트로 변환'),
                        style: TextStyle(
                          color: textColor.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_showTranscript &&
            (_transcript != null || _transcriptError != null))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: _transcriptError != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFEF4444), size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _transcriptError!,
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  color: AppTheme.primary, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'AI 변환',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _transcript!,
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
      ],
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