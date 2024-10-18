// api_service.dart

import 'package:web_socket_channel/io.dart'; // Updated import
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'dart:collection';
import 'logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  IOWebSocketChannel? _channel; // Updated type
  IOWebSocketChannel? _notificationChannel; // Updated type
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool isFeedingAudio = false;

  // Unique user ID
  String? userId;

  // Event Stream Controller
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  // Server status
  bool _isServerOnline = true;

  // Heartbeat timer
  Timer? _heartbeatTimer;

  // Flag to indicate if the disconnection was intentional
  bool _isManuallyClosed = false;

  // Flag to indicate if a channel switch is in progress
  bool _isSwitchingChannel = false;

  // Initialize user ID
  Future<void> initializeUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedUserId = prefs.getString('userId');
    if (storedUserId == null) {
      userId = const Uuid().v4();
      await prefs.setString('userId', userId!);
    } else {
      userId = storedUserId;
    }

    // Connect to notification WebSocket
    await connectToNotificationWebSocket(); // Await the async method
  }

  // Heartbeat function to check server status
  void startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final response = await http.get(Uri.parse('http://192.168.0.104:8080/heartbeat'));
        if (response.statusCode == 200) {
          if (!_isServerOnline) {
            _isServerOnline = true;
            _eventController.add({'type': 'server_online'});
          }
        } else {
          if (_isServerOnline) {
            _isServerOnline = false;
            _eventController.add({'type': 'server_offline'});
          }
        }
      } catch (e) {
        if (_isServerOnline) {
          _isServerOnline = false;
          _eventController.add({'type': 'server_offline'});
        }
      }
    });
  }

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
      Logger.log("Error initializing audio player: $e");
    }
  }

  Future<void> connectToNotificationWebSocket() async {
    try {
      _notificationChannel = IOWebSocketChannel.connect(
        Uri.parse('ws://192.168.0.104:8080/ws/notifications'),
      );

      // Send the register message with userId
      _notificationChannel!.sink.add(json.encode({
        'type': 'register',
        'userId': userId,
      }));

      _notificationChannel!.stream.listen(
        (message) {
          if (message is String) {
            final decodedMessage = json.decode(message);
            if (decodedMessage['type'] == 'channel_deleted') {
              // Handle channel deletion notification
              _eventController.add({
                'type': 'channel_deleted',
                'channelName': decodedMessage['channelName'],
              });
            }
            // Handle other notification types if needed
          }
        },
        onError: (error) {
          Logger.log("Notification WebSocket error: $error");
        },
        onDone: () {
          Logger.log("Notification WebSocket connection closed");
          // Optionally, attempt to reconnect
        },
      );
    } catch (e) {
      Logger.log("Error connecting to Notification WebSocket: $e");
    }
  }

  void connectToWebSocket(String channel) async {
    _isManuallyClosed = false; // Reset the flag
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return;
    }

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(
            'ws://192.168.0.104:8080/ws/audio/${Uri.encodeComponent(channel)}/${Uri.encodeComponent(userId!)}'),
      );

      _channel!.stream.listen(
        (message) {
          if (message is Uint8List) {
            try {
              _enqueueAudio(message); // Enqueue audio for buffered playback
            } catch (e) {
              Logger.log("Error processing incoming audio: $e");
            }
          } else {
            final decodedMessage = json.decode(message);
            if (decodedMessage['type'] == 'channel_deleted') {
              // Handle channel deletion notification
              Logger.log("Channel deleted: ${decodedMessage['channelName']}");
              _eventController.add({
                'type': 'channel_deleted',
                'channelName': decodedMessage['channelName'],
              });
              // Do not automatically switch channels here
            } else if (decodedMessage['type'] == 'error') {
              // Handle error messages
              Logger.log("Error: ${decodedMessage['message']}");
            }
          }
        },
        onError: (error) {
          Logger.log("WebSocket error: $error");
          _eventController.add({'type': 'connection_error'});
        },
        onDone: () {
          Logger.log("WebSocket connection closed");
          if (!_isManuallyClosed && !_isSwitchingChannel) {
            _eventController.add({'type': 'connection_closed'});
          }
          // Reset the switching channel flag
          _isSwitchingChannel = false;
        },
      );
    } catch (e) {
      Logger.log("Error connecting to WebSocket: $e");
      _eventController.add({'type': 'connection_error'});
      _isSwitchingChannel = false; // Reset the flag on error
    }
  }

  void switchChannel(String newChannel) {
    _isSwitchingChannel = true; // Set the flag
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    connectToWebSocket(newChannel);
  }

  void sendAudioStream(Uint8List audioChunk) {
    if (_channel != null) {
      _channel!.sink.add(audioChunk);
    } else {
      Logger.log("Cannot send audio: WebSocket is not connected.");
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
            Logger.log("Playback finished");
          },
        );
      }

      if (_player.isPlaying && _player.foodSink != null) {
        try {
          await _player.feedFromStream(_audioBuffer.removeFirst());
        } catch (e) {
          Logger.log("Error feeding audio stream: $e");
          break; // Prevent continuous loop in case of errors
        }
      } else {
        Logger.log("Player is not ready for streaming.");
        break; // Break to avoid infinite loop
      }
    }
    isFeedingAudio = false;
  }

  void closeWebSocket() {
    _isManuallyClosed = true; // Set the flag
    _channel?.sink.close();
    _channel = null; // Reset the channel to allow reconnection

    // Clear the audio buffer and reset the flag
    _audioBuffer.clear();
    isFeedingAudio = false;
  }

  void dispose() {
    closeWebSocket();
    _player.closePlayer();
    _eventController.close();
    _heartbeatTimer?.cancel();
    _notificationChannel?.sink.close(); // Close the notification WebSocket
  }

  // Fetch channels from the server
  Future<List<dynamic>> fetchChannels() async {
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return [];
    }
    try {
      final response = await http.get(Uri.parse('http://192.168.0.104:8080/channels?userId=$userId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['channels'];
      } else {
        Logger.log('Failed to load channels');
        return [];
      }
    } catch (e) {
      Logger.log('Error fetching channels: $e');
      _eventController.add({'type': 'server_offline'});
      return [];
    }
  }

  // Create a new channel
  Future<bool> createChannel(String channelName) async {
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.0.104:8080/channels'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'channelName': channelName, 'userId': userId}),
      );
      if (response.statusCode == 201) {
        Logger.log('Channel "$channelName" created successfully.');
        return true;
      } else {
        final data = json.decode(response.body);
        Logger.log('Failed to create channel: ${data['message']}');
        return false;
      }
    } catch (e) {
      Logger.log('Error creating channel: $e');
      return false;
    }
  }

  // Join a channel
  Future<bool> joinChannel(String channelName) async {
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.0.104:8080/channels/${Uri.encodeComponent(channelName)}/join'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );
      if (response.statusCode == 200) {
        Logger.log('Joined channel "$channelName".');
        return true;
      } else {
        final data = json.decode(response.body);
        Logger.log('Failed to join channel: ${data['message']}');
        return false;
      }
    } catch (e) {
      Logger.log('Error joining channel: $e');
      return false;
    }
  }

  // Leave a channel
  Future<bool> leaveChannel(String channelName) async {
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.0.104:8080/channels/${Uri.encodeComponent(channelName)}/leave'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );
      if (response.statusCode == 200) {
        Logger.log('Left channel "$channelName".');
        return true;
      } else {
        final data = json.decode(response.body);
        Logger.log('Failed to leave channel: ${data['message']}');
        return false;
      }
    } catch (e) {
      Logger.log('Error leaving channel: $e');
      return false;
    }
  }

  // Delete a channel
  Future<bool> deleteChannel(String channelName) async {
    if (userId == null) {
      Logger.log('User ID not initialized.');
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse('http://192.168.0.104:8080/channels/${Uri.encodeComponent(channelName)}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );
      if (response.statusCode == 200) {
        Logger.log('Channel "$channelName" deleted successfully.');
        return true;
      } else {
        final data = json.decode(response.body);
        Logger.log('Failed to delete channel: ${data['message']}');
        return false;
      }
    } catch (e) {
      Logger.log('Error deleting channel: $e');
      return false;
    }
  }

  // Method to check if the server is online
  Future<bool> checkServerOnline() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.0.104:8080/heartbeat'));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      Logger.log('Server is offline: $e');
    }
    return false;
  }

  // Getter to access the server status
  bool get isServerOnline => _isServerOnline;

  bool get isSwitchingChannel => _isSwitchingChannel;
}
