import 'dart:convert';

/// Конфигурация карт. Ветка 2gis: переход с OSM/MapTiler на 2ГИС.
///
/// Слой 1 (работает уже сейчас, без ключа): растровые тайлы 2ГИС. Их рендерят
/// и flutter_map (обзорная карта, активный вызов, деталка инцидента), и
/// MapLibre в первом-лице-навигации — раньше там стоял MapTiler-стиль с так и
/// не заполненным ключом, и навигационная карта рендерилась пустой.
///
/// Подложка берётся из Raster Tiles API по ключу подписки. Ключ подставляется
/// при сборке и в репозиторий не попадает:
///
///   flutter build apk --dart-define=SAFECITY_DGIS_TILES_KEY=<ключ>
///
/// Без ключа собирается прежняя веб-подложка 2ГИС: картинка та же, но запросы
/// не идут в оплаченный пакет (и лицензией не покрыты) — это режим локальной
/// разработки, не для релизных сборок.
class MapConfig {
  /// Ключ Raster Tiles API. Отдельный от серверного (Routing + Geocoder):
  /// этот уезжает внутрь APK, откуда его может достать кто угодно, поэтому
  /// ограничьте его в кабинете 2ГИС по идентификатору приложения.
  static const String _tilesKey =
      String.fromEnvironment('SAFECITY_DGIS_TILES_KEY');

  /// Собрано ли приложение с оплаченной подложкой.
  static bool get hasTilesKey => _tilesKey.isNotEmpty;

  /// Растровые тайлы 2ГИС для flutter_map (web-меркатор, 256 px).
  static final String tileUrlTemplate = hasTilesKey
      ? 'https://tile{s}.maps.2gis.com/v2/tiles/online_sd/{z}/{x}/{y}.png?key=$_tilesKey'
      : 'https://tile{s}.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1.5';

  /// Зеркала тайл-сервера — flutter_map подставляет их в {s}.
  static const List<String> tileSubdomains = ['0', '1', '2', '3'];

  /// Дальше 18-го зума растровых тайлов у 2ГИС нет — на 19-м сервер отвечает
  /// 204 с пустым телом (проверено на боевом ключе), поэтому flutter_map
  /// растягивает 18-й вместо пустых клеток.
  static const int tileMaxNativeZoom = 18;

  /// Обязательная атрибуция подложки.
  static const String attribution = '© 2ГИС';

  /// Для flutter_map SimpleAttributionWidget — он сам добавляет «© ».
  static const String attributionSource = '2ГИС';

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
            tileUrlTemplate.replaceFirst('{s}', s),
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
