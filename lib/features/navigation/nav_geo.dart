import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Pure geodesic helpers for turn-by-turn navigation. Snap/along maths use an
/// equirectangular local projection centred on the query point — sub-metre at
/// the distances a route follower cares about, and far cheaper than full
/// geodesics on every GPS fix.
class NavGeo {
  static const double _earthRadiusM = 6371000.0;
  static const Distance _distance = Distance();

  /// Great-circle distance in metres.
  static double distanceM(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  /// Initial bearing a→b in degrees, normalised to [0, 360).
  static double bearingDeg(LatLng a, LatLng b) {
    final lat1 = _rad(a.latitude), lat2 = _rad(b.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Cumulative distance (m) from the route start to each vertex.
  static List<double> cumulativeDistances(List<LatLng> path) {
    final out = List<double>.filled(path.length, 0);
    for (var i = 1; i < path.length; i++) {
      out[i] = out[i - 1] + distanceM(path[i - 1], path[i]);
    }
    return out;
  }

  /// Point on [path] at [distanceAlongM] metres from the start (clamped to ends).
  static LatLng pointAtDistance(List<LatLng> path, double distanceAlongM) {
    if (path.isEmpty) throw ArgumentError('empty path');
    if (path.length == 1 || distanceAlongM <= 0) return path.first;
    var remaining = distanceAlongM;
    for (var i = 1; i < path.length; i++) {
      final seg = distanceM(path[i - 1], path[i]);
      if (remaining <= seg || i == path.length - 1) {
        final t = seg == 0 ? 0.0 : (remaining / seg).clamp(0.0, 1.0).toDouble();
        return _lerp(path[i - 1], path[i], t);
      }
      remaining -= seg;
    }
    return path.last;
  }

  /// Snap [p] onto the nearest point of [path], returning cross-track distance
  /// (how far off-route p is) and along-track distance (progress from the start).
  static SnapResult snapToPath(List<LatLng> path, LatLng p) {
    if (path.isEmpty) throw ArgumentError('empty path');
    if (path.length == 1) {
      return SnapResult(
          point: path.first, crossTrackM: distanceM(p, path.first), alongM: 0, segmentIndex: 0);
    }
    // Equirectangular projection to metres, centred on p.
    final kx = _earthRadiusM * math.cos(_rad(p.latitude)); // m per radian lon
    const ky = _earthRadiusM; // m per radian lat
    double px(LatLng c) => _rad(c.longitude) * kx;
    double py(LatLng c) => _rad(c.latitude) * ky;

    final ppx = px(p), ppy = py(p);
    var best = double.infinity, bestT = 0.0, cumBefore = 0.0, runCum = 0.0;
    var bestSeg = 0;
    for (var i = 1; i < path.length; i++) {
      final ax = px(path[i - 1]), ay = py(path[i - 1]);
      final bx = px(path[i]), by = py(path[i]);
      final dx = bx - ax, dy = by - ay;
      final segLen2 = dx * dx + dy * dy;
      final t = segLen2 == 0
          ? 0.0
          : (((ppx - ax) * dx + (ppy - ay) * dy) / segLen2).clamp(0.0, 1.0).toDouble();
      final cx = ax + t * dx, cy = ay + t * dy;
      final d2 = (ppx - cx) * (ppx - cx) + (ppy - cy) * (ppy - cy);
      if (d2 < best) {
        best = d2;
        bestT = t;
        bestSeg = i - 1;
        cumBefore = runCum;
      }
      runCum += distanceM(path[i - 1], path[i]);
    }
    final segMeters = distanceM(path[bestSeg], path[bestSeg + 1]);
    return SnapResult(
      point: _lerp(path[bestSeg], path[bestSeg + 1], bestT),
      crossTrackM: math.sqrt(best),
      alongM: cumBefore + bestT * segMeters,
      segmentIndex: bestSeg,
    );
  }

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;
}

class SnapResult {
  final LatLng point;
  final double crossTrackM; // distance from p to the route
  final double alongM; // distance from route start to the snapped point
  final int segmentIndex;
  const SnapResult({
    required this.point,
    required this.crossTrackM,
    required this.alongM,
    required this.segmentIndex,
  });
}
