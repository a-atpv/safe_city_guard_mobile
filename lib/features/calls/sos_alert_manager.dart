import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart';

class SOSAlertManager {
  static Future<void> triggerAlert() async {
    try {
      // Trigger Vibration
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(
          pattern: [500, 200, 500, 200, 500],
          intensities: [128, 255, 128, 255, 128],
        );
      }

      // Trigger Sound
      FlutterRingtonePlayer().play(
        fromAsset: null, // use system if null
        android: AndroidSounds.alarm,
        ios: IosSounds.alarm,
        looping: false,
        volume: 1.0,
        asAlarm: true,
      );
    } catch (e) {
      debugPrint('SOSAlertManager: Failed to trigger alert: $e');
    }
  }

  static void stopAlert() {
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }
}
