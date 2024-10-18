// server.js

const express = require('express');
const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

const app = express();
const port = 8080;

// Middleware to parse JSON bodies for HTTP requests
app.use(express.json());

// Create an HTTP server
const server = http.createServer(app);

// Create WebSocket servers
const wss = new WebSocket.Server({ noServer: true }); // For audio streaming
const notificationWSS = new WebSocket.Server({ noServer: true }); // For notifications

// Store clients per channel and audio messages in memory
const clientsPerChannel = {};
const channelMessages = {};

// Store all connected notification clients
const notificationClients = new Map(); // Map of userId to WebSocket clients

// File path for storing channels
const CHANNELS_FILE = path.join(__dirname, 'channels.json');

// Load channels from file or initialize default channels
let channels = {};
if (fs.existsSync(CHANNELS_FILE)) {
  try {
    const data = fs.readFileSync(CHANNELS_FILE);
    channels = JSON.parse(data);
  } catch (e) {
    console.error('Failed to load channels from file:', e);
    channels = {};
  }
}

// Ensure default channels exist
['Channel 1', 'Channel 2', 'Channel 3'].forEach((channelName) => {
  if (!channels[channelName]) {
    channels[channelName] = {
      name: channelName,
      creatorId: 'system',
      isDefault: true,
      members: null, // accessible to all
    };
  }
});

// Function to save channels to file
function saveChannelsToFile() {
  try {
    fs.writeFileSync(CHANNELS_FILE, JSON.stringify(channels, null, 2));
  } catch (e) {
    console.error('Failed to save channels to file:', e);
  }
}

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

// Handle WebSocket upgrades
server.on('upgrade', (request, socket, head) => {
  const pathname = request.url;

  if (pathname.startsWith('/ws/audio/')) {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  } else if (pathname === '/ws/notifications') {
    notificationWSS.handleUpgrade(request, socket, head, (ws) => {
      notificationWSS.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

// WebSocket connection for live audio streaming
wss.on('connection', (ws, req) => {
  const urlParts = req.url.split('/');
  const channel = decodeURIComponent(urlParts[urlParts.length - 2]); // Extract channel from URL
  const userId = decodeURIComponent(urlParts[urlParts.length - 1]); // Extract userId from URL

  // Check if the user has access to the channel
  const channelData = channels[channel];
  if (!channelData) {
    ws.send(JSON.stringify({ type: 'error', message: 'Channel not found' }));
    ws.close();
    return;
  }

  if (channelData.members && !channelData.members.includes(userId) && channelData.creatorId !== userId) {
    ws.send(JSON.stringify({ type: 'error', message: 'Access denied to channel' }));
    ws.close();
    return;
  }

  if (!clientsPerChannel[channel]) {
    clientsPerChannel[channel] = new Set();
  }
  clientsPerChannel[channel].add(ws);
  console.log(`Client connected to channel: ${channel}`);

  ws.on('message', (data) => {
    if (clientsPerChannel[channel]) {
      // Save audio data
      saveAudioFile(channel, data);

      // Broadcast audio to all clients in the channel except the sender
      clientsPerChannel[channel].forEach((client) => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(data);
        }
      });
    } else {
      // Channel has been deleted; inform the client and close the connection
      ws.send(JSON.stringify({ type: 'error', message: 'Channel has been deleted' }));
      ws.close();
    }
  });

  ws.on('close', () => {
    if (clientsPerChannel[channel]) {
      clientsPerChannel[channel].delete(ws);
      if (clientsPerChannel[channel].size === 0) {
        delete clientsPerChannel[channel];
      }
    }
    console.log(`Client disconnected from channel: ${channel}`);
  });

  ws.on('error', (error) => {
    console.error(`Error on channel ${channel}:`, error);
  });
});

// WebSocket connection for notifications
notificationWSS.on('connection', (ws) => {
  let userId = null;

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      if (data.type === 'register' && data.userId) {
        userId = data.userId;
        notificationClients.set(userId, ws);
        console.log(`User ${userId} registered for notifications`);
      }
    } catch (e) {
      console.error('Error parsing message:', e);
    }
  });

  ws.on('close', () => {
    if (userId) {
      notificationClients.delete(userId);
    }
    console.log('Client disconnected from notification WebSocket');
  });

  ws.on('error', (error) => {
    console.error('Error on notification WebSocket:', error);
  });
});

// CRUD endpoints for channels

