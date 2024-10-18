// widgets/connectivity_card.dart

import 'package:flutter/material.dart';

class ConnectivityCard extends StatelessWidget {
  final bool isConnected;
  final int channelIndex;
  final List<String> channels;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Function(int) onSwitchChannel;
  final VoidCallback onChannelOptions;

  const ConnectivityCard({
    super.key,
    required this.isConnected,
    required this.channelIndex,
    required this.channels,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSwitchChannel,
    required this.onChannelOptions,
  });

  @override
  Widget build(BuildContext context) {
    String currentChannelName = (channels.isNotEmpty && channelIndex >= 0 && channelIndex < channels.length)
        ? channels[channelIndex]
        : 'No Channels';

    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: const BorderSide(color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Stack(
          children: [
            // Place the icon at the top-right corner
            Positioned(
              top: 0,
              right: 0,
              child: Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
                size: 24,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Connectivity Status Text
                Text(
                  isConnected ? 'ONLINE' : 'OFFLINE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Channel Selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Decrease Channel Button
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: (channels.isNotEmpty && channelIndex >= 0) ? () {
                        onSwitchChannel(-1);
                      } : null,
                    ),
                    const SizedBox(width: 20),
                    // Current Channel
                    Text(
                      currentChannelName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Increase Channel Button
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_drop_up,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: (channels.isNotEmpty && channelIndex >= 0) ? () {
                        onSwitchChannel(1);
                      } : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Turn On/Off Button with Icon
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: ElevatedButton(
                        key: ValueKey(isConnected),
                        onPressed: (channelIndex >= 0) ? (isConnected ? onDisconnect : onConnect) : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(
                            side: BorderSide(color: Colors.white),
                          ),
                          foregroundColor:
                              isConnected ? Colors.black : Colors.white,
                          backgroundColor:
                              isConnected ? Colors.white : Colors.black,
                          padding: const EdgeInsets.all(16.0),
                        ),
                        child: Icon(
                          Icons.power_settings_new,
                          color: isConnected ? Colors.black : Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Settings Button
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: ElevatedButton(
                        key: ValueKey('settings'),
                        onPressed: onChannelOptions,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(
                            side: BorderSide(color: Colors.white),
                          ),
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.all(16.0),
                        ),
                        child: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
