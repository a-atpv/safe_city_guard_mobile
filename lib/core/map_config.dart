/// MapLibre map style for in-app navigation.
///
/// SETUP: replace `YOUR_MAPTILER_KEY` with a MapTiler key (free tier is enough
/// for a trial), or point [styleUrl] at any MapLibre-compatible style — e.g. a
/// self-hosted TileServer-GL, or a Protomaps PMTiles style. Without a valid
/// style the map renders blank.
class MapConfig {
  static const String styleUrl =
      'https://api.maptiler.com/maps/streets-v2/style.json?key=YOUR_MAPTILER_KEY';

  /// Camera fallback until the first GPS fix (Almaty centre).
  static const double fallbackLat = 43.238949;
  static const double fallbackLng = 76.889709;
}
