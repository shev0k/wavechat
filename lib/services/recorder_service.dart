// recorder_service.dart
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'logger.dart';

class RecorderService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final StreamSink<Uint8List> _audioStreamSink;

  RecorderService(this._audioStreamSink);

  Future<void> openRecorder() async {
    try {
      await _recorder.openRecorder();
    } catch (e) {
      Logger.log('Error opening recorder: $e');
    }
  }

  Future<void> closeRecorder() async {
    try {
      await _recorder.closeRecorder();
    } catch (e) {
      Logger.log('Error closing recorder: $e');
    }
  }

  Future<void> startRecording() async {
    try {
      await _recorder.startRecorder(
        codec: Codec.pcm16,
        toStream: _audioStreamSink,
      );
    } catch (e) {
      Logger.log('Error starting recording: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      await _recorder.stopRecorder();
    } catch (e) {
      Logger.log('Error stopping recording: $e');
    }
  }
}
