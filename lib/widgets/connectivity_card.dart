// widgets/connectivity_card.dart
import 'package:flutter/material.dart';

class ConnectivityCard extends StatelessWidget {
  final bool isConnected;
  final int channelIndex;
  final List<String> channels;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Function(int) onSwitchChannel;

  const ConnectivityCard({
    super.key,
    required this.isConnected,
    required this.channelIndex,
    required this.channels,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSwitchChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: const BorderSide(color: Colors.white),
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
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
                      icon: const Text(
                        '▼',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                        ),
                      ),
                      onPressed: () {
                        onSwitchChannel(-1);
                      },
                    ),
                    const SizedBox(width: 20),
                    // Current Channel
                    Text(
                      channels[channelIndex],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Increase Channel Button
                    IconButton(
                      icon: const Text(
                        '▲',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                        ),
                      ),
                      onPressed: () {
                        onSwitchChannel(1);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Turn On/Off Button with Icon, now round
                ElevatedButton(
                  onPressed: isConnected ? onDisconnect : onConnect,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