// Create a new channel
app.post('/channels', (req, res) => {
  const { channelName, userId } = req.body;

  if (!channelName || !userId) {
    return res.status(400).json({
      status: 'error',
      message: 'Channel name and user ID are required',
    });
  }

  if (channels[channelName]) {
    return res.status(400).json({
      status: 'error',
      message: 'Channel already exists',
    });
  }

  channels[channelName] = {
    name: channelName,
    creatorId: userId,
    isDefault: false,
    members: [userId],
  };

  saveChannelsToFile();

  res.status(201).json({
    status: 'success',
    channelName,
  });
});

// Get the list of channels
app.get('/channels', (req, res) => {
  const userId = req.query.userId;
  if (!userId) {
    return res.status(400).json({
      status: 'error',
      message: 'User ID is required',
    });
  }

  const accessibleChannels = Object.values(channels).filter(channel => {
    if (channel.isDefault) return true;
    if (channel.creatorId === userId) return true;
    if (channel.members && channel.members.includes(userId)) return true;
    return false;
  });

  res.status(200).json({
    status: 'success',
    channels: accessibleChannels,
  });
});

// Delete a channel
app.delete('/channels/:channelName', (req, res) => {
  const { channelName } = req.params;
  const { userId } = req.body;

  const channel = channels[channelName];

  if (!channel) {
    return res.status(404).json({
      status: 'error',
      message: 'Channel not found',
    });
  }

  if (channel.creatorId !== userId) {
    return res.status(403).json({
      status: 'error',
      message: 'Only the creator can delete this channel',
    });
  }

  delete channels[channelName];
  saveChannelsToFile();

  // Notify and close any clients connected to this channel
  if (clientsPerChannel[channelName]) {
    clientsPerChannel[channelName].forEach((client) => {
      client.send(JSON.stringify({
        type: 'channel_deleted',
        channelName: channelName,
      }));
      client.close(); // This will trigger the 'close' event on client side
    });
    delete clientsPerChannel[channelName];
  }

  // Remove messages associated with the channel
  if (channelMessages[channelName]) {
    delete channelMessages[channelName];
  }

  // Notify only the members of the channel about the deletion
  const membersToNotify = new Set();
  if (channel.members) {
    channel.members.forEach((memberId) => {
      membersToNotify.add(memberId);
    });
  }
  // Also include the creator
  membersToNotify.add(channel.creatorId);

  membersToNotify.forEach((memberId) => {
    const client = notificationClients.get(memberId);
    if (client && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({
        type: 'channel_deleted',
        channelName: channelName,
      }));
    }
  });

  res.status(200).json({
    status: 'success',
    message: 'Channel deleted',
  });
});

// Join a channel
app.post('/channels/:channelName/join', (req, res) => {
  const { channelName } = req.params;
  const { userId } = req.body;

  if (!channelName || !userId) {
    return res.status(400).json({
      status: 'error',
      message: 'Channel name and user ID are required',
    });
  }

  const channel = channels[channelName];
  if (!channel) {
    return res.status(404).json({
      status: 'error',
      message: 'Channel not found',
    });
  }

  if (channel.isDefault) {
    return res.status(400).json({
      status: 'error',
      message: 'Cannot join default channels',
    });
  }

  if (!channel.members) {
    channel.members = [];
  }

  if (!channel.members.includes(userId)) {
    channel.members.push(userId);
    saveChannelsToFile();
  }

  res.status(200).json({
    status: 'success',
    message: `Joined channel ${channelName}`,
  });
});

// Leave a channel
app.post('/channels/:channelName/leave', (req, res) => {
  const { channelName } = req.params;
  const { userId } = req.body;

  if (!channelName || !userId) {
    return res.status(400).json({
      status: 'error',
      message: 'Channel name and user ID are required',
    });
  }

  const channel = channels[channelName];
  if (!channel) {
    return res.status(404).json({
      status: 'error',
      message: 'Channel not found',
    });
  }

  if (channel.isDefault) {
    return res.status(400).json({
      status: 'error',
      message: 'Cannot leave default channels',
    });
  }

  if (channel.members && channel.members.includes(userId)) {
    channel.members = channel.members.filter(id => id !== userId);
    saveChannelsToFile();
    res.status(200).json({
      status: 'success',
      message: `Left channel ${channelName}`,
    });
  } else {
    res.status(400).json({
      status: 'error',
      message: 'User is not a member of the channel',
    });
  }
});

// Heartbeat endpoint to check server status
app.get('/heartbeat', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// Start the server
server.listen(port, '0.0.0.0', () => {
  console.log(`Server running and accessible from any IP on the network at port ${port}`);
});
