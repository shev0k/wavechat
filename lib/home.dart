// home.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'recorder_service.dart';
import 'widgets/connectivity_card.dart';
import 'dart:async';
import 'dart:typed_data';
import 'logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late ValueNotifier<List<dynamic>> channelsNotifier;

  bool _microphonePermissionDenied = false;

  // Server status
  bool _serverOnline = true;

  // Common TextStyle
  final TextStyle _textStyle = const TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontFamily: 'RetroFont',
  );

  @override
  void initState() {
    super.initState();
    _audioStreamController = StreamController<Uint8List>();
    _recorderService = RecorderService(_audioStreamController.sink);
    _openRecorder();
    _setupAudioStreamListener();
    channelsNotifier = ValueNotifier<List<dynamic>>([]);
    _initializeUser();
    _setupEventListener();
    _apiService.startHeartbeat();

    // Preload images to ensure they are loaded even if the server is offline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/talk_active.png'), context);
      precacheImage(const AssetImage('assets/images/talk_inactive.png'), context);
    });
  }

  Future<void> _initializeUser() async {
    try {
      await _apiService.initializeUserId();
    } catch (e) {
      Logger.log('Error initializing user ID: $e');
    }

    await _fetchChannels();
    await _loadLastSelectedChannel();
  }

  Future<void> _loadLastSelectedChannel() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? lastChannel = prefs.getString('lastChannel');
    if (lastChannel != null) {
      int index = channelsNotifier.value.indexWhere((channel) => channel['name'] == lastChannel);
      if (index != -1) {
        setState(() {
          channelIndex = index;
        });
      }
    }
  }

  void _setupEventListener() {
  _apiService.events.listen((event) async {
    if (event['type'] == 'server_online') {
      _showSnackBar('Server is back online.');
      setState(() {
        _serverOnline = true;
      });
      await _fetchChannels();
      if (!mounted) return;

      if (channelsNotifier.value.isNotEmpty) {
        if (channelIndex == -1) {
          setState(() {
            channelIndex = 0;
          });
          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
        }
      }

      // Attempt to reconnect if previously connected
      if (isConnected) {
        String channelName = channelsNotifier.value.isNotEmpty && channelIndex >= 0
            ? channelsNotifier.value[channelIndex]['name']
            : null;
        _connect(channelName);
            }
    }
      if (event['type'] == 'channel_deleted') {
        String deletedChannel = event['channelName'];
        String? currentChannelName = channelsNotifier.value.isNotEmpty &&
                channelIndex >= 0 &&
                channelIndex < channelsNotifier.value.length
            ? channelsNotifier.value[channelIndex]['name']
            : null;

        await _fetchChannels(); // Re-fetch channels from server
        if (!mounted) return;

        if (deletedChannel == currentChannelName) {
          // Current channel has been deleted
          // Attempt to switch to "Channel 1"
          int newIndex = channelsNotifier.value
              .indexWhere((channel) => channel['name'] == 'Channel 1');
          if (newIndex != -1) {
            setState(() {
              channelIndex = newIndex;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', 'Channel 1');
            if (isConnected) {
              _apiService.switchChannel('Channel 1');
            } else {
              _connect('Channel 1'); // Attempt to connect to "Channel 1"
            }
            _showSnackBar(
                'Channel "$deletedChannel" has been deleted. Switched to "Channel 1".');
          } else if (channelsNotifier.value.isNotEmpty) {
            // "Channel 1" not found, switch to first available channel
            setState(() {
              channelIndex = 0;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
            if (isConnected) {
              _apiService.switchChannel(channelsNotifier.value[channelIndex]['name']);
            } else {
              _connect(channelsNotifier.value[channelIndex]['name']); // Attempt to connect
            }
            _showSnackBar(
                'Channel "$deletedChannel" has been deleted. Switched to "${channelsNotifier.value[channelIndex]['name']}".');
          } else {
            // No channels are available
            setState(() {
              channelIndex = -1;
              isConnected = false;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.remove('lastChannel');
            if (isConnected) {
              _disconnect();
            }
            _showSnackBar(
                'Channel "$deletedChannel" has been deleted. No channels available.');
          }
        } else {
          // Deleted channel is not the current channel
          // Update the channel index if necessary
          int newIndex = channelsNotifier.value
              .indexWhere((channel) => channel['name'] == currentChannelName);
          if (newIndex != -1) {
            setState(() {
              channelIndex = newIndex;
            });
          } else if (channelsNotifier.value.isNotEmpty) {
            setState(() {
              channelIndex = 0;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
            if (isConnected) {
              _apiService.switchChannel(channelsNotifier.value[channelIndex]['name']);
            } else {
              _connect(channelsNotifier.value[channelIndex]['name']); // Attempt to connect
            }
          } else {
            // No channels left
            setState(() {
              channelIndex = -1;
              isConnected = false;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.remove('lastChannel');
            if (isConnected) {
              _disconnect();
            }
          }
          _showSnackBar('Channel "$deletedChannel" has been deleted.');
        }
      } else if (event['type'] == 'connection_error') {
        _showSnackBar('Lost connection to the server.');
        setState(() {
          isConnected = false;
        });
      } else if (event['type'] == 'connection_closed') {
        // Connection was closed intentionally or unintentionally
        Logger.log('Connection closed.');
        // Only set isConnected to false if not switching channels
        if (!_apiService.isSwitchingChannel) {
          setState(() {
            isConnected = false;
          });
        }
      } else if (event['type'] == 'server_offline') {
        _showSnackBar('Server is offline.');
        setState(() {
          _serverOnline = false;
          isConnected = false;
        });
      } else if (event['type'] == 'server_online') {
        _showSnackBar('Server is back online.');
        setState(() {
          _serverOnline = true;
        });
        await _fetchChannels();

        // Attempt to reconnect if the user was connected before
        if (isConnected) {
          _connect();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This method can be used to preload images, but we already did it in initState
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
    _audioStreamSubscription = _audioStreamController.stream.listen((audioChunk) {
      if (isConnected) {
        _apiService.sendAudioStream(audioChunk);
      }
    });
  }

  Future<void> _fetchChannels() async {
  try {
    final fetchedChannels = await _apiService.fetchChannels();
    if (!mounted) return;

    setState(() {
      channelsNotifier.value = fetchedChannels;
      if (channelsNotifier.value.isNotEmpty) {
        if (channelIndex == -1) {
          // If previously there were no channels, set channelIndex to 0
          channelIndex = 0;
        } else if (channelIndex >= channelsNotifier.value.length) {
          // If channelIndex is out of bounds, adjust it
          channelIndex = channelsNotifier.value.length - 1;
        }
      } else {
        // No channels available
        channelIndex = -1;
      }
    });
  } catch (e) {
    Logger.log('Error fetching channels: $e');
    if (!mounted) return;
    setState(() {
      channelsNotifier.value = [];
      channelIndex = -1;
    });
  }

  // Remember last connected channel if applicable
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? lastChannel = prefs.getString('lastChannel');
  if (lastChannel != null) {
    int index = channelsNotifier.value.indexWhere((channel) => channel['name'] == lastChannel);
    if (index != -1) {
      setState(() {
        channelIndex = index;
      });
    } else if (channelsNotifier.value.isNotEmpty) {
      setState(() {
        channelIndex = 0;
      });
      prefs.setString('lastChannel', channelsNotifier.value[0]['name']);
    } else {
      setState(() {
        channelIndex = -1;
      });
      prefs.remove('lastChannel');
    }
  }
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
    _apiService.dispose();
    channelsNotifier.dispose();
    super.dispose();
  }

  void _connect([String? channelName]) {
  if (isConnected || _microphonePermissionDenied) return;
  if (!_serverOnline) {
    _showSnackBar('Attempting to connect, but the server appears to be offline.');
    // Continue attempting to connect
  }
  if (channelIndex == -1 || channelsNotifier.value.isEmpty) {
    _showSnackBar('No channels available to connect.');
    return;
  }
  try {
    String channelToConnect = channelName ?? channelsNotifier.value[channelIndex]['name'];
    _apiService.connectToWebSocket(channelToConnect);
    setState(() {
      isConnected = true;
    });
  } catch (e) {
    Logger.log('Connection error: $e');
    _showSnackBar('Failed to connect to the server.');
    setState(() {
      isConnected = false;
    });
  }
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
      _apiService.switchChannel(
          channelsNotifier.value[(channelIndex + delta) % channelsNotifier.value.length]['name']);
    }
    setState(() {
      int newIndex = (channelIndex + delta) % channelsNotifier.value.length;
      if (newIndex < 0) {
        newIndex += channelsNotifier.value.length;
      }
      channelIndex = newIndex;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
    });
    if (wasConnected) {
      // No need to reconnect, as switchChannel handles it
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
    // Remove any existing MaterialBanner
    ScaffoldMessenger.of(context).removeCurrentMaterialBanner();

    // Create a new MaterialBanner
    final materialBanner = MaterialBanner(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: Colors.black87,
      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return; // Ensure the widget is still mounted
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text(
            'DISMISS',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );

    // Show the new MaterialBanner
    ScaffoldMessenger.of(context)
      ..clearMaterialBanners() // Clear any existing banners
      ..showMaterialBanner(materialBanner);

    // Automatically dismiss the MaterialBanner after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return; // Ensure the widget is still mounted
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  // Method to display channel options
  void _showChannelOptionsDialog() {
    // Users can now navigate the menus even when disconnected

    showDialog(
      context: context,
      builder: (context) {
        return _CustomDialog(
          title: 'Channel Options',
          icon: Icons.settings,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogOption(
                icon: Icons.add,
                text: 'Create Channel',
                onTap: () {
                  Navigator.of(context).pop(); // Close current dialog
                  _showCreateChannelDialog();
                },
              ),
              _DialogOption(
                icon: Icons.login,
                text: 'Join Channel',
                onTap: () {
                  Navigator.of(context).pop(); // Close current dialog
                  _showJoinChannelDialog();
                },
              ),
              _DialogOption(
                icon: Icons.list,
                text: 'Manage Channels',
                onTap: () {
                  Navigator.of(context).pop(); // Close current dialog
                  _showManageChannelsDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Custom Dialog Widget
  void _showCustomDialog({
    required String title,
    required IconData icon,
    required Widget content,
    List<Widget>? actions,
    double iconVerticalOffset = 0.0, // New parameter
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder: (context) {
        return _CustomDialog(
          title: title,
          icon: icon,
          content: content,
          actions: actions,
          iconVerticalOffset: iconVerticalOffset, // Pass the offset
        );
      },
    );
  }

  // Method to display the create channel dialog
  void _showCreateChannelDialog() {
    String channelName = '';
    _showCustomDialog(
      title: 'Create Channel',
      icon: Icons.add,
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              onChanged: (value) {
                channelName = value.trim();
              },
              style: _textStyle,
              decoration: InputDecoration(
                hintText: 'Enter channel name',
                hintStyle: _textStyle.copyWith(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.5))),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Back Button
                _DialogButton(
                  icon: Icons.arrow_back,
                  onTap: () {
                    Navigator.of(context).pop();
                    _showChannelOptionsDialog(); // Go back to main dialog
                  },
                ),
                const SizedBox(width: 10),
                // Confirm Button
                _DialogButton(
                  icon: Icons.check,
                  onTap: () async {
                    if (channelName.isNotEmpty) {
                      await _createChannel(channelName);
                    } else {
                      _showSnackBar('Channel name cannot be empty.');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      iconVerticalOffset: 1.0, // Adjust icon position if needed
    );
  }

  // Method to display the join channel dialog
  void _showJoinChannelDialog() {
    String channelName = '';
    _showCustomDialog(
      title: 'Join Channel',
      icon: Icons.login,
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              onChanged: (value) {
                channelName = value.trim();
              },
              style: _textStyle,
              decoration: InputDecoration(
                hintText: 'Enter channel name',
                hintStyle: _textStyle.copyWith(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.5))),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Back Button
                _DialogButton(
                  icon: Icons.arrow_back,
                  onTap: () {
                    Navigator.of(context).pop();
                    _showChannelOptionsDialog(); // Go back to main dialog
                  },
                ),
                const SizedBox(width: 10),
                // Confirm Button
                _DialogButton(
                  icon: Icons.check,
                  onTap: () async {
                    if (channelName.isNotEmpty) {
                      await _joinChannel(channelName);
                    } else {
                      _showSnackBar('Channel name cannot be empty.');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      iconVerticalOffset: 1.0, // Adjust icon position if needed
    );
  }

  void _showManageChannelsDialog() {
    _showCustomDialog(
      title: 'Manage Channels',
      icon: Icons.list,
      content: ValueListenableBuilder<List<dynamic>>(
        valueListenable: channelsNotifier,
        builder: (context, channelsList, _) {
          // Include both user-created and joined channels
          List<dynamic> userChannels = channelsList.where((channel) {
            return channel['creatorId'] == _apiService.userId ||
                (channel['members'] != null && channel['members'].contains(_apiService.userId));
          }).toList();

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5, // Set a max height
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (userChannels.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      itemCount: userChannels.length,
                      itemBuilder: (context, index) {
                        var channel = userChannels[index];
                        String channelName = channel['name'];

                        return _ChannelCard(
                          channelName: channelName,
                          isOwner: channel['creatorId'] == _apiService.userId,
                          onDelete: () async {
                            if (channel['creatorId'] == _apiService.userId) {
                              await _deleteChannel(channelName);
                            } else {
                              await _leaveChannel(channelName);
                            }
                          },
                          onTap: () {
                            int newIndex = channelsNotifier.value
                                .indexWhere((ch) => ch['name'] == channelName);
                            if (newIndex != -1) {
                              _switchChannel(newIndex - channelIndex);
                              Navigator.of(context).pop(); // Close dialog
                              _showSnackBar('Switched to "$channelName".');
                            }
                          },
                        );
                      },
                    ),
                  )
                else
                  const SizedBox(height: 10),
                if (userChannels.isEmpty)
                  Text(
                    'No channels available.',
                    style: _textStyle.copyWith(color: Colors.white70),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DialogButton(
                      icon: Icons.arrow_back,
                      onTap: () {
                        Navigator.of(context).pop();
                        _showChannelOptionsDialog(); // Go back to main dialog
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      iconVerticalOffset: 1.0, // Adjust icon position if needed
    );
  }

  Future<void> _createChannel(String channelName) async {
    if (!_serverOnline) {
      _showSnackBar('Cannot create channel: Server is offline.');
      return;
    }
    bool success = await _apiService.createChannel(channelName);
    if (success) {
      await _fetchChannels();
      if (!mounted) return; // Check if the widget is still mounted

      int newIndex =
          channelsNotifier.value.indexWhere((channel) => channel['name'] == channelName);
      if (newIndex != -1) {
        setState(() {
          channelIndex = newIndex;
        });
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('lastChannel', channelName);
        if (isConnected) {
          _apiService.switchChannel(channelName);
        }
        if (mounted) _showSnackBar('Channel "$channelName" created.');
      }
      if (mounted) Navigator.of(context).pop(); // Close dialog
    } else {
      _showSnackBar('Failed to create channel. It may already exist or server error.');
    }
  }

  Future<void> _joinChannel(String channelName) async {
    if (!_serverOnline) {
      _showSnackBar('Cannot join channel: Server is offline.');
      return;
    }
    bool success = await _apiService.joinChannel(channelName);
    if (success) {
      await _fetchChannels();
      if (!mounted) return; // Ensure the widget is still mounted

      int newIndex =
          channelsNotifier.value.indexWhere((channel) => channel['name'] == channelName);
      if (newIndex == -1) {
        if (mounted) _showSnackBar('Channel "$channelName" does not exist.');
        return;
      }

      if (channelsNotifier.value[channelIndex]['name'] == channelName) {
        if (mounted) _showSnackBar('You are already in channel "$channelName".');
        return;
      }

      // Update the state with the new channel index
      setState(() {
        channelIndex = newIndex;
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('lastChannel', channelName);

      // Switch to the new channel without disconnecting
      if (isConnected) {
        _apiService.switchChannel(channelName);
      }

      if (mounted) {
        _showSnackBar('Joined channel "$channelName".');
        Navigator.of(context).pop(); // Close dialog
      }
    } else {
      _showSnackBar('Failed to join channel. It may not exist or server error.');
    }
  }

  Future<void> _leaveChannel(String channelName) async {
  if (!_serverOnline) {
    _showSnackBar('Cannot leave channel: Server is offline.');
    return;
  }

  // Store the current channel name before updating channels
  String? currentChannelName = channelsNotifier.value.isNotEmpty &&
          channelIndex >= 0 &&
          channelIndex < channelsNotifier.value.length
      ? channelsNotifier.value[channelIndex]['name']
      : null;

  bool success = await _apiService.leaveChannel(channelName);
  if (success) {
    await _fetchChannels();
    if (!mounted) return;

    if (channelsNotifier.value.isNotEmpty) {
      if (currentChannelName == channelName) {
        // The user left the current channel
        int newIndex = channelsNotifier.value
            .indexWhere((channel) => channel['name'] == 'Channel 1');
        if (newIndex != -1) {
          setState(() {
            channelIndex = newIndex;
          });
          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setString('lastChannel', 'Channel 1');
          if (isConnected) {
            _apiService.switchChannel('Channel 1');
          } else {
            _connect('Channel 1');
          }
        } else {
          // If 'Channel 1' is not available, switch to first available channel
          setState(() {
            channelIndex = 0;
          });
          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
          if (isConnected) {
            _apiService.switchChannel(channelsNotifier.value[channelIndex]['name']);
          } else {
            _connect(channelsNotifier.value[channelIndex]['name']);
          }
        }
      } else {
        // The user left a channel that is not the current one
        // Ensure the channelIndex is still valid
        int newIndex = channelsNotifier.value
            .indexWhere((channel) => channel['name'] == currentChannelName);
        if (newIndex != -1) {
          setState(() {
            channelIndex = newIndex;
          });
        } else {
          // Current channel is no longer available, switch to 'Channel 1' or first available
          int channel1Index = channelsNotifier.value
              .indexWhere((channel) => channel['name'] == 'Channel 1');
          if (channel1Index != -1) {
            setState(() {
              channelIndex = channel1Index;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', 'Channel 1');
            if (isConnected) {
              _apiService.switchChannel('Channel 1');
            } else {
              _connect('Channel 1');
            }
          } else {
            setState(() {
              channelIndex = 0;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
            if (isConnected) {
              _apiService.switchChannel(channelsNotifier.value[channelIndex]['name']);
            } else {
              _connect(channelsNotifier.value[channelIndex]['name']);
            }
          }
        }
      }
      _showSnackBar('Left channel "${channelName.toUpperCase()}".');
    } else {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.remove('lastChannel');
      _showSnackBar('No channels available.');
      _disconnect();
    }
  } else {
    _showSnackBar('Failed to leave channel.');
  }
}


  Future<void> _deleteChannel(String channelName) async {
    if (!_serverOnline) {
      _showSnackBar('Cannot delete channel: Server is offline.');
      return;
    }
    bool success = await _apiService.deleteChannel(channelName);
    if (success) {
      await _fetchChannels();
      if (channelsNotifier.value.isNotEmpty) {
        if (channelsNotifier.value[channelIndex]['name'] == channelName) {
          // If we deleted the channel we're currently connected to
          int newIndex =
              channelsNotifier.value.indexWhere((channel) => channel['name'] == 'Channel 1');
          if (newIndex != -1) {
            setState(() {
              channelIndex = newIndex;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', 'Channel 1');
            if (isConnected) {
              _apiService.switchChannel('Channel 1');
            } else {
              _connect('Channel 1'); // Attempt to connect to "Channel 1"
            }
          } else {
            setState(() {
              channelIndex = 0;
            });
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString('lastChannel', channelsNotifier.value[channelIndex]['name']);
            if (isConnected) {
              _apiService.switchChannel(channelsNotifier.value[channelIndex]['name']);
            } else {
              _connect(channelsNotifier.value[channelIndex]['name']); // Attempt to connect
            }
          }
          _showSnackBar(
              'Channel "$channelName" deleted. Switched to "${channelsNotifier.value[channelIndex]['name']}".');
        } else {
          _showSnackBar('Channel "$channelName" deleted.');
        }
      } else {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.remove('lastChannel');
        _showSnackBar('Channel "$channelName" deleted. No channels available.');
        _disconnect();
      }
    } else {
      _showSnackBar('Failed to delete channel.');
    }
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
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ValueListenableBuilder<List<dynamic>>(
          valueListenable: channelsNotifier,
          builder: (context, channelsList, _) {
            // Always show the home screen regardless of server status
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Connectivity Card with reduced width
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.85,
                  child: ConnectivityCard(
                    isConnected: isConnected,
                    channelIndex: channelIndex,
                    channels: channelsList
                        .map<String>((channel) => channel['name'] as String)
                        .toList(),
                    onConnect: _connect,
                    onDisconnect: _disconnect,
                    onSwitchChannel: _switchChannel,
                    onChannelOptions: _showChannelOptionsDialog,
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
                    gaplessPlayback: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Custom Dialog Widget
class _CustomDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget content;
  final List<Widget>? actions;
  final double iconVerticalOffset; // New parameter

  const _CustomDialog({
    required this.title,
    required this.icon,
    required this.content,
    this.actions,
    this.iconVerticalOffset = 1.0, // Default value
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle _textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontFamily: 'RetroFont',
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white54),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center, // Added this line
                  children: [
                    Transform.translate(
                      offset: Offset(0, iconVerticalOffset),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: _textStyle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                content,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog Option Widget
class _DialogOption extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final double iconVerticalOffset; // New parameter

  const _DialogOption({
    required this.icon,
    required this.text,
    required this.onTap,
    this.iconVerticalOffset = 1.0, // Default value
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle _textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontFamily: 'RetroFont',
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, // Added this line
          children: [
            Transform.translate(
              offset: Offset(0, iconVerticalOffset),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: _textStyle,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

// Dialog Button Widget
class _DialogButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _DialogButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
            color: Color.fromARGB(202, 255, 255, 255), shape: BoxShape.circle),
        padding: const EdgeInsets.all(8.0), // Reduced from 12.0 to 8.0
        child: Icon(
          icon,
          color: Colors.black,
          size: 25.0, // Adjusted size
        ),
      ),
    );
  }
}

// Channel Card Widget
class _ChannelCard extends StatelessWidget {
  final String channelName;
  final bool isOwner;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channelName,
    required this.isOwner,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle _textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontFamily: 'RetroFont',
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                channelName,
                style: _textStyle,
              ),
            ),
            IconButton(
              icon: Icon(
                isOwner ? Icons.delete : Icons.exit_to_app,
                color: Colors.white,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
