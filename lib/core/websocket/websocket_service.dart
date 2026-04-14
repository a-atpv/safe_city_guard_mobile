import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api_client.dart';
import '../api_constants.dart';

class WebSocketService {
  static const String _baseUrl = ApiConstants.wsGuardUrl;
  
  Timer? _heartbeatTimer;
  int _connectionAttempts = 0;
  WebSocketChannel? _channel;
  bool _isConnecting = false;
  bool _shouldReconnect = false;
  int _reconnectDelaySeconds = 2;
  final int _maxReconnectDelaySeconds = 32;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  void connect() async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;
    _shouldReconnect = true;
    _connectionAttempts++;

    // Refresh token proactively if we've failed a few times
    String? token;
    if (_connectionAttempts > 2) {
      debugPrint('WebSocketService: Multiple failures, attempting explicit token refresh...');
      token = await ApiClient.refreshToken();
    } else {
      token = await ApiClient.ensureFreshToken();
    }

    if (token == null) {
      debugPrint('WebSocketService: No token available, cannot connect.');
      _isConnecting = false;
      _handleDisconnect();
      return;
    }

    final url = '$_baseUrl?token=$token';
    debugPrint('WebSocketService: Connecting (Attempt $_connectionAttempts)...');

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      
      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(true);
      _reconnectDelaySeconds = 2; // Reset on success
      _connectionAttempts = 0;
      debugPrint('WebSocketService: Connected successfully');

      _startHeartbeat();

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          debugPrint('WebSocketService: Connection closed by server');
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('WebSocketService: Connection error: $error');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WebSocketService: Exception during connection: $e');
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void disconnect() {
    debugPrint('WebSocketService: Manual disconnect requested');
    _shouldReconnect = false;
    _stopHeartbeat();
    _channel?.sink.close();
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeat() {
    if (_isConnected && _channel != null) {
      try {
        debugPrint('WebSocketService: Sending heartbeat (ping)');
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        debugPrint('WebSocketService: Failed to send heartbeat: $e');
      }
    }
  }

  void _handleMessage(dynamic message) {
    try {
      // Handle potential binary data (not expected here but for robustness)
      if (message is! String) {
        debugPrint('WebSocketService: Received non-string message, ignoring');
        return;
      }

      final Map<String, dynamic> data = jsonDecode(message);
      
      // Filter out heartbeat responses or server-initiated pings
      if (data['type'] == 'ping') {
        debugPrint('WebSocketService: Received heartbeat (ping) from server');
        // Optional: send pong if server expects it
        // _channel?.sink.add(jsonEncode({'type': 'pong'}));
        return;
      }
      
      if (data['type'] == 'pong') {
        debugPrint('WebSocketService: Received heartbeat (pong) response from server');
        return;
      }

      debugPrint('WebSocketService: Business message received: ${data['type']}');
      _messageController.add(data);
    } catch (e) {
      debugPrint('WebSocketService: Error decoding message: $e - Content: $message');
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
    _stopHeartbeat();
    
    if (_shouldReconnect) {
      debugPrint('WebSocketService: Scheduled reconnection in $_reconnectDelaySeconds s');
      
      Future.delayed(Duration(seconds: _reconnectDelaySeconds), () async {
        if (_shouldReconnect) {
          _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(2, _maxReconnectDelaySeconds);
          connect();
        }
      });
    }
  }

  void dispose() {
    _shouldReconnect = false;
    _stopHeartbeat();
    _channel?.sink.close();
    _messageController.close();
    _connectionController.close();
  }
}

// Provider for global access
final webSocketServiceProvider = WebSocketService();
