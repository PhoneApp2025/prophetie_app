import 'dart:async';
import 'dart:io';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';

class RecordingService {
  late final RecorderController _recorderController;
  String? _recordingPath;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  Function(Duration)? onTimerTick;

  RecorderController get recorderController => _recorderController;
  String? get recordingPath => _recordingPath;
  Duration get elapsed => _elapsed;

  RecordingService({this.onTimerTick}) {
    _recorderController = RecorderController();
  }

  Future<void> startRecording() async {
    final hasPermission = await _recorderController.checkPermission();
    if (!hasPermission) return;

    final dir = await getApplicationDocumentsDirectory();
    _recordingPath =
        '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorderController.record(path: _recordingPath!);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsed += const Duration(milliseconds: 100);
      onTimerTick?.call(_elapsed);
    });
  }

  Future<void> pauseRecording() async {
    await _recorderController.pause();
    _timer?.cancel();
  }

  Future<void> resumeRecording() async {
    await _recorderController.record(path: _recordingPath!);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsed += const Duration(milliseconds: 100);
      onTimerTick?.call(_elapsed);
    });
  }

  Future<String?> stopRecording() async {
    _timer?.cancel();
    final path = await _recorderController.stop();
    _elapsed = Duration.zero;
    return path;
  }

  void dispose() {
    _timer?.cancel();
    _recorderController.dispose();
  }
}
