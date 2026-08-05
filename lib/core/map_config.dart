import 'dart:convert';

/// Конфигурация карт. Ветка 2gis: переход с OSM/MapTiler на 2ГИС.
///
/// Слой 1 (работает уже сейчас, без ключа): растровые тайлы 2ГИС. Их рендерят
/// и flutter_map (обзорная карта, активный вызов, деталка инцидента), и
/// MapLibre в первом-лице-навигации — раньше там стоял MapTiler-стиль с так и
/// не заполненным ключом, и навигационная карта рендерилась пустой.
///
/// ВНИМАНИЕ: tile{s}.maps.2gis.com — это веб-тайлы 2ГИС, а не отдельный
/// публичный API-продукт. Для продакшена нужен ключ/договор с dev.2gis.com
/// и перевод экранов на нативный dgis_mobile_sdk_map (слой 2 перехода);
/// каркас подключения — lib/core/dgis_sdk.dart.
class MapConfig {
  /// Растровые тайлы 2ГИС для flutter_map (web-меркатор, 256 px).
  static const String tileUrlTemplate =
      'https://tile{s}.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1.5';

  /// Зеркала тайл-сервера — flutter_map подставляет их в {s}.
  static const List<String> tileSubdomains = ['0', '1', '2', '3'];

  /// Дальше 18-го зума растровых тайлов у 2ГИС нет — flutter_map
  /// растягивает 18-й вместо пустых клеток.
  static const int tileMaxNativeZoom = 18;

  /// Обязательная атрибуция подложки.
  static const String attribution = '© 2ГИС';

  /// Camera fallback until the first GPS fix (Almaty centre).
  static const double fallbackLat = 43.238949;
  static const double fallbackLng = 76.889709;

  /// Стиль MapLibre для навигации от первого лица: та же растровая подложка
  /// 2ГИС, что и на остальных экранах. `styleString` у MapLibre принимает
  /// и URL, и сырой JSON — здесь JSON, чтобы не тащить ассеты и ключи.
  static final String navStyle = jsonEncode({
    'version': 8,
    'name': 'SafeCity 2GIS raster',
    'sources': {
      'dgis': {
        'type': 'raster',
        'tiles': [
          for (final s in tileSubdomains)
            'https://tile$s.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1.5',
        ],
        'tileSize': 256,
        'maxzoom': tileMaxNativeZoom,
        'attribution': attribution,
      },
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#e8e6e1'},
      },
      {'id': 'dgis', 'type': 'raster', 'source': 'dgis'},
    ],
  });
}
