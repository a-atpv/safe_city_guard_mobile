# safe_city_guard_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Карты: переход на 2ГИС (ветка 2gis)

Приложение переезжает с OSM-стека на 2ГИС. Уже сделано:

- Все карты (обзорная, активный вызов, деталка инцидента) рендерят
  растровые тайлы 2ГИС через flutter_map — конфиг в `lib/core/map_config.dart`.
- Навигация от первого лица (MapLibre) использует ту же подложку 2ГИС.
  Прежний MapTiler-стиль требовал ключ, который так и не был выписан,
  поэтому навигационная карта рендерилась пустой.
- Обратный геокодинг больше не ходит в Nominatim с устройства: адреса отдаёт
  бэкенд (`GET /api/v1/guard/geocode/reverse` — `lib/core/services/reverse_geocoder.dart`),
  где по ключу `DGIS_API_KEY` включается геокодер 2ГИС.
- Маршруты к вызову бэкенд строит через 2GIS Routing API (пробки, русские
  инструкции) с фолбэком на OSRM — приложение изменений не требует.

### Релизная сборка: только через скрипт

Ключ подложки (Raster Tiles API) попадает в приложение только через
`--dart-define`, и собранная без него сборка **выглядит точно так же**: та же
картинка, но запросы идут в бесплатный веб-эндпоинт 2ГИС — не по подписке, не
по лицензии и без гарантии, что тайлы будут отдавать и завтра. Именно так в
TestFlight уехала сборка, у которой карта у охранника оказалась пустым серым
прямоугольником.

Поэтому ключи лежат в `dart_defines.json` (в `.gitignore`, шаблон —
`dart_defines.example.json`), а собирать релиз надо так:

```bash
./scripts/build_release.sh ipa        # iOS для TestFlight/App Store
./scripts/build_release.sh apk        # Android
./scripts/build_release.sh config     # если архив делается из Xcode:
                                      # пишет ключи в ios/Flutter/Generated.xcconfig,
                                      # запускать перед каждым Product → Archive
```

Скрипт отказывается собирать релиз, если `SAFECITY_DGIS_TILES_KEY` не задан.
Сборка без ключа вдобавок пишет предупреждение в лог устройства на старте
(`MapConfig.warnIfUnlicensed`), а если тайлы не приходят, на карте появляется
плашка «Карта не загрузилась. Повторить», и в логе — адрес тайла с причиной
(`lib/core/basemap.dart`).

### Этап 2: нативный 2GIS Mobile SDK

Когда будет получен ключ Mobile SDK (файл `dgissdk.key` из кабинета
https://dev.2gis.com):

1. `pubspec.yaml`: добавить `dgis_mobile_sdk_map: ^13.6.1`.
2. `android/build.gradle.kts`: в `repositories` добавить
   `maven { url = uri("https://artifactory.2gis.dev/sdk-maven-release") }`;
   minSdk — не ниже 23.
3. Положить `dgissdk.key` в `assets/` (каталог уже в pubspec).
4. Инициализация: `import 'package:dgis_mobile_sdk_map/dgis.dart' as sdk;`
   → `final sdkContext = sdk.DGis.initialize();`
5. Переводить экраны по одному, начиная с обзорной карты; последним —
   навигацию (у полного SDK есть свой навигатор).

Замечание: растровые тайлы `tile{s}.maps.2gis.com` — веб-эндпоинт 2ГИС,
не оформленный как публичный API-продукт. Для продакшена нужен договор
с 2ГИС и/или переход на нативный SDK (этап 2). SDK сознательно не
подключён заранее: без ключа он не рендерит ничего, а в APK добавляет
десятки мегабайт нативных библиотек.
