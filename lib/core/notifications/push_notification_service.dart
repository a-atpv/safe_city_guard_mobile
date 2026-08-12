import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import '../router/app_router.dart';
import 'sos_siren.dart';

/// Top-level function to handle background messages.
/// This must be a top-level function (not inside a class) to work correctly.
///
/// SOS pushes are sent to guards as **data-only** messages (see the backend's
/// `NotificationService._send_sos_push`), so Android does not auto-display
/// them — this handler is what renders the alert, and it renders it on the
/// siren channel. That is the whole point: a data message wakes this isolate
/// even when the app is backgrounded or killed, and the notification it posts
/// carries `FLAG_INSISTENT`, so the system keeps looping the siren on the alarm
/// stream after the isolate is gone.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final Map<String, dynamic> data = message.data;
  final String? type = data['type']?.toString();
  log('Handling a background message: ${message.messageId} (type=$type)');

  if (!kSosPushTypes.contains(type)) {
    // The call is over (user cancelled, someone else closed it) while the app
    // is not running — silence a siren that is still going.
    final String? status = data['status']?.toString().toLowerCase();
    if (status != null && kTerminalCallStatuses.contains(status)) {
      await SosSiren.cancelNotification(initializePlugin: true);
    }
    return;
  }

  // Fresh isolate: Firebase is not bound here yet.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    log('Background handler: Firebase already initialized or failed: $e');
  }

  await SosSiren.showNotification(
    title: data['title']?.toString() ?? '🚨 Экстренный вызов!',
    body: data['body']?.toString() ??
        'Нужна ваша помощь. Откройте приложение и примите вызов.',
    payload: jsonEncode(data),
    initializePlugin: true,
  );
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
      // Раньше здесь стоял `return`, и это стоило охраннику всех вызовов сразу:
      // отказ от показа уведомлений (Android 13+) обрывал инициализацию до
      // регистрации фонового обработчика FCM и до получения токена. А доставка
      // data-сообщений от разрешения POST_NOTIFICATIONS не зависит — запрещён
      // только показ. Продолжаем: токен уедет на бэкенд, SOS-пуш дойдёт, и,
      // пока приложение открыто, сирена всё равно прозвучит.
      log('Push Notifications: Permission DENIED — уведомления показывать '
          'нельзя, сирена в фоне не прозвучит. Инициализацию продолжаем: '
          'доставка data-сообщений от этого разрешения не зависит.');
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

    // 3. Create Android Notification Channels
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'emergency_channel', // id
        'Emergency Alerts', // title
        description: 'This channel is used for emergency calls.', // description
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final AndroidFlutterLocalNotificationsPlugin? android = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await android?.createNotificationChannel(channel);

      // Dedicated looping-siren channel for SOS offers.
      await SosSiren.ensureChannel();

      await _requestAndroidAlertPermissions(android);
    }

    // 4. Set up Background Messenger
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Received foreground message: ${message.notification?.title}');

      final String? type = message.data['type']?.toString();
      if (kSosPushTypes.contains(type)) {
        // App is on screen: play the siren in-app instead of stacking a
        // heads-up notification on top of the incoming-offer sheet.
        SosSiren.startInApp();
        _onSosPushCallback?.call(message.data);
        return;
      }

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

  static const String _fullScreenIntentAskedKey = 'sos_full_screen_intent_asked';

  /// Notifications (Android 13+) and full-screen intents (Android 14+) are both
  /// user-grantable. Without the latter the siren still sounds but the screen is
  /// not woken, so it is worth asking for — once. The plugin sends the guard to
  /// a system settings screen when it is missing, and re-asking on every launch
  /// would trap them in it.
  Future<void> _requestAndroidAlertPermissions(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    try {
      await android.requestNotificationsPermission();

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_fullScreenIntentAskedKey) ?? false) return;
      await prefs.setBool(_fullScreenIntentAskedKey, true);
      final granted = await android.requestFullScreenIntentPermission();
      log('Push Notifications: full-screen intent permission granted=$granted');
    } catch (e) {
      log('Push Notifications: alert permission request failed: $e');
    }
  }

  void Function(String token)? _onTokenCallback;

  /// Sets a callback to be called whenever a new FCM token is obtained or refreshed.
  void setOnTokenCallback(void Function(String token) callback) {
    _onTokenCallback = callback;
  }

  void Function(Map<String, dynamic> data)? _onSosPushCallback;

  /// Called when an SOS push lands while the app is on screen. Lets the call
  /// layer pull the offer over HTTP even if the WebSocket happens to be down.
  void setOnSosPush(void Function(Map<String, dynamic> data) callback) {
    _onSosPushCallback = callback;
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
    // Tapping the siren notification silences it (the system stops looping once
    // it is cancelled); the in-app alert takes over from here.
    SosSiren.stop();
    if (response.payload != null) {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationPayload(data);
    }
  }

  void Function(String status, int callId)? onTerminalStatusReceived;
  Map<String, dynamic>? _pendingTerminalEvent;

  void setOnTerminalStatusReceived(void Function(String status, int callId) callback) {
    onTerminalStatusReceived = callback;
    if (_pendingTerminalEvent != null) {
      final status = _pendingTerminalEvent!['status'] as String;
      final callId = _pendingTerminalEvent!['callId'] as int;
      _pendingTerminalEvent = null;
      Future.delayed(const Duration(milliseconds: 500), () {
        callback(status, callId);
      });
    }
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    log('Handling notification payload: $data');
    
    final status = data['status']?.toString();
    final callIdStr = data['call_id']?.toString();
    
    if (status != null && callIdStr != null) {
      final statusLower = status.toLowerCase();
      if (statusLower == 'completed' ||
          statusLower == 'cancelled_by_user' ||
          statusLower == 'cancelled_by_system') {
        final callId = int.tryParse(callIdStr) ?? 0;
        
        if (onTerminalStatusReceived != null) {
          onTerminalStatusReceived!(statusLower, callId);
        } else {
          _pendingTerminalEvent = {
            'status': statusLower,
            'callId': callId,
          };
        }
        return;
      }
    }
    
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
        final type = data['type']?.toString();
        if (type == 'call_offer' || type == 'new_emergency_broadcast') {
          log('Navigating to /home (Call offer/broadcast notification)');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              GoRouter.of(context).go('/home');
            }
          });
          return;
        }

        final callIdStr = data['call_id'].toString();
        final callId = int.tryParse(callIdStr) ?? 0;
        log('Navigating to /active-call with callId: $callId');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            GoRouter.of(context).push('/active-call', extra: callId);
          }
        });
      } else {
        log('Navigating to /home');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            GoRouter.of(context).go('/home');
          }
        });
      }
    } else {
      log('ERROR: Could not get context for navigation after waiting.');
    }
  }
}
