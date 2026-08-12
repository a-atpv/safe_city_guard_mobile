import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

/// FCM payload `type` values that mean "an SOS needs a guard right now".
const Set<String> kSosPushTypes = {'call_offer', 'new_emergency_broadcast'};

/// Call states that mean nobody needs to respond any more, so a siren that is
/// still going should shut up.
const Set<String> kTerminalCallStatuses = {
  'completed',
  'cancelled_by_user',
  'cancelled_by_system',
};

/// The looping emergency siren.
///
/// The sound itself is a two-tone police "pin-pon": 1160/870 Hz alternating
/// every 0.6 s, four cycles to a 4.8 s seamless loop. It is synthesised, not
/// recorded — `scripts/make_sos_siren.py` regenerates all three copies
/// (`res/raw`, `assets/sounds`, `ios/Runner`) and explains the frequencies.
/// Swapping the file contents needs no channel bump: the channel stores the
/// sound by name, `android.resource://<pkg>/raw/sos_siren`.
///
/// Two delivery paths, because the app has to scream in states where a Dart
/// isolate cannot be trusted to stay alive:
///
///  * [showNotification] — an alarm-category notification carrying
///    `FLAG_INSISTENT`, so **Android itself** loops `res/raw/sos_siren.mp3` on
///    the alarm stream until the notification is cancelled. This is the
///    background/terminated path: the FCM background isolate only has to live
///    long enough to post it, after that the system keeps the siren going.
///  * [startInApp] — the same siren played by the app while it is on screen,
///    so the offer sheet does not get a heads-up notification stacked on top
///    of it.
///
/// Both stop through [stop].
class SosSiren {
  SosSiren._();

  /// Channel settings are frozen when the channel is first created, so this id
  /// carries a version suffix: bump it whenever the sound, importance or audio
  /// usage below changes, otherwise upgraded installs keep the old settings.
  static const String channelId = 'sos_siren_channel_v1';
  static const String _channelName = 'Экстренные вызовы (сирена)';
  static const String _channelDescription =
      'Сирена при поступлении SOS-вызова. Звучит на уровне будильника.';

  /// Fixed id so a second push replaces the first notification instead of
  /// stacking a second siren on top of it.
  static const int notificationId = 90001;

  /// Path of the bundled siren, used for the in-app playback path.
  static const String _sirenAsset = 'assets/sounds/sos_siren.mp3';

  /// `Notification.FLAG_INSISTENT` — repeat the sound until the notification is
  /// cancelled. Not exposed as a constant by the plugin.
  static final Int32List _flagInsistent = Int32List.fromList(<int>[4]);

  static final Int64List _vibrationPattern =
      Int64List.fromList(<int>[0, 700, 400, 700, 400, 700]);

  /// The offer is re-broadcast to other guards after 60 s (see the backend's
  /// dispatch escalation), so a siren nobody reacted to silences itself then
  /// instead of ringing forever in a pocket.
  static const int _autoSilenceMs = 60000;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _channelReady = false;
  static bool _inAppPlaying = false;

  /// Creates the siren channel. Idempotent, and safe to call from the FCM
  /// background isolate (which starts with a fresh, uninitialised plugin).
  static Future<void> ensureChannel() async {
    if (_channelReady || !Platform.isAndroid) {
      _channelReady = true;
      return;
    }
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('sos_siren'),
      // Alarm usage routes the siren to the alarm stream: it is audible with the
      // ringer silenced and at alarm volume rather than notification volume.
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      enableLights: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _channelReady = true;
  }

  /// Binds the plugin inside the FCM background isolate, which starts with a
  /// fresh, uninitialised copy of it.
  static Future<void> _initializePluginForBackgroundIsolate() async {
    const InitializationSettings initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(initSettings);
  }

  /// Posts the looping siren notification. Works from the background isolate:
  /// pass [initializePlugin] there so the plugin is bound before showing.
  static Future<void> showNotification({
    required String title,
    required String body,
    required String payload,
    bool initializePlugin = false,
  }) async {
    try {
      if (initializePlugin) {
        await _initializePluginForBackgroundIsolate();
      }
      await ensureChannel();

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        // Wakes the screen and shows the app over the lock screen when the
        // device is idle; falls back to a heads-up banner when it is in use.
        fullScreenIntent: true,
        sound: const RawResourceAndroidNotificationSound('sos_siren'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        vibrationPattern: _vibrationPattern,
        enableVibration: true,
        enableLights: true,
        // Loop the siren until the notification goes away.
        additionalFlags: _flagInsistent,
        // Not swipeable — the guard has to tap it (which opens the offer).
        ongoing: true,
        autoCancel: true,
        timeoutAfter: _autoSilenceMs,
        visibility: NotificationVisibility.public,
        ticker: title,
      );

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'sos_siren.caf',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      await _plugin.show(
        notificationId,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: payload,
      );
    } catch (e) {
      log('SosSiren: failed to show siren notification: $e');
    }
  }

  /// Plays the siren inside the app (offer sheet on screen). Looping playback
  /// on the alarm stream, plus a repeating vibration.
  static Future<void> startInApp() async {
    if (_inAppPlaying) return;
    _inAppPlaying = true;
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // repeat: 0 restarts the pattern from index 0 — vibrates until cancelled.
        Vibration.vibrate(pattern: <int>[0, 700, 400, 700, 400, 700], repeat: 0);
      }
    } catch (e) {
      log('SosSiren: vibration failed: $e');
    }

    try {
      // `fromAsset`, а НЕ `fromFile`. В flutter_ringtone_player 4.0.0+4 первая
      // же строка play() — `if (fromAsset == null && android == null && ios ==
      // null) throw "Please specify the sound source."`, и fromFile в этой
      // проверке не упомянут. Вызов, где задан только fromFile, всегда падает,
      // не доходя до ветки, которая его обрабатывает; catch ниже глушил это
      // исключение и уводил на системный будильник — именно его и слышали
      // вместо сирены. Проверено тестом sos_siren_playback_test.dart.
      //
      // Дописать сюда android:/ios: «на всякий случай» нельзя: нативная часть
      // перезаписывает uri системным звуком, если пришёл аргумент android
      // ("The androidSound overrides fromAsset if exists").
      await FlutterRingtonePlayer().play(
        fromAsset: _sirenAsset,
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
      return;
    } catch (e) {
      log('SosSiren: bundled siren playback failed: $e');
    }

    // Последнее средство — штатный будильник телефона. Звучит не как сирена, и
    // это осознанный компромисс: тревога не тем тоном лучше, чем тишина.
    try {
      await FlutterRingtonePlayer().playAlarm(volume: 1.0, looping: true);
      log('SosSiren: сирена не проигралась, звучит системный будильник');
    } catch (e) {
      log('SosSiren: system alarm playback failed: $e');
    }
  }

  /// Silences everything: in-app playback, vibration and the siren notification.
  static Future<void> stop() async {
    _inAppPlaying = false;
    try {
      await FlutterRingtonePlayer().stop();
    } catch (e) {
      log('SosSiren: stop playback failed: $e');
    }
    try {
      Vibration.cancel();
    } catch (e) {
      log('SosSiren: cancel vibration failed: $e');
    }
    await cancelNotification();
  }

  /// Cancels only the siren notification (the system stops looping the sound).
  /// Pass [initializePlugin] when calling from the FCM background isolate.
  static Future<void> cancelNotification({bool initializePlugin = false}) async {
    try {
      if (initializePlugin) {
        await _initializePluginForBackgroundIsolate();
      }
      await _plugin.cancel(notificationId);
    } catch (e) {
      log('SosSiren: cancel notification failed: $e');
    }
  }

}
