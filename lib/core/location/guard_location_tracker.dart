/// Common surface for the guard's background-location backend, so the shift
/// controller talks to one seam regardless of what is behind it.
///
/// Single implementation: `GeolocatorLocationService` — free `geolocator` +
/// Android foreground service. Covers backgrounded, **not** force-killed or
/// rebooted; on the dedicated A70 fleet (one managed model, battery
/// optimisation disabled at provisioning) that is the whole requirement.
///
/// The paid Transistorsoft backend (the only one that survives app-kill) was
/// removed along with `flutter_background_geolocation`: its v5 licence is
/// required on BOTH platforms, was never purchased, and the unlicensed SDK put
/// a "LICENSE VALIDATION FAILURE" banner in front of every release build while
/// contributing nothing — the free stack had already taken over tracking.
/// Restoring it means buying the licence, not just re-adding the dependency.
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
