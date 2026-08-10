import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import '../api_constants.dart';
import '../token_storage.dart';
import 'guard_location_tracker.dart';

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
class LocationService implements GuardLocationTracker {
  bool _ready = false;

  /// Token plumbing is registered against the one native SDK in this isolate,
  /// so it is tracked statically — a second LocationService (a rebuilt shift
  /// controller, say) must not double up the listeners. They stay subscribed
  /// for the life of the isolate: tokens rotate between shifts too.
  static bool _tokenListenersRegistered = false;

  /// Access token last handed to the SDK — lets [_pushAuthorizationToSdk] skip
  /// no-op config writes, including the echo of our own write-back.
  static String? _pushedAccessToken;

  /// JWT auth block used by the native HTTP layer. When the 30-minute access
  /// token expires mid-shift, the SDK POSTs [refreshUrl] with [refreshPayload]
  /// and swaps in the new token natively — so uploads keep authenticating even
  /// when the app is terminated and the Dart refresh interceptor isn't running.
  Future<bg.Authorization?> _buildAuthorization() async {
    final accessToken = await TokenStorage().getAccessToken();
    final refreshToken = await TokenStorage().getRefreshToken();
    if (accessToken == null) return null;
    _pushedAccessToken = accessToken;
    return bg.Authorization(
      strategy: bg.Authorization.STRATEGY_JWT,
      accessToken: accessToken,
      refreshToken: refreshToken ?? '',
      // POST /api/v1/guard/auth/refresh  →  {access_token, refresh_token}
      refreshUrl: '${ApiConstants.guardBaseUrl}${ApiConstants.refresh}',
      refreshPayload: const {'refresh_token': '{refreshToken}'},
    );
  }

  /// Hand the Dart-side tokens to the native layer. Called whenever
  /// [TokenStorage] changes, so a renewal done by the Dart interceptor doesn't
  /// leave the SDK holding an older pair.
  Future<void> _pushAuthorizationToSdk() async {
    final accessToken = await TokenStorage().getAccessToken();
    if (accessToken == null || accessToken == _pushedAccessToken) return;
    final authorization = await _buildAuthorization();
    if (authorization == null) return;
    await bg.BackgroundGeolocation.setConfig(bg.Config(authorization: authorization));
    debugPrint('LocationService: pushed renewed tokens to the native layer');
  }

  Future<void> _onSdkAuthorization(bg.AuthorizationEvent event) async {
    if (event.success) {
      // Record it as already-pushed so the TokenStorage change we are about to
      // cause doesn't bounce the same token straight back at the SDK.
      _pushedAccessToken = await _persistSdkTokens(event) ?? _pushedAccessToken;
      return;
    }
    debugPrint(
        'LocationService: native token refresh failed (${event.status}): ${event.error}');
    // The SDK's copy was rejected. Ours may be newer — the Dart interceptor
    // renews on its own 401s — so hand it over instead of declaring the session
    // dead here. If the Dart pair is dead too, the next Dart-side call is what
    // ends the session, on the one code path that owns that decision.
    await _pushAuthorizationToSdk();
  }

