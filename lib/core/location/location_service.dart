import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import '../api_constants.dart';
import '../token_storage.dart';

/// Background location tracking for on-duty guards.
///
/// Backed by the Transistorsoft background-geolocation SDK so a guard's position
/// keeps reaching the backend even when the app is backgrounded OR killed. The
/// native layer persists each fix to its own store and HTTP-POSTs it to
/// `POST /guard/location` on its own — no live Dart isolate required. That is
/// what lets the dispatcher route an SOS to the guard's *current* whereabouts
/// instead of wherever they happened to be when they last closed the app.
///
/// Platform reality: on Android the foreground service keeps high-resolution
/// updates flowing after task-removal; on iOS a force-quit falls back to
/// Significant-Location-Change (coarser, ~500 m) which relaunches the app in
/// the background — Apple does not permit continuous GPS after force-quit. The
/// backend "location freshness" gate is the safety net for the remaining gaps.
class LocationService {
  bool _ready = false;

  /// JWT auth block used by the native HTTP layer. When the 30-minute access
  /// token expires mid-shift, the SDK POSTs [refreshUrl] with [refreshPayload]
  /// and swaps in the new token natively — so uploads keep authenticating even
  /// when the app is terminated and the Dart refresh interceptor isn't running.
  Future<bg.Authorization?> _buildAuthorization() async {
    final accessToken = await TokenStorage().getAccessToken();
    final refreshToken = await TokenStorage().getRefreshToken();
    if (accessToken == null) return null;
    return bg.Authorization(
      strategy: bg.Authorization.STRATEGY_JWT,
      accessToken: accessToken,
      refreshToken: refreshToken ?? '',
      // POST /api/v1/guard/auth/refresh  →  {access_token, refresh_token}
      refreshUrl: '${ApiConstants.guardBaseUrl}${ApiConstants.refresh}',
      refreshPayload: const {'refresh_token': '{refreshToken}'},
    );
  }

  /// Start (or resume) background tracking. Safe to call repeatedly: on later
  /// calls it just refreshes the auth token and re-starts the SDK.
  Future<void> start() async {
    final authorization = await _buildAuthorization();
    if (authorization == null) {
      debugPrint('LocationService: no access token — cannot start tracking');
      return;
    }

    if (!_ready) {
      await bg.BackgroundGeolocation.ready(bg.Config(
        // ── Geolocation ──
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 10.0, // emit a fix every ~10 m of movement
        // ── Application lifecycle ──
        stopOnTerminate: false, // keep tracking after the app is killed
        startOnBoot: true, // resume tracking after a device reboot
        enableHeadless: false, // native HTTP uploads; no Dart callback needed
        foregroundService: true, // Android persistent notification (required)
        notification: bg.Notification(
          title: 'Safe City — смена активна',
          text: 'Передаём геопозицию для быстрого реагирования на вызовы',
        ),
        // ── HTTP: native upload straight to /guard/location ──
        url: '${ApiConstants.guardBaseUrl}${ApiConstants.location}',
        httpRootProperty: '.', // POST the record as the root JSON object
        locationTemplate:
            '{"latitude":<%= latitude %>,"longitude":<%= longitude %>,"accuracy":<%= accuracy %>}',
        httpTimeout: 10000,
        autoSync: true, // upload as fixes arrive
        autoSyncThreshold: 0, // no batching delay
        batchSync: false, // one location object per request (matches the API)
        maxRecordsToPersist: 100, // cap the offline backlog
        authorization: authorization,
        // ── Misc ──
        stopTimeout: 5,
        logLevel: bg.Config.LOG_LEVEL_OFF,
        debug: false,
      ));
      _ready = true;
    } else {
      // Already configured this launch — just refresh the token, which may
      // have rotated since the last shift.
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        authorization: authorization,
      ));
    }

    await bg.BackgroundGeolocation.start();
  }

  /// Stop background tracking (guard went off-shift).
  Future<void> stop() async {
    await bg.BackgroundGeolocation.stop();
  }
}
