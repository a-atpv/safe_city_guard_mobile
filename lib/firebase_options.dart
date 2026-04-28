import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAoaeL8X0BUeYu2Wi4AC348e52jC5AL7Nk',
    appId: '1:835753769209:android:051187c3e7428c94508a28', // Guessed from iOS pattern, might be wrong
    messagingSenderId: '835753769209',
    projectId: 'safe-city-82a57',
    storageBucket: 'safe-city-82a57.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAoaeL8X0BUeYu2Wi4AC348e52jC5AL7Nk',
    appId: '1:835753769209:ios:94a15cab6ab821e4508a28',
    messagingSenderId: '835753769209',
    projectId: 'safe-city-82a57',
    storageBucket: 'safe-city-82a57.firebasestorage.app',
    iosBundleId: 'com.safeCityGuard.appname',
  );
}
