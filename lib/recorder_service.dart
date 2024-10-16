// recorder_service.dart
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';

class RecorderService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final StreamSink<Uint8List> _audioStreamSink;

  RecorderService(this._audioStreamSink);

  Future<void> openRecorder() async {
    await _recorder.openRecorder();
  }

  Future<void> closeRecorder() async {
    await _recorder.closeRecorder();
  }

  Future<void> startRecording() async {
    await _recorder.startRecorder(
      codec: Codec.pcm16,
      toStream: _audioStreamSink,
    );
  }

  Future<void> stopRecording() async {
    await _recorder.stopRecorder();
  }
}
