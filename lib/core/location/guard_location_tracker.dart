/// Common surface for the guard's background-location backends, so the shift
/// controller can switch between them in a single line.
///
/// Implementations:
///  - `LocationService`           — Transistorsoft flutter_background_geolocation
///    (paid Android license; survives full app-kill).
///  - `GeolocatorLocationService` — free `geolocator` + Android foreground service
///    (backgrounded-only; on trial for the dedicated Samsung A70 fleet).
abstract interface class GuardLocationTracker {
  /// Start (or resume) background tracking for an on-duty guard.
  Future<void> start();

  /// Stop background tracking (guard went off-shift).
  Future<void> stop();
}
