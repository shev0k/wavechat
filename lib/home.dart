// home.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'recorder_service.dart';
import 'widgets/connectivity_card.dart';
import 'dart:async';
import 'dart:typed_data';

class WalkieTalkieHome extends StatefulWidget {
  const WalkieTalkieHome({super.key});

  @override
  State<WalkieTalkieHome> createState() => _WalkieTalkieHomeState();
}

class _WalkieTalkieHomeState extends State<WalkieTalkieHome> {
  final ApiService _apiService = ApiService();
  late final RecorderService _recorderService;
  late final StreamController<Uint8List> _audioStreamController;
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  bool isConnected = false;
  bool isTalking = false;
  int channelIndex = 0;
  final List<String> channels = ['Channel 1', 'Channel 2', 'Channel 3'];

  bool _microphonePermissionDenied = false;

  @override
  void initState() {
    super.initState();
    _audioStreamController = StreamController<Uint8List>();
    _recorderService = RecorderService(_audioStreamController.sink);
    _openRecorder();
    _setupAudioStreamListener();
  }

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _recorderService.openRecorder();
    } else {
      // Handle permission denied
      setState(() {
        _microphonePermissionDenied = true;
      });
      return;
    }
  }

  void _setupAudioStreamListener() {
    _audioStreamSubscription =
        _audioStreamController.stream.listen((audioChunk) {
      if (isConnected) {
        _apiService.sendAudioStream(audioChunk);
      }
    });
  }

  @override
  void dispose() {
    if (isTalking) {
      _stopStreaming();
    }
    if (isConnected) {
      _disconnect();
    }
    _recorderService.closeRecorder();
    _audioStreamSubscription?.cancel();
    _audioStreamController.close();
    _apiService.dispose(); // Ensure ApiService cleans up resources
    super.dispose();
  }

  void _connect() {
    if (isConnected || _microphonePermissionDenied) return;
    _apiService.connectToWebSocket(channels[channelIndex]);
    setState(() {
      isConnected = true;
    });
  }

  void _disconnect() {
    if (!isConnected) return;
    _apiService.closeWebSocket();
    setState(() {
      isConnected = false;
    });
  }

  void _switchChannel(int delta) {
    bool wasConnected = isConnected;
    if (isConnected) {
      _disconnect();
    }
    setState(() {
      channelIndex = (channelIndex + delta) % channels.length;
      if (channelIndex < 0) {
        channelIndex += channels.length;
      }
    });
    if (wasConnected) {
      _connect();
    }
  }

  void _startStreaming() async {
    if (!isConnected || _microphonePermissionDenied) {
      _showSnackBar('Please turn on the walkie talkie first.');
      return;
    }

    await _recorderService.startRecording();

    setState(() {
      isTalking = true;
    });
  }

  void _stopStreaming() async {
    await _recorderService.stopRecording();

    setState(() {
      isTalking = false;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show a SnackBar if microphone permission is denied
    if (_microphonePermissionDenied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackBar('Microphone permission is required.');
      });
    }

    return Scaffold(
      backgroundColor: Colors.black, // Black background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Connectivity Card with reduced width
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.85, // 85% of screen width
              child: ConnectivityCard(
                isConnected: isConnected,
                channelIndex: channelIndex,
                channels: channels,
                onConnect: _connect,
                onDisconnect: _disconnect,
                onSwitchChannel: _switchChannel,
              ),
            ),
            const SizedBox(height: 40),
            // Push-to-Talk Image Button
            GestureDetector(
              onTapDown: (_) {
                if (isConnected) {
                  _startStreaming();
                } else {
                  _showSnackBar('Please turn on the walkie talkie first.');
                }
              },
              onTapUp: (_) {
                if (isConnected) {
                  _stopStreaming();
                }
              },
              child: Image.asset(
                isTalking
                    ? 'assets/images/talk_active.png'
                    : 'assets/images/talk_inactive.png',
                width: 300,
                height: 300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
