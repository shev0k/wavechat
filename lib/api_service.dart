// api_service.dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'dart:collection';

class ApiService {
  WebSocketChannel? _channel;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool isFeedingAudio = false;

  // Buffer for incoming audio data
  final Queue<Uint8List> _audioBuffer = Queue<Uint8List>();
  final int maxBufferLength = 500; // Max number of audio chunks to buffer

  ApiService() {
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      await _player.openPlayer();
    } catch (e) {
      print("Error initializing audio player: $e");
    }
  }

  void connectToWebSocket(String channel) {
    if (_channel != null) {
      closeWebSocket(); // Close existing connection before creating a new one
    }

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://192.168.0.104:8080/ws/audio/$channel'),
      );

      _channel!.stream.listen(
        (message) {
          if (message is Uint8List) {
            try {
              _enqueueAudio(message); // Enqueue audio for buffered playback
            } catch (e) {
              print("Error processing incoming audio: $e");
            }
          } else {
            print("Received non-audio message");
          }
        },
        onError: (error) {
          print("WebSocket error: $error");
          // Optionally, notify the UI about the error
        },
        onDone: () {
          print("WebSocket connection closed");
          // Optionally, notify the UI that the connection is closed
        },
      );
    } catch (e) {
      print("Error connecting to WebSocket: $e");
      // Optionally, notify the UI about the connection error
    }
  }

  void sendAudioStream(Uint8List audioChunk) {
    if (_channel != null) {
      _channel!.sink.add(audioChunk);
    } else {
      print("Cannot send audio: WebSocket is not connected.");
    }
  }

  void _enqueueAudio(Uint8List audioData) {
    // Limit the buffer size to prevent memory issues
    if (_audioBuffer.length >= maxBufferLength) {
      _audioBuffer.removeFirst();
    }
    _audioBuffer.add(audioData);
    if (!isFeedingAudio) {
      _feedAudioStream();
    }
  }

  void _feedAudioStream() async {
    isFeedingAudio = true;
    while (_audioBuffer.isNotEmpty) {
      if (!_player.isPlaying) {
        await _player.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 16000,
          whenFinished: () {
            print("Playback finished");
          },
        );
      }

      if (_player.isPlaying && _player.foodSink != null) {
        try {
          await _player.feedFromStream(_audioBuffer.removeFirst());
        } catch (e) {
          print("Error feeding audio stream: $e");
          break; // Prevent continuous loop in case of errors
        }
      } else {
        print("Player is not ready for streaming.");
        break; // Break to avoid infinite loop
      }
    }
    isFeedingAudio = false;
  }

  void closeWebSocket() {
    _channel?.sink.close();
    _channel = null; // Reset the channel to allow reconnection

    // Do not stop the player here
    // _player.stopPlayer();

    // Clear the audio buffer and reset the flag
    _audioBuffer.clear();
    isFeedingAudio = false;
  }

  void dispose() {
    closeWebSocket();
    _player.closePlayer();
  }
}
