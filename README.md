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
