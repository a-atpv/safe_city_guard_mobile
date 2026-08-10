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
  ///
  /// Возвращает true, только если трекинг реально запущен. Раньше провал
  /// (выключенный GPS, отобранное разрешение, отсутствующий токен) глотался
  /// молча — охранник числился «На смене», ни один фикс не уходил, и бэкенд
  /// держал его последнюю известную точку любой давности. Именно так вызов из
  /// Астаны получил маршрут из Актобе.
  Future<bool> start();

  /// Stop background tracking (guard went off-shift).
  Future<void> stop();
}
