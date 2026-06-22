import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════
// 음성 녹음 서비스
// ═══════════════════════════════════════════════
class AudioRecordService {
  static final AudioRecordService _instance =
      AudioRecordService._internal();
  factory AudioRecordService() => _instance;
  AudioRecordService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  DateTime? _startTime;
  int _pausedDuration = 0;
  bool _isPaused = false;

  bool get isRecording => _currentPath != null && !_isPaused;
  bool get isPaused => _isPaused;
  bool get hasRecording => _currentPath != null;

  /// 녹음 시작
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) {
        print('❌ 마이크 권한 없음');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 22050,
        ),
        path: path,
      );

      _currentPath = path;
      _startTime = DateTime.now();
      _pausedDuration = 0;
      _isPaused = false;
      return true;
    } catch (e) {
      print('❌ 녹음 시작 실패: $e');
      return false;
    }
  }

  /// 일시정지
  Future<void> pause() async {
    try {
      if (!isRecording) return;
      await _recorder.pause();
      
      // 경과 시간 누적
      if (_startTime != null) {
        _pausedDuration += DateTime.now().difference(_startTime!).inSeconds;
        _startTime = null;
      }
      _isPaused = true;
    } catch (e) {
      print('❌ 일시정지 실패: $e');
    }
  }

  /// 재개
  Future<void> resume() async {
    try {
      if (!_isPaused) return;
      await _recorder.resume();
      _startTime = DateTime.now();
      _isPaused = false;
    } catch (e) {
      print('❌ 재개 실패: $e');
    }
  }

  /// 녹음 중지 & 파일 경로 반환
  Future<({String path, int duration})?> stop() async {
    try {
      if (!hasRecording) return null;

      final path = await _recorder.stop();
      if (path == null) return null;

      final duration = currentDuration;
      
      _currentPath = null;
      _startTime = null;
      _pausedDuration = 0;
      _isPaused = false;

      return (path: path, duration: duration);
    } catch (e) {
      print('❌ 녹음 중지 실패: $e');
      return null;
    }
  }

  /// 녹음 취소 (파일 삭제)
  Future<void> cancel() async {
    try {
      if (!hasRecording) return;

      await _recorder.stop();

      if (_currentPath != null) {
        final file = File(_currentPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _currentPath = null;
      _startTime = null;
      _pausedDuration = 0;
      _isPaused = false;
    } catch (e) {
      print('❌ 녹음 취소 실패: $e');
    }
  }

  /// 현재 녹음 시간 (초)
  int get currentDuration {
    int total = _pausedDuration;
    if (_startTime != null && !_isPaused) {
      total += DateTime.now().difference(_startTime!).inSeconds;
    }
    return total;
  }

  /// 데시벨 스트림 (파형 애니메이션용)
  Stream<Amplitude> get amplitudeStream =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  void dispose() {
    _recorder.dispose();
  }
}

// ═══════════════════════════════════════════════
// 음성 재생 서비스
// ═══════════════════════════════════════════════
class AudioPlayerService {
  static final AudioPlayerService _instance =
      AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  AudioPlayer? _player;
  String? _currentMessageId;

  String? get currentMessageId => _currentMessageId;

  final _playingController = StreamController<String?>.broadcast();
  Stream<String?> get playingStream => _playingController.stream;

  /// 재생 (URL 또는 로컬 파일 경로)
  Future<void> play(String messageId, String source, {double speed = 1.0}) async {
    try {
      await stop();

      _player = AudioPlayer();
      _currentMessageId = messageId;
      _playingController.add(messageId);

      // 로컬 파일 vs URL 구분
      // 로컬 파일 vs URL 구분
      if (source.startsWith('http')) {
        await _player!.setUrl(source);
      } else {
        // file:// 스킴이 붙어 있으면 제거 (복원된 음성 대응)
        final filePath = source.startsWith('file://')
            ? Uri.parse(source).toFilePath()
            : source;
        await _player!.setFilePath(filePath);
      }
      
      await _player!.setSpeed(speed);
      await _player!.play();

      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          stop();
        }
      });
    } catch (e) {
      print('❌ 재생 실패: $e');
      _currentMessageId = null;
      _playingController.add(null);
    }
  }

  Future<void> pause() async {
    await _player?.pause();
    _playingController.add(null);
  }

  Future<void> resume() async {
    await _player?.play();
    if (_currentMessageId != null) {
      _playingController.add(_currentMessageId);
    }
  }

  Future<void> stop() async {
    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _currentMessageId = null;
    _playingController.add(null);
  }

  Future<void> setSpeed(double speed) async {
    await _player?.setSpeed(speed);
  }

  Stream<Duration> get positionStream =>
      _player?.positionStream ?? const Stream.empty();

  Duration? get duration => _player?.duration;

  bool get isPlaying => _player?.playing ?? false;
}

// ═══════════════════════════════════════════════
// Supabase 업로드 헬퍼
// ═══════════════════════════════════════════════
Future<String> uploadAudioFile({
  required String localPath,
  required String roomId,
}) async {
  final file = File(localPath);
  final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
  final path = 'audio/$roomId/$fileName';

  await Supabase.instance.client.storage.from('kyorangtalk').upload(
        path,
        file,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'audio/m4a',
        ),
      );

  final url = Supabase.instance.client.storage
      .from('kyorangtalk')
      .getPublicUrl(path);

  // 로컬 임시 파일 삭제
  try {
    await file.delete();
  } catch (e) {
    print('임시 파일 삭제 실패: $e');
  }

  return url;
}