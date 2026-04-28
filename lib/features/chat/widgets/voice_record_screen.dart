import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../../../core/theme/app_theme.dart';
import '../services/audio_service.dart';

/// 음성 녹음 화면 (BottomSheet)
Future<({String path, int duration})?> showVoiceRecordSheet(
    BuildContext context) async {
  return await showModalBottomSheet<({String path, int duration})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const VoiceRecordScreen(),
  );
}

class VoiceRecordScreen extends StatefulWidget {
  const VoiceRecordScreen({super.key});

  @override
  State<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends State<VoiceRecordScreen>
    with TickerProviderStateMixin {
  final _recordService = AudioRecordService();
  final _playerService = AudioPlayerService();

  // 상태
  bool _isInitializing = true;
  bool _hasPermission = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isFinished = false;
  bool _isPlayingPreview = false;

  String? _recordedPath;
  int _recordedDuration = 0;

  // 타이머 & 파형
  Timer? _timer;
  int _seconds = 0;
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<String?>? _playingSub;
  final List<double> _waveformData = [];

  // 애니메이션
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _init();

    _playingSub = _playerService.playingStream.listen((id) {
      if (!mounted) return;
      setState(() {
        _isPlayingPreview = id == 'preview';
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _playingSub?.cancel();
    _pulseController.dispose();
    _playerService.stop();
    super.dispose();
  }

  Future<void> _init() async {
    final started = await _recordService.start();
    if (!mounted) return;

    setState(() {
      _hasPermission = started;
      _isInitializing = false;
      _isRecording = started;
    });

    if (started) {
      _startTimer();
      _listenAmplitude();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _seconds = _recordService.currentDuration;
      });
    });
  }

  void _listenAmplitude() {
    _amplitudeSub?.cancel();
    _amplitudeSub = _recordService.amplitudeStream.listen((amp) {
      if (!mounted) return;
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      setState(() {
        _waveformData.add(normalized);
        if (_waveformData.length > 50) {
          _waveformData.removeAt(0);
        }
      });
    });
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      await _recordService.resume();
      _startTimer();
      _listenAmplitude();
      setState(() => _isPaused = false);
    } else {
      await _recordService.pause();
      _timer?.cancel();
      _amplitudeSub?.cancel();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _finishRecording() async {
    _timer?.cancel();
    _amplitudeSub?.cancel();

    final result = await _recordService.stop();
    if (result == null) return;

    if (!mounted) return;
    setState(() {
      _recordedPath = result.path;
      _recordedDuration = result.duration;
      _isRecording = false;
      _isPaused = false;
      _isFinished = true;
    });
  }

  Future<void> _cancel() async {
    await _recordService.cancel();
    await _playerService.stop();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _reRecord() async {
    if (_recordedPath != null) {
      try {
        final file = File(_recordedPath!);
        if (await file.exists()) await file.delete();
      } catch (e) {}
    }

    await _playerService.stop();

    setState(() {
      _isFinished = false;
      _recordedPath = null;
      _recordedDuration = 0;
      _seconds = 0;
      _waveformData.clear();
    });

    final started = await _recordService.start();
    if (!mounted) return;

    if (started) {
      setState(() => _isRecording = true);
      _startTimer();
      _listenAmplitude();
    }
  }

  Future<void> _togglePreview() async {
    if (_recordedPath == null) return;

    if (_isPlayingPreview) {
      await _playerService.pause();
    } else {
      await _playerService.play('preview', _recordedPath!);
    }
  }

  void _send() {
    if (_recordedPath == null) return;
    Navigator.pop(context, (
      path: _recordedPath!,
      duration: _recordedDuration,
    ));
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isFinished
                        ? Icons.check_circle_outline
                        : Icons.mic,
                    color: _isFinished
                        ? AppTheme.success
                        : AppTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isFinished
                        ? '녹음 완료'
                        : _isPaused
                            ? '일시정지'
                            : '음성 메시지',
                    style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              if (_isInitializing)
                _buildLoading()
              else if (!_hasPermission)
                _buildNoPermission()
              else if (_isFinished)
                _buildPreview()
              else
                _buildRecording(),

              const SizedBox(height: 32),

              if (!_isInitializing && _hasPermission)
                _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      children: [
        CircularProgressIndicator(color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(
          '녹음을 준비하고 있어요...',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildNoPermission() {
    return Column(
      children: [
        Icon(Icons.mic_off, color: AppTheme.error, size: 48),
        const SizedBox(height: 16),
        Text(
          '마이크 권한이 필요해요',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '설정에서 마이크 권한을 허용해주세요',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _cancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
          ),
          child: const Text('닫기',
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildRecording() {
    return Column(
      children: [
        // ✨ 파형 - LayoutBuilder로 반응형!
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _WaveformDisplay(
                  waveforms: _waveformData,
                  active: !_isPaused,
                  maxWidth: constraints.maxWidth,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 타이머
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isRecording && !_isPaused)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xFFEF4444),
                      const Color(0xFFEF4444).withOpacity(0.3),
                      _pulseController.value,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              )
            else if (_isPaused)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              _formatTime(_seconds),
              style: TextStyle(
                color: AppTheme.textMain,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        GestureDetector(
          onTap: _togglePreview,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              _isPlayingPreview ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          _formatTime(_recordedDuration),
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '탭하여 미리 듣기',
          style: TextStyle(
            color: AppTheme.textSub,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    if (_isFinished) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _reRecord,
              icon: Icon(Icons.refresh, color: AppTheme.textSub, size: 18),
              label: Text('다시 녹음',
                  style: TextStyle(
                      color: AppTheme.textSub,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _send,
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              label: const Text('전송',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.close,
                color: Color(0xFFEF4444), size: 18),
            label: const Text('취소',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFFEF4444)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        Expanded(
          child: OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              color: AppTheme.primary,
              size: 18,
            ),
            label: Text(
              _isPaused ? '재개' : '일시정지',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppTheme.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        Expanded(
          child: ElevatedButton.icon(
            onPressed: _seconds < 1 ? null : _finishRecording,
            icon: const Icon(Icons.check, color: Colors.white, size: 18),
            label: const Text('완료',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// ✨ 파형 디스플레이 (반응형!)
// ═══════════════════════════════════════════════
class _WaveformDisplay extends StatelessWidget {
  final List<double> waveforms;
  final bool active;
  final double maxWidth;

  const _WaveformDisplay({
    required this.waveforms,
    required this.active,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    // ✨ 화면 너비에 따라 바 개수 동적 계산
    // 바 너비: 3px, 간격: 3px = 6px per bar
    const barWidth = 3.0;
    const barSpacing = 3.0;
    const totalPerBar = barWidth + barSpacing;
    
    final barCount = (maxWidth / totalPerBar).floor();
    
    return SizedBox(
      height: 60,
      width: maxWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          // 최근 데이터만 표시 (반대 순서)
          final dataIndex = waveforms.length - 1 - index;
          final value = dataIndex >= 0 && dataIndex < waveforms.length
              ? waveforms[dataIndex]
              : 0.1;
          final height = (8 + value * 52).clamp(8.0, 60.0);

          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: barSpacing / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: barWidth,
              height: height,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.primary
                    : AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }).reversed.toList(),
      ),
    );
  }
}