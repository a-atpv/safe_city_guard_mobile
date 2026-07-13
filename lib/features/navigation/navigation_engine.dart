import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../calls/route_model.dart';
import 'nav_geo.dart';
import 'nav_models.dart';
import 'nav_phrases.dart';

/// The renderer-agnostic navigation brain. Feed it a route + the guard's fix +
/// the (moving) target; it returns a [NavState] describing what to say, what to
/// show, and where to point the camera. No IO, no map, no async — so it's cheap
/// to reason about and trivial to unit-test.
class NavigationEngine {
  List<LatLng> _path = [];
  double _routeLengthM = 0;
  double _routeDurationS = 0;
  List<NavManeuver> _maneuvers = [];

  bool get hasRoute => _path.length >= 2;
  List<LatLng> get path => _path;

  // Tunables.
  static const double offRouteM = 40; // cross-track beyond this ⇒ off route
  static const double closeApproachM = 60; // within this of target ⇒ bearing arrow
  static const double arrivedM = 20;

  void setRoute(RouteData route) {
    _path = route.coordinates
        .where((c) => c.length >= 2)
        .map((c) => LatLng(c[0], c[1])) // backend sends [lat, lng]
        .toList();
    _routeLengthM =
        _path.length >= 2 ? NavGeo.cumulativeDistances(_path).last : 0;
    _routeDurationS = route.durationSeconds;
    _maneuvers = _buildManeuvers(route.steps);
  }

  List<NavManeuver> _buildManeuvers(List<RouteStep> steps) {
    if (_path.isEmpty) return [];
    final out = <NavManeuver>[];
    var along = 0.0;
    for (final s in steps) {
      // OSRM puts the maneuver at the START of its step; the step's distance is
      // travelled afterwards. So each maneuver sits at the running distance.
      final at =
          NavGeo.pointAtDistance(_path, along.clamp(0.0, _routeLengthM).toDouble());
      final ph = NavPhrases.fromOsrm(s.instruction, s.name);
      out.add(NavManeuver(
        bannerText: ph.banner,
        spokenText: ph.spoken,
        roadName: s.name,
        alongM: along,
        at: at,
      ));
      along += s.distanceMeters;
    }
    return out;
  }

  NavState compute({
    required LatLng guard,
    required double headingDeg,
    required double speedMps,
    required LatLng target,
  }) {
    final distToTarget = NavGeo.distanceM(guard, target);

    if (distToTarget <= arrivedM) return _arrived(guard, headingDeg);
    if (!hasRoute || distToTarget <= closeApproachM) {
      return _closeApproach(guard, target, headingDeg, speedMps, distToTarget);
    }

    final snap = NavGeo.snapToPath(_path, guard);
    final remaining =
        (_routeLengthM - snap.alongM).clamp(0.0, _routeLengthM).toDouble();
    final remainingSeconds = _routeLengthM <= 0
        ? 0
        : (_routeDurationS * (remaining / _routeLengthM)).round();

    NavManeuver? next;
    for (final m in _maneuvers) {
      if (m.alongM > snap.alongM + 5) {
        next = m;
        break;
      }
    }
    final distToManeuver = next != null
        ? (next.alongM - snap.alongM).clamp(0.0, remaining).toDouble()
        : remaining;

    // Camera bearing: prefer motion heading; when slow/stationary the heading is
    // noise, so face along the route just ahead of the snapped point.
    final camBearing = (speedMps >= 1.5 && headingDeg >= 0)
        ? headingDeg
        : _routeBearingAhead(snap.alongM);

    return NavState(
      mode: NavMode.routing,
      nextManeuver: next,
      distanceToManeuverM: distToManeuver,
      remainingDistanceM: remaining,
      remainingSeconds: remainingSeconds,
      offRoute: snap.crossTrackM > offRouteM,
      camera: CameraTarget(
        center: snap.point,
        bearing: camBearing,
        zoom: _zoomForSpeed(speedMps),
        tilt: 55,
      ),
    );
  }

  NavState _closeApproach(LatLng guard, LatLng target, double headingDeg,
      double speedMps, double dist) {
    final bearing = NavGeo.bearingDeg(guard, target);
    return NavState(
      mode: NavMode.closeApproach,
      bearingToTargetDeg: bearing,
      distanceToTargetM: dist,
      remainingDistanceM: dist,
      camera: CameraTarget(
        center: guard,
        bearing: (speedMps >= 1.0 && headingDeg >= 0) ? headingDeg : bearing,
        zoom: 18,
        tilt: 30,
      ),
    );
  }

  NavState _arrived(LatLng guard, double headingDeg) => NavState(
        mode: NavMode.arrived,
        distanceToTargetM: 0,
        camera: CameraTarget(
          center: guard,
          bearing: headingDeg < 0 ? 0 : headingDeg,
          zoom: 18,
          tilt: 0,
        ),
      );

  double _routeBearingAhead(double alongM) {
    if (_path.length < 2) return 0;
    final a = NavGeo.pointAtDistance(_path, alongM);
    final b = NavGeo.pointAtDistance(_path, math.min(alongM + 25, _routeLengthM));
    return NavGeo.bearingDeg(a, b);
  }

  double _zoomForSpeed(double speedMps) {
    if (speedMps < 2) return 18; // walking pace
    if (speedMps < 8) return 16.8; // slow city
    if (speedMps < 15) return 16; // city
    return 15.3; // fast road
  }
}
