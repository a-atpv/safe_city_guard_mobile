import 'dart:convert';

import 'package:flutter/foundation.dart';

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
/// разработки, не для релизных сборок. Проверять это глазами оказалось нельзя:
/// две подложки не отличить на вид, и в TestFlight уехала сборка без ключа —
/// у неё 2ГИС в какой-то момент перестал отдавать тайлы, и карта осталась
/// пустым серым прямоугольником. Поэтому: релиз собирать только через
/// `scripts/build_release.sh` (он подставляет ключ из `dart_defines.json`), а
/// сборка без ключа кричит в лог на старте — см. [warnIfUnlicensed].
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

  /// Обязательная атрибуция подложки. Рисует [MapAttribution] из
  /// `core/basemap.dart`: flutter_map-овский `SimpleAttributionWidget` жёстко
  /// впечатывает перед этим текстом «flutter_map | », и имя библиотеки висело
  /// на карте у охранника.
  static const String attribution = '© 2ГИС';

  /// Уходит в заголовок User-Agent запросов за тайлами — 2ГИС по нему видит,
  /// кто ходит за подложкой. Совпадает с идентификатором приложения.
  static const String userAgentPackageName = 'com.safeCityGuard.appname';

  /// Куда смотрит камера до первой координаты от GPS. Актобе: SOS принимаются
  /// только там, значит и охранники работают там — раньше карта успевала
  /// показать Алматы (здесь) или Астану (экран карты) и уезжала к охраннику
  /// только после фикса.
  static const double fallbackLat = 50.283932;
  static const double fallbackLng = 57.166978;

  /// Ругается в лог, если релизная сборка идёт без ключа подложки. Не бросает
  /// исключение: пустая карта — плохо, но упавшее приложение охранника хуже.
  static void warnIfUnlicensed() {
    if (hasTilesKey || kDebugMode) return;
    debugPrint(
      '[map] СБОРКА БЕЗ КЛЮЧА ПОДЛОЖКИ 2ГИС. Тайлы идут в бесплатный веб-'
      'эндпоинт: подписка не задействована, лицензией это не покрыто, и 2ГИС '
      'вправе перестать их отдавать (карта станет серой). Релиз собирать '
      'через scripts/build_release.sh',
    );
  }

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
