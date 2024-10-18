// home.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/api_service.dart';
import 'services/recorder_service.dart';
import 'widgets/connectivity_card.dart';
import 'dart:async';
import 'dart:typed_data';
import 'services/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/*
===============================================================================
                                    SECTIONS
===============================================================================

1. VARIABLES .................................................................. Line 34
   - variables used throughout the class

2. INITIALIZATION ............................................................. Line 54
   - initState()
   - _initializeUser()
   - _loadLastSelectedChannel()
   - _openRecorder()

3. EVENT LISTENERS ............................................................ Line 98
   - _setupEventListener()
   - _setupAudioStreamListener()

4. RECORDER METHODS ........................................................... Line 153
   - _startStreaming()
   - _stopStreaming()

5. API CALLS .................................................................. Line 169
   - _fetchChannels()
   - _connect()
   - _disconnect()
   - _createChannel()
   - _joinChannel()
   - _leaveChannel()
   - _deleteChannel()

6. UI METHODS ................................................................. Line 268
   - _switchChannel()
   - _showSnackBar()
   - _showChannelOptionsDialog()
   - _showCreateChannelDialog()
   - _showJoinChannelDialog()
   - _showManageChannelsDialog()
   - _showCustomDialog()

===============================================================================
*/

class WalkieTalkieHome extends StatefulWidget {
  const WalkieTalkieHome({super.key});

  @override
  State<WalkieTalkieHome> createState() => _WalkieTalkieHomeState();
}

class _WalkieTalkieHomeState extends State<WalkieTalkieHome> {

  // ============================================================================
  //                                    VARIABLES
  // ============================================================================
  // VARIABLES USED THROUGHOUT THE CLASS.

  final ApiService _apiService = ApiService();
  late final RecorderService _recorderService;
  late final StreamController<Uint8List> _audioStreamController;
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  bool isConnected = false;
  bool isTalking = false;
  int channelIndex = 0;
  late ValueNotifier<List<dynamic>> channelsNotifier;

  bool _microphonePermissionDenied = false;

  // SERVER STATUS
  bool _serverOnline = true;

