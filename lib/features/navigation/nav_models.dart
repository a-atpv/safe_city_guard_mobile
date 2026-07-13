import 'package:latlong2/latlong.dart';

enum NavMode {
  /// Following the street route with turn-by-turn guidance.
  routing,

  /// Within a few dozen metres of a moving target — street routing is noise, so
  /// we home in on the live point with a bearing arrow.
  closeApproach,

  /// Effectively on top of the target.
  arrived,
}

/// One turn-by-turn maneuver, derived from an OSRM step + the route polyline.
class NavManeuver {
  final String bannerText; // short label, e.g. "Направо"
  final String spokenText; // full clause for TTS, distance prefix added at speak time
  final String roadName;
  final double alongM; // distance from route start at which this maneuver occurs
  final LatLng at;
  const NavManeuver({
    required this.bannerText,
    required this.spokenText,
    required this.roadName,
    required this.alongM,
    required this.at,
  });
}

/// Where the first-person camera should point this frame.
class CameraTarget {
  final LatLng center;
  final double bearing; // degrees; "up" on screen = direction of travel
  final double zoom;
  final double tilt; // degrees of pitch (0 = top-down, ~55 = first-person)
  const CameraTarget({
    required this.center,
    required this.bearing,
    required this.zoom,
    required this.tilt,
  });
}

/// Immutable snapshot of the navigation state for one GPS fix.
class NavState {
  final NavMode mode;
  final CameraTarget camera;
  final NavManeuver? nextManeuver;
  final double distanceToManeuverM;
  final double remainingDistanceM;
  final int remainingSeconds;
  final bool offRoute;

  /// Populated only in [NavMode.closeApproach]: straight-line bearing/distance to
  /// the live target.
  final double? bearingToTargetDeg;
  final double? distanceToTargetM;

  const NavState({
    required this.mode,
    required this.camera,
    this.nextManeuver,
    this.distanceToManeuverM = 0,
    this.remainingDistanceM = 0,
    this.remainingSeconds = 0,
    this.offRoute = false,
    this.bearingToTargetDeg,
    this.distanceToTargetM,
  });

  String get etaText {
    final m = (remainingSeconds / 60).ceil();
    return m < 60 ? '$m мин' : '${m ~/ 60} ч ${m % 60} мин';
  }

  String get remainingDistanceText {
    if (remainingDistanceM >= 1000) {
      final km = (remainingDistanceM / 100).round() / 10.0;
      return '${km.toString().replaceAll('.', ',')} км';
    }
    return '${(remainingDistanceM / 10).round() * 10} м';
  }
}
