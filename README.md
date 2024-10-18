# WaveChat - Real-Time Voice Messaging App

[**Download the latest APK here**](https://github.com/shev0k/wavechat/releases)

## Overview

**WaveChat** is an instant voice messaging app designed to replicate the simplicity and fun of classic walkie-talkies. It allows users to join dynamic channels, communicate with friends in real-time, and experience a seamless, live audio connection with a sleek, retro-styled interface. Whether you're coordinating in real-time or sharing spontaneous moments, WaveChat ensures instant and immersive communication.

![WaveChat App Preview](https://raw.githubusercontent.com/shev0k/wavechat/refs/heads/Features/images/WaveChatV2.png)

## Key Features

- **Real-Time Voice Communication**: Instantly speak to other users on the same channel with no delay. Press to talk and release to listen, just like a traditional walkie-talkie.
  
- **Dynamic Channel Management**: Create, join, leave, and delete channels on the fly. No longer limited to three channels, WaveChat supports an unlimited number of channels to accommodate your communication needs.

- **Channel-Based Interaction**: Easily switch between multiple channels, ensuring you stay connected with the right group at the right time.

- **Simple, Minimalist Interface**: A sleek, black-and-white interface inspired by retro walkie-talkies keeps the focus on the conversation, with tactile feedback and responsive controls.

- **Hold-to-Talk**: Hold down the hold-to-talk button to broadcast your voice. Let go when done to allow others to speak, ensuring natural, walkie-talkie-style communication.

- **Persistent Channel Selection**: WaveChat remembers your last selected channel, allowing you to seamlessly reconnect without the hassle of reselecting each time.

- **Robust Server Connectivity**: Enhanced handling of server status changes, including automatic reconnection and user notifications when the server goes offline or comes back online.

- **User-Friendly Channel Options**: Access comprehensive channel options through intuitive dialogs, making it easy to manage your communication channels effectively.

![WaveChat App Preview](https://raw.githubusercontent.com/shev0k/wavechat/refs/heads/Features/images/WaveChatV3.png)

## Technology Stack

- **Frontend**: Developed using **Flutter** for smooth cross-platform performance on both iOS and Android devices.
  
- **Backend**: Built on **Node.js** with **WebSocket** technology, enabling low-latency, real-time audio streaming across multiple channels.

- **Audio Streaming**: Powered by **Flutter Sound** for high-quality, real-time voice communication, ensuring that your voice is transmitted with minimal delay.

## Target Audience

- **Primary Users**: Teams, friends, and event organizers who need instant, walkie-talkie-style communication with the flexibility of managing multiple channels.

- **Secondary Users**: Individuals seeking a minimalistic, distraction-free communication app with a retro aesthetic and real-time functionality.

- **Casual Users**: Anyone who enjoys nostalgic experiences and simple, efficient voice messaging.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/shev0k/wavechat.git
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Usage

1. **Launch WaveChat** on your device.
2. **Grant microphone permissions** when prompted to enable voice communication.
3. **Select a channel** from the list of available channels or create a new one.
4. **Press and hold the Hold-to-Talk button** to speak. Release to listen.
5. **Manage your channels** by creating, joining, leaving, or deleting channels through the channel options menu.

## Future Enhancements

- **Additional Customization**: Allow users to customize channels and their interface with personalized themes or notifications.
- **Enhanced Security**: Implement end-to-end encryption for voice messages to ensure secure communication.
- **Advanced User Management**: Introduce roles and permissions within channels for better control and organization.
- **Cross-Platform Support**: Expand support to web and desktop platforms for broader accessibility.


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