  // COMMON TEXT STYLE
  final TextStyle _textStyle = const TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontFamily: 'RetroFont',
  );

  // ============================================================================
  //                                   INITIALIZATION
  // ============================================================================
  // INITIALIZING THE STATE AND SETUP.

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

    // PRELOAD IMAGES
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

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _recorderService.openRecorder();
    } else {
      // PERMISSION DENIED
      setState(() {
        _microphonePermissionDenied = true;
      });
      return;
    }
  }

  // ============================================================================
  //                                  EVENT LISTENERS
  // ============================================================================
  // SETTING UP EVENT LISTENERS.

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

        // RECONNECT IF PREVIOUSLY CONNECTED
        if (isConnected) {
          String channelName = channelsNotifier.value.isNotEmpty && channelIndex >= 0
              ? channelsNotifier.value[channelIndex]['name']
              : null;
          _connect(channelName);
        }
      }

      // HANDLE CHANNEL DELETED EVENT
      if (event['type'] == 'channel_deleted') {
        String deletedChannel = event['channelName'];
        String? currentChannelName = channelsNotifier.value.isNotEmpty &&
                channelIndex >= 0 &&
                channelIndex < channelsNotifier.value.length
            ? channelsNotifier.value[channelIndex]['name']
            : null;

        await _fetchChannels();
        if (!mounted) return;

        if (deletedChannel == currentChannelName) {
          // CURRENT CHANNEL DELETED
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
            _showSnackBar(
                'Channel "$deletedChannel" has been deleted. Switched to "Channel 1".');
          } else if (channelsNotifier.value.isNotEmpty) {
            // SWITCH TO FIRST AVAILABLE CHANNEL
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
            _showSnackBar(
                'Channel "$deletedChannel" has been deleted. Switched to "${channelsNotifier.value[channelIndex]['name']}".');
          } else {
            // NO CHANNELS AVAILABLE
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
          // DELETED CHANNEL IS NOT CURRENT CHANNEL
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
              _connect(channelsNotifier.value[channelIndex]['name']);
            }
          } else {
            // NO CHANNELS LEFT
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
        // CONNECTION CLOSED
        Logger.log('Connection closed.');
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

        // RECONNECT IF PREVIOUSLY CONNECTED
        if (isConnected) {
          _connect();
        }
      }
    });
  }

  void _setupAudioStreamListener() {
    _audioStreamSubscription = _audioStreamController.stream.listen((audioChunk) {
      if (isConnected) {
        _apiService.sendAudioStream(audioChunk);
      }
    });
  }

  // ============================================================================
  //                                 RECORDER METHODS
  // ============================================================================
  // STARTING AND STOPPING AUDIO STREAMING.

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

  // ============================================================================
  //                                    API CALLS
  // ============================================================================
  // INTERACT WITH THE API SERVICE.

  Future<void> _fetchChannels() async {
    try {
      final fetchedChannels = await _apiService.fetchChannels();
      if (!mounted) return;

      setState(() {
        channelsNotifier.value = fetchedChannels;
        if (channelsNotifier.value.isNotEmpty) {
          if (channelIndex == -1) {
            // SET CHANNELINDEX TO 0
            channelIndex = 0;
          } else if (channelIndex >= channelsNotifier.value.length) {
            // ADJUST CHANNELINDEX
            channelIndex = channelsNotifier.value.length - 1;
          }
        } else {
          // NO CHANNELS AVAILABLE
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

    // REMEMBER LAST CONNECTED CHANNEL
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

  void _connect([String? channelName]) {
    if (isConnected || _microphonePermissionDenied) return;
    if (!_serverOnline) {
      _showSnackBar('Attempting to connect, but the server appears to be offline.');
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

  Future<void> _createChannel(String channelName) async {
    if (!_serverOnline) {
      _showSnackBar('Cannot create channel: Server is offline.');
      return;
    }
    bool success = await _apiService.createChannel(channelName);
    if (success) {
      await _fetchChannels();
      if (!mounted) return;

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
      if (mounted) Navigator.of(context).pop();
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
      if (!mounted) return;

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

      setState(() {
        channelIndex = newIndex;
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('lastChannel', channelName);

      if (isConnected) {
        _apiService.switchChannel(channelName);
      }

      if (mounted) {
        _showSnackBar('Joined channel "$channelName".');
        Navigator.of(context).pop();
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
          // LEFT CURRENT CHANNEL
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
            // SWITCH TO FIRST AVAILABLE CHANNEL
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
          // LEFT A DIFFERENT CHANNEL
          int newIndex = channelsNotifier.value
              .indexWhere((channel) => channel['name'] == currentChannelName);
          if (newIndex != -1) {
            setState(() {
              channelIndex = newIndex;
            });
          } else {
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
          _showSnackBar('Left channel "${channelName.toUpperCase()}".');
        }
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
          // DELETED CURRENT CHANNEL
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

  // ============================================================================
  //                                    UI METHODS
  // ============================================================================
  // UI INTERACTIONS AND DIALOGS.

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
      // NO NEED TO RECONNECT
    }
  }

  void _showSnackBar(String message) {
    // REMOVE EXISTING BANNER
    ScaffoldMessenger.of(context).removeCurrentMaterialBanner();

    // CREATE NEW BANNER
    final materialBanner = MaterialBanner(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: Colors.black87,
      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text(
            'DISMISS',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );

    // SHOW BANNER
    ScaffoldMessenger.of(context)
      ..clearMaterialBanners()
      ..showMaterialBanner(materialBanner);

    // AUTO DISMISS AFTER 3 SECONDS
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    });
  }

  void _showChannelOptionsDialog() {
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
                  Navigator.of(context).pop();
                  _showCreateChannelDialog();
                },
              ),
              _DialogOption(
                icon: Icons.login,
                text: 'Join Channel',
                onTap: () {
                  Navigator.of(context).pop();
                  _showJoinChannelDialog();
                },
              ),
              _DialogOption(
                icon: Icons.list,
                text: 'Manage Channels',
                onTap: () {
                  Navigator.of(context).pop();
                  _showManageChannelsDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                _DialogButton(
                  icon: Icons.arrow_back,
                  onTap: () {
                    Navigator.of(context).pop();
                    _showChannelOptionsDialog();
                  },
                ),
                const SizedBox(width: 10),
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
      iconVerticalOffset: 1.0,
    );
  }

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
                _DialogButton(
                  icon: Icons.arrow_back,
                  onTap: () {
                    Navigator.of(context).pop();
                    _showChannelOptionsDialog();
                  },
                ),
                const SizedBox(width: 10),
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
      iconVerticalOffset: 1.0,
    );
  }

  void _showManageChannelsDialog() {
    _showCustomDialog(
      title: 'Manage Channels',
      icon: Icons.list,
      content: ValueListenableBuilder<List<dynamic>>(
        valueListenable: channelsNotifier,
        builder: (context, channelsList, _) {
          List<dynamic> userChannels = channelsList.where((channel) {
            return channel['creatorId'] == _apiService.userId ||
                (channel['members'] != null && channel['members'].contains(_apiService.userId));
          }).toList();

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
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
                              Navigator.of(context).pop();
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
                        _showChannelOptionsDialog();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      iconVerticalOffset: 1.0,
    );
  }

  void _showCustomDialog({
    required String title,
    required IconData icon,
    required Widget content,
    List<Widget>? actions,
    double iconVerticalOffset = 0.0,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _CustomDialog(
          title: title,
          icon: icon,
          content: content,
          actions: actions,
          iconVerticalOffset: iconVerticalOffset,
        );
      },
    );
  }

  // ============================================================================
  //                                   DISPOSE METHOD
  // ============================================================================
  // CLEANUP RESOURCES WHEN THE WIDGET IS DISPOSED.

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

  // ============================================================================
  //                                    BUILD METHOD
  // ============================================================================
  // BUILD THE WIDGET TREE.

  @override
  Widget build(BuildContext context) {
    // SHOW SNACKBAR IF MICROPHONE PERMISSION IS DENIED
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
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // CONNECTIVITY CARD
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
                // PUSH-TO-TALK BUTTON
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
  final double iconVerticalOffset;

  const _CustomDialog({
    required this.title,
    required this.icon,
    required this.content,
    this.actions,
    this.iconVerticalOffset = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    const TextStyle textStyle = TextStyle(
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, iconVerticalOffset),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: textStyle,
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
  final double iconVerticalOffset;

  const _DialogOption({
    required this.icon,
    required this.text,
    required this.onTap,
    // ignore: unused_element
    this.iconVerticalOffset = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    const TextStyle textStyle = TextStyle(
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, iconVerticalOffset),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: textStyle,
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
    // ignore: unused_element
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
            color: Color.fromARGB(202, 255, 255, 255), shape: BoxShape.circle),
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          icon,
          color: Colors.black,
          size: 25.0,
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
    const TextStyle textStyle = TextStyle(
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
                style: textStyle,
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
