import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart';

/// Top-level function to handle background messages.
/// This must be a top-level function (not inside a class) to work correctly.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log("Handling a background message: ${message.messageId}");
  // For now, we just log. You could also show a local notification here if needed,
  // but FCM usually handles display messages automatically.
}

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Request permissions (especially for iOS)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      log('Push Notifications: Permission DENIED');
      return;
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      log('Push Notifications: Permission PROVISIONAL (quiet)');
    } else {
      log('Push Notifications: Permission GRANTED');
    }

    // 2. Local Notifications Setup (for showing foreground alerts)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 2.5 Configure foreground notification options for iOS
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true, 
      badge: true,
      sound: true,
    );

    // 3. Create Android Notification Channel
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'emergency_channel', // id
        'Emergency Alerts', // title
        description: 'This channel is used for emergency calls.', // description
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // 4. Set up Background Messenger
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Received foreground message: ${message.notification?.title}');
      
      // On iOS, setForegroundNotificationPresentationOptions handles the display
      // On Android, we show a local notification
      if (message.notification != null && Platform.isAndroid) {
        _showLocalNotification(message);
      }
    });

    // 6. Handle notification taps when app is in background but opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log('Notification opened app: ${message.data}');
      _handleNotificationPayload(message.data);
    });

    // 7. Check if the app was launched from a terminated state via a notification
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      log('App launched from terminated state via notification');
      _handleNotificationPayload(initialMessage.data);
    }

    _isInitialized = true;
    log('PushNotificationService initialized');
    
    // Proactively get token to ensure we have it
    await getFcmToken();
  }

  Future<String?> getFcmToken() async {
    try {
      // On iOS, we must wait for the APNS token to be available
      if (Platform.isIOS) {
        log('Push Notifications: Checking APNS status...');
        String? apnsToken = await _fcm.getAPNSToken();
        if (apnsToken == null) {
          log('Push Notifications: APNS token not yet available. Retrying...');
          // Give it a few attempts
          for (int i = 0; i < 5; i++) {
            await Future.delayed(Duration(seconds: 2 * (i + 1)));
            apnsToken = await _fcm.getAPNSToken();
            if (apnsToken != null) break;
            log('Push Notifications: APNS retry ${i + 1} failed...');
          }
        }
        
        if (apnsToken != null) {
          log('Push Notifications: APNS Token Success: $apnsToken');
        } else {
          log('Push Notifications: APNS Token ERROR: Still null after retries. FCM will likely fail.');
        }
      }

      log('Push Notifications: Requesting FCM Token...');
      String? token = await _fcm.getToken();
      if (token != null) {
        log('Push Notifications: FCM Token Success: $token');
      } else {
        log('Push Notifications: FCM Token ERROR: Received null');
      }
      return token;
    } catch (e) {
      log('Push Notifications: FATAL ERROR during token retrieval: $e');
      return null;
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_channel',
            'Emergency Alerts',
            channelDescription: 'This channel is used for emergency calls.',
            icon: android.smallIcon,
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationPayload(data);
    }
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    log('Handling notification payload: $data');
    // To avoid circular dependency if push_notification_service is imported in main.dart:
    // We already have go_router in the project, we could also use that if we had access to the router instance.
    // However, rootNavigatorKey.currentState?.pushNamed(...) is a standard way.
    
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      // If we have a call_id, we might want to go to active-call
      if (data.containsKey('call_id')) {
        final callId = int.tryParse(data['call_id'].toString()) ?? 0;
        GoRouter.of(context).push('/active-call', extra: callId);
      } else {
        GoRouter.of(context).go('/home');
      }
    }
  }
}
