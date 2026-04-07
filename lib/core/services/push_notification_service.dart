import 'dart:developer';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api_client.dart';
import '../token_storage.dart';

/// Top-level function to handle background messages.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log("Handling a background message: ${message.messageId}");
}

class PushNotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final TokenStorage _tokenStorage = TokenStorage();

  Future<void> initialize() async {
    // 1. Initialize Local Notifications
    await _initLocalNotifications();

    // 2. Request permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      log('Guard granted notification permission');
    }

    // 3. Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Foreground message received: ${message.messageId}');
      _showLocalNotification(message);
    });

    // 5. Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log('Notification opened app: ${message.data}');
    });

    // 6. Get/Register the FCM Token
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        log("FCM Token: $token");
        await _registerDeviceToken(token);
      }
    } catch (e) {
      log("Error getting FCM token: $e");
    }

    // 7. Listen for token refreshes
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      log("FCM Token updated: $newToken");
      await _registerDeviceToken(newToken);
    });
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        log('Local notification tapped: ${details.payload}');
      },
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'safe_city_guard_channel',
      'Safe City Guard Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails();

    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformDetails,
      payload: message.data.toString(),
    );
  }

  Future<void> _registerDeviceToken(String token) async {
    try {
      // Check if guard is logged in
      final accessToken = await _tokenStorage.getAccessToken();
      if (accessToken == null) {
        log("Cannot register FCM token: Guard not logged in yet.");
        return;
      }

      final response = await ApiClient.instance.post(
        '/device/register',
        data: {
          'device_token': token,
          'device_type': Platform.isAndroid ? 'android' : 'ios',
          'device_model': 'Guard Mobile Device',
          'app_version': '1.0.0',
        },
      );

      if (response.statusCode == 200) {
        log("FCM Token registered successfully with backend for guard");
      }
    } catch (e) {
      log("Failed to register FCM token for guard with backend: $e");
    }
  }
}
