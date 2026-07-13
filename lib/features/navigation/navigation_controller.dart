import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/websocket/websocket_service.dart';
import '../calls/route_model.dart';
import '../calls/route_service.dart';
import 'nav_geo.dart';
import 'nav_models.dart';
import 'nav_phrases.dart';
import 'navigation_engine.dart';

/// Orchestrates live navigation to a MOVING target (the SOS caller):
///  - seeds the route from the backend (which already routes to the victim's
///    live position), then keeps the victim position fresh from the WS push
///    `user_location_update`;
///  - reroutes when the target drifts past a threshold, or the guard goes
///    off-route — debounced so a jittery victim GPS doesn't thrash the route;
///  - feeds each guard fix through [NavigationEngine] and speaks turn prompts.
///
/// UI binds to the [ValueNotifier]s; all IO lives here, the engine stays pure.
class NavigationController {
  NavigationController({
    required this.callId,
    WebSocketService? ws,
    RouteService? routeService,
  })  : _ws = ws ?? webSocketServiceProvider,
        _routeService = routeService ?? RouteService();

  final int callId;
  final WebSocketService _ws;
  final RouteService _routeService;
  final NavigationEngine _engine = NavigationEngine();
  final FlutterTts _tts = FlutterTts();

  final ValueNotifier<NavState?> state = ValueNotifier(null);
  final ValueNotifier<List<LatLng>> routeLine = ValueNotifier(const []);
  final ValueNotifier<LatLng?> target = ValueNotifier(null);
  final ValueNotifier<LatLng?> guard = ValueNotifier(null);

  StreamSubscription<Position>? _posSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  LatLng? _lastRoutedTarget;
  DateTime? _lastRouteAt;
  bool _rerouting = false;
  DateTime? _offRouteSince;

  // Voice de-dup.
  String? _lastSpokenKey;
  int _lastSpokenBucket = -1;

  // Reroute policy.
  static const _targetMovedM = 40.0;
  static const _minRerouteGap = Duration(seconds: 12);
  static const _offRouteGrace = Duration(seconds: 6);

  Future<void> start() async {
    await _initTts();
    await _fetchRoute(seed: true); // gets victim coords + initial route
    _wsSub = _ws.messageStream.listen(_onWsMessage);
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onGuardFix,
        onError: (e) => debugPrint('NavigationController: pos stream error: $e'));
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {/* TTS is best-effort */}
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'user_location_update') return;
    if (msg['call_id'] != null && msg['call_id'] != callId) return;
    final lat = (msg['latitude'] as num?)?.toDouble();
    final lng = (msg['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final t = LatLng(lat, lng);
    target.value = t;
    _maybeReroute(t);
  }

  void _onGuardFix(Position pos) {
    final g = LatLng(pos.latitude, pos.longitude);
    guard.value = g;
    final t = target.value;
    if (t == null) return;

    final st = _engine.compute(
      guard: g,
      headingDeg: pos.heading, // geolocator: degrees, -1 when unknown
      speedMps: pos.speed < 0 ? 0 : pos.speed,
      target: t,
    );
    state.value = st;
    _speak(st);

    if (st.offRoute) {
      _offRouteSince ??= DateTime.now();
      if (DateTime.now().difference(_offRouteSince!) >= _offRouteGrace) {
        _maybeReroute(t, force: true);
      }
    } else {
      _offRouteSince = null;
    }
  }

  void _maybeReroute(LatLng t, {bool force = false}) {
    if (_rerouting) return;
    final now = DateTime.now();
    final gapOk = _lastRouteAt == null ||
        now.difference(_lastRouteAt!) >= _minRerouteGap;
    final movedEnough = _lastRoutedTarget == null ||
        NavGeo.distanceM(_lastRoutedTarget!, t) > _targetMovedM;
    if (force || (movedEnough && gapOk)) _fetchRoute();
  }

  Future<void> _fetchRoute({bool seed = false}) async {
    if (_rerouting) return;
    _rerouting = true;
    try {
      RouteData? r;
      LatLng? t;
      if (seed || guard.value == null || target.value == null) {
        // Seed: backend routes from the guard's known position to the victim's
        // live position and hands back both.
        final data = await _routeService.getRouteToCall(callId, withSteps: true);
        r = data.route;
        t = LatLng(data.userLatitude, data.userLongitude);
      } else {
        // Reroute: use the guard's *live* device position + the victim's *live*
        // WS position — fresher than the server's last-known coordinates.
        t = target.value!;
        r = await _routeService.calculateRoute(
          originLat: guard.value!.latitude,
          originLng: guard.value!.longitude,
          destLat: t.latitude,
          destLng: t.longitude,
          withSteps: true,
        );
      }
      target.value = t;
      _lastRoutedTarget = t;
      _lastRouteAt = DateTime.now();
      if (r != null && r.coordinates.length >= 2) {
        _engine.setRoute(r);
        routeLine.value = _engine.path;
      }
    } catch (e) {
      debugPrint('NavigationController: route fetch failed: $e');
    } finally {
      _rerouting = false;
    }
  }

  void _speak(NavState st) {
    if (st.mode == NavMode.closeApproach) {
      if (_lastSpokenKey != 'close') {
        _lastSpokenKey = 'close';
        _lastSpokenBucket = -1;
        _say('Цель рядом, ориентируйтесь по стрелке');
      }
      return;
    }
    if (st.mode == NavMode.arrived) {
      if (_lastSpokenKey != 'arrived') {
        _lastSpokenKey = 'arrived';
        _say('Вы на месте');
      }
      return;
    }
    final m = st.nextManeuver;
    if (m == null) return;
    // Announce once at the ~300 m approach and once at the ~60 m commit point.
    final d = st.distanceToManeuverM;
    final bucket = d <= 60 ? 0 : (d <= 300 ? 1 : 2);
    if (bucket == 2) return; // too far to announce yet
    final key = m.alongM.toStringAsFixed(0);
    if (key == _lastSpokenKey && bucket == _lastSpokenBucket) return;
    _lastSpokenKey = key;
    _lastSpokenBucket = bucket;
    final prefix = bucket == 0 ? '' : '${NavPhrases.distancePrefix(d)} ';
    _say('$prefix${m.spokenText}');
  }

  Future<void> _say(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {/* best-effort */}
  }

  Future<void> dispose() async {
    await _posSub?.cancel();
    await _wsSub?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    state.dispose();
    routeLine.dispose();
    target.dispose();
    guard.dispose();
  }
}