  /// Start (or resume) background tracking. Safe to call repeatedly: on later
  /// calls it just refreshes the auth token and re-starts the SDK.
  @override
  Future<bool> start() async {
    final authorization = await _buildAuthorization();
    if (authorization == null) {
      debugPrint('LocationService: no access token — cannot start tracking');
      return false;
    }

    if (!_ready) {
      await bg.BackgroundGeolocation.ready(bg.Config(
        // ── Geolocation ──
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 10.0, // emit a fix every ~10 m of movement
        // ── Application lifecycle ──
        stopOnTerminate: false, // keep tracking after the app is killed
        startOnBoot: true, // resume tracking after a device reboot
        // Headless ON so the heartbeat below still fires a fix when the app is
        // killed — see backgroundGeolocationHeadlessTask, registered in main().
        enableHeadless: true,
        foregroundService: true, // Android persistent notification (required)
        // A guard standing at a post produces no movement, so distanceFilter
        // emits nothing and last_location_update would go stale — dropping them
        // from SOS dispatch. The heartbeat forces a fresh fix on a timer instead.
        // 60 s is the SDK minimum; well inside the backend's 180 s freshness gate.
        heartbeatInterval: 60,
        preventSuspend: true, // iOS: stay awake between heartbeats
        pausesLocationUpdatesAutomatically: false, // iOS: never let the OS pause us
        locationAuthorizationRequest: 'Always', // background tracking needs "Always"
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
        // Paired with the ACTIVITY_RECOGNITION `tools:node="remove"` in AndroidManifest:
        // we don't ship the motion-activity permission (it makes Google Play flag the app
        // as a "health app"), so tell the SDK not to subscribe to Motion API updates.
        // Freshness is covered by the heartbeat above, so we lose nothing that matters.
        disableMotionActivityUpdates: true,
        stopTimeout: 5,
        logLevel: bg.Config.LOG_LEVEL_OFF,
        debug: false,
      ));

      // Keep the two token stores in step, both ways.
      if (!_tokenListenersRegistered) {
        _tokenListenersRegistered = true;
        bg.BackgroundGeolocation.onAuthorization(_onSdkAuthorization);
        TokenStorage.changes.listen((_) => _pushAuthorizationToSdk());
      }

      // Foreground/backgrounded heartbeat (the app-alive counterpart to the
      // headless task): pull a fresh fix so a motionless guard keeps reporting.
      // Registered once, guarded by _ready.
      bg.BackgroundGeolocation.onHeartbeat((event) async {
        try {
          await bg.BackgroundGeolocation.getCurrentPosition(
            samples: 1,
            persist: true, // persist → native autoSync POSTs it to /guard/location
            timeout: 30,
          );
        } catch (e) {
          debugPrint('LocationService: heartbeat fix failed: $e');
        }
      });

      _ready = true;
    } else {
      // Already configured this launch — just refresh the token, which may
      // have rotated since the last shift.
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        authorization: authorization,
      ));
    }

    await bg.BackgroundGeolocation.start();
    return true;
  }

  /// Stop background tracking (guard went off-shift).
  @override
  Future<void> stop() async {
    await bg.BackgroundGeolocation.stop();
  }
}

/// Persist tokens the native layer renewed on its own.
///
/// The SDK refreshes the JWT natively — that is the whole point of
/// [bg.Authorization.STRATEGY_JWT] — and the backend rotates the refresh token
/// on every renew. Without writing the result back, the Dart side sits on a
/// refresh token that stops rotating and dies of old age after
/// REFRESH_TOKEN_EXPIRE_DAYS, signing the guard out while the native layer is
/// still happily uploading fixes. Shared by the app-alive listener and the
/// headless task, since either isolate can be the one that renews.
/// Returns the stored access token, or null when the event carried none.
Future<String?> _persistSdkTokens(bg.AuthorizationEvent event) async {
  final response = event.response;
  final accessToken = response?['access_token'] as String?;
  final refreshToken = response?['refresh_token'] as String?;
  if (accessToken == null || refreshToken == null) {
    debugPrint('LocationService: authorization event without tokens, ignoring');
    return null;
  }
  await TokenStorage().saveTokens(accessToken, refreshToken);
  debugPrint('LocationService: stored tokens renewed by the native layer');
  return accessToken;
}

/// Headless heartbeat handler — runs in its own isolate when the app has been
/// terminated but the shift is still active. Its whole job is to pull one fresh
/// fix on each heartbeat so a motionless, app-killed guard keeps reporting a
/// current position (native autoSync uploads it). The app-alive counterpart is
/// the `onHeartbeat` listener in [LocationService.start].
///
/// Must be a top-level function tagged `@pragma('vm:entry-point')` and registered
/// via `BackgroundGeolocation.registerHeadlessTask` in main() before runApp.
@pragma('vm:entry-point')
void backgroundGeolocationHeadlessTask(bg.HeadlessEvent headlessEvent) async {
  // The app-killed counterpart of LocationService._onSdkAuthorization: a renewal
  // that happens while no Dart UI isolate exists must still reach SharedPreferences,
  // otherwise the guard comes back to a session that expired behind their back.
  if (headlessEvent.name == bg.Event.AUTHORIZATION) {
    final event = headlessEvent.event;
    if (event is bg.AuthorizationEvent && event.success) {
      await _persistSdkTokens(event);
    }
    return;
  }

  if (headlessEvent.name == bg.Event.HEARTBEAT) {
    try {
      await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        timeout: 30,
      );
    } catch (e) {
      debugPrint('LocationService(headless): heartbeat fix failed: $e');
    }
  }
}
