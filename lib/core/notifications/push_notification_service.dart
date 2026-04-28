import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';

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
      log('App launched from terminated state via FCM notification');
      _handleNotificationPayload(initialMessage.data);
    }

    // 7.1 Also check for local notification launch details
    final NotificationAppLaunchDetails? launchDetails = 
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null) {
        log('App launched from terminated state via Local Notification');
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _handleNotificationPayload(data);
        } catch (e) {
          log('Error decoding local notification payload: $e');
        }
      }
    }

    _isInitialized = true;
    log('PushNotificationService initialized');
    
    // Proactively get token to ensure we have it
    final token = await getFcmToken();
    if (token != null) {
      _onTokenCallback?.call(token);
    }

    // 8. Listen for token refreshes
    _fcm.onTokenRefresh.listen((newToken) {
      log('Push Notifications: Token refreshed');
      _onTokenCallback?.call(newToken);
    });
  }

  void Function(String token)? _onTokenCallback;

  /// Sets a callback to be called whenever a new FCM token is obtained or refreshed.
  void setOnTokenCallback(void Function(String token) callback) {
    _onTokenCallback = callback;
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
    
    // Use a microtask or future to allow the current frame to complete
    // and wait for the navigator context if it's not yet ready
    _processNavigation(data);
  }

  Future<void> _processNavigation(Map<String, dynamic> data) async {
    // Wait for context to be available (max 10 seconds)
    // This is important for app launches from terminated state
    int attempts = 0;
    while (rootNavigatorKey.currentContext == null && attempts < 20) {
      log('Waiting for rootNavigatorKey.currentContext... attempt ${attempts + 1}');
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }

    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      // If we have a call_id, we might want to go to active-call
      if (data.containsKey('call_id')) {
        final callIdStr = data['call_id'].toString();
        final callId = int.tryParse(callIdStr) ?? 0;
        log('Navigating to /active-call with callId: $callId');
        GoRouter.of(context).push('/active-call', extra: callId);
      } else {
        log('Navigating to /home');
        GoRouter.of(context).go('/home');
      }
    } else {
      log('ERROR: Could not get context for navigation after waiting.');
    }
  }
}
