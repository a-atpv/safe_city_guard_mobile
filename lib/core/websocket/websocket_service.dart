import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api_client.dart';
import '../api_constants.dart';
import '../token_storage.dart';

class WebSocketService {
  static const String _baseUrl = ApiConstants.wsGuardUrl;
  
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

    final token = await ApiClient.ensureFreshToken();
    if (token == null) {
      debugPrint('WebSocketService: No token found, cannot connect.');
      _isConnecting = false;
      return;
    }

    final url = '$_baseUrl?token=$token';
    debugPrint('WebSocketService: Connecting to WebSocket...');

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      
      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(true);
      _reconnectDelaySeconds = 2; // Reset on success
      debugPrint('WebSocketService: Connected');

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          debugPrint('WebSocketService: Connection closed');
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('WebSocketService: Connection error: $error');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WebSocketService: Failed to connect: $e');
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void disconnect() {
    debugPrint('WebSocketService: Disconnecting manually');
    _shouldReconnect = false;
    _channel?.sink.close();
    _isConnected = false;
    _connectionController.add(false);
  }

  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      
      // Filter out heartbeat messages
      if (data['type'] == 'ping') {
        debugPrint('WebSocketService: Received heartbeat (ping)');
        return;
      }

      debugPrint('WebSocketService: Received business message: ${data['type']}');
      _messageController.add(data);
    } catch (e) {
      debugPrint('WebSocketService: Error decoding message: $e');
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
    
    if (_shouldReconnect) {
      debugPrint('WebSocketService: Reconnecting in $_reconnectDelaySeconds seconds...');
      
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
    _channel?.sink.close();
    _messageController.close();
    _connectionController.close();
  }
}

// Provider for global access
final webSocketServiceProvider = WebSocketService();
