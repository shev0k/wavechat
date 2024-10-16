const express = require('express');
const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

const app = express();
const port = 8080;

// Middleware to parse JSON bodies for HTTP requests
app.use(express.json());

// Create an HTTP server and WebSocket server on top of it
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Store clients per channel and audio messages in memory
const channels = {};
const channelMessages = {};

// Directory to save audio files
const AUDIO_DIRECTORY = path.join(__dirname, 'audio_files');
if (!fs.existsSync(AUDIO_DIRECTORY)) {
  fs.mkdirSync(AUDIO_DIRECTORY);
}

// Function to save audio file
function saveAudioFile(channel, audioData) {
  const fileName = `audio_${channel}_${Date.now()}.pcm`;
  const filePath = path.join(AUDIO_DIRECTORY, fileName);
  fs.writeFileSync(filePath, audioData);
  return fileName;
}

// WebSocket connection for live audio streaming
wss.on('connection', (ws, req) => {
  const channel = req.url.split('/').pop(); // Extract channel from URL

  if (!channels[channel]) {
    channels[channel] = new Set();
  }
  channels[channel].add(ws);
  console.log(`Client connected to channel: ${channel}`);

  ws.on('message', (data) => {
    const fileName = saveAudioFile(channel, data);

    // Store the message in memory
    if (!channelMessages[channel]) {
      channelMessages[channel] = [];
    }
    channelMessages[channel].push({
      filename: fileName,
      timestamp: new Date(),
    });

    // Broadcast audio to all clients in the channel except the sender
    channels[channel].forEach((client) => {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  });

  ws.on('close', () => {
    channels[channel].delete(ws);
    if (channels[channel].size === 0) {
      delete channels[channel];
    }
    console.log(`Client disconnected from channel: ${channel}`);
  });

  ws.on('error', (error) => {
    console.error(`Error on channel ${channel}:`, error);
  });
});

// POST endpoint to upload audio messages
app.post('/channel/:channel/messages', (req, res) => {
  const { channel } = req.params;
  const { sender, audioData } = req.body;

  if (!audioData) {
    return res.status(400).json({ status: 'error', message: 'Missing audio data' });
  }

  // Save the audio file
  const buffer = Buffer.from(audioData, 'base64');
  const fileName = saveAudioFile(channel, buffer);

  // Store the message in memory
  if (!channelMessages[channel]) {
    channelMessages[channel] = [];
  }
  channelMessages[channel].push({
    sender,
    filename: fileName,
    timestamp: new Date(),
  });

  res.status(201).json({
    status: 'success',
    filename: fileName,
    channel,
  });
});

// GET endpoint to retrieve all audio messages for a channel
app.get('/channel/:channel/messages', (req, res) => {
  const { channel } = req.params;

  if (!channelMessages[channel]) {
    return res.status(404).json({ status: 'error', message: 'No messages found' });
  }

  res.status(200).json({
    status: 'success',
    audioMessages: channelMessages[channel],
  });
});

// Start the server
server.listen(port, '0.0.0.0', () => {
  console.log(`Server running and accessible from any IP on the network at port ${port}`);
});
