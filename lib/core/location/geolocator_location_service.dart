import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../api_client.dart';
import '../api_constants.dart';
import 'guard_location_tracker.dart';

/// Free-stack background location tracking for on-duty guards: `geolocator` + an
/// Android foreground service, with NO paid SDK. Drop-in alternative to the
/// Transistorsoft-backed `LocationService`, on trial for the dedicated Samsung
/// A70 fleet (one managed model, guard app only, battery-optimisation disabled
/// at provisioning — the conditions under which a foreground service reliably
/// survives being backgrounded).
///
/// Coverage vs the paid SDK: this keeps reporting while the app is BACKGROUNDED,
/// **not** after a force-kill or reboot. On a single-purpose device that is the
/// whole requirement.
///
/// Two fix sources feed `POST /guard/location` (auth + token-refresh handled by
/// [ApiClient.instance]):
///  1. Movement stream (`getPositionStream` inside the foreground service) — a
///     fix every ~10 m as the guard patrols.
///  2. A 60 s heartbeat (`getCurrentPosition`) — so a guard standing still keeps
///     reporting inside the backend's 180 s freshness gate. Because `distanceFilter`
///     emits nothing when motionless, without this the guard would go stale at a post.
///
/// Retry: [_pending] holds the freshest fix not yet accepted by the backend. Both
/// new fixes and each heartbeat drive [_flush], so a transient upload/connectivity
/// failure self-heals on the next tick. It is latest-wins on purpose — a live
/// tracker must send the *current* position, never replay a stale backlog.
class GeolocatorLocationService implements GuardLocationTracker {
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;
  bool _running = false;

  /// Freshest fix awaiting a successful upload (null once acked). Depth-1 queue.
  Position? _pending;

  static const Duration _heartbeatInterval = Duration(seconds: 60);

  /// Skip fixes coarser than this — the backend rejects >100 m anyway, so there's
  /// no point spending an upload on one. Mirrors `GuardService.MAX_LOCATION_ACCURACY_M`.
  static const double _maxAccuracyM = 100;

  @override
  Future<void> start() async {
    if (_running) return;
    if (!await _ensurePermission()) return;
    _running = true;

    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(
      _onFix,
      onError: (e) => debugPrint('GeolocatorLocationService: stream error: $e'),
    );

    // Heartbeat: stationary reporting + retry. Fires in the isolate the
    // foreground service keeps alive while backgrounded.
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _tick());

    // Emit one fix now so we don't wait up to 60 s / first movement for a fix.
    unawaited(_tick());
  }

  @override
  Future<void> stop() async {
    _running = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _positionSub?.cancel(); // also tears down the foreground service
    _positionSub = null;
    _pending = null;
  }

  /// Ensures location services are on and permission is granted. With the
  /// foreground service, "while in use" is enough for background delivery on
  /// Android; "Always" is still preferred (set in the A70 provisioning checklist).
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('GeolocatorLocationService: location services disabled');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('GeolocatorLocationService: location permission denied ($perm)');
      return false;
    }
    if (perm == LocationPermission.whileInUse) {
      debugPrint('GeolocatorLocationService: only "while in use" granted — '
          'foreground service still covers background, but grant "Always" for headroom');
    }
    return true;
  }

  Future<void> _tick() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      _onFix(pos); // stores as _pending + flushes
    } catch (e) {
      debugPrint('GeolocatorLocationService: heartbeat fix failed: $e');
      unawaited(_flush()); // still retry any pending fix (connectivity may be back)
    }
  }

  void _onFix(Position pos) {
    if (!_running) return;
    if (pos.accuracy > 0 && pos.accuracy > _maxAccuracyM) return; // coarse fix
    _pending = pos; // latest-wins: never replay stale positions
    unawaited(_flush());
  }

  Future<void> _flush() async {
    final pos = _pending;
    if (pos == null) return;
    try {
      await ApiClient.instance.post(ApiConstants.location, data: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      });
      // Only clear if a newer fix hasn't replaced it while we awaited the POST.
      if (identical(_pending, pos)) _pending = null;
    } catch (e) {
      // Keep _pending; the next fix or heartbeat retries the latest position.
      debugPrint('GeolocatorLocationService: upload failed, will retry: $e');
    }
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Foreground service keeps location flowing while backgrounded. Requires
      // battery-optimisation disabled + "never sleeping apps" on the device.
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        forceLocationManager: false, // prefer the fused provider (Play Services)
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Safe City — смена активна',
          notificationText: 'Передаём геопозицию для реагирования на вызовы',
          enableWakeLock: true,
          setOngoing: true, // guard can't swipe the notification away and kill the service
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }
}
