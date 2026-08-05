import '../api_client.dart';

/// Обратный геокодинг через бэкенд SafeCity (там — 2ГИС с фолбэком на
/// Nominatim, ключ 2ГИС не покидает сервер).
///
/// Раньше каждый экран ходил в Nominatim напрямую с устройства; с переходом
/// на 2ГИС адреса приходят из одного места и совпадают с адресом вызова,
/// который видят диспетчер и ГБР.
class ReverseGeocoder {
  ReverseGeocoder._();

  /// Короткая подпись адреса («Абая 150») или null, когда адрес не найден
  /// или сеть недоступна. Ошибки глотаются: подпись адреса — украшение,
  /// падать из-за неё нельзя.
  static Future<String?> shortAddress(double lat, double lng) async {
    try {
      final resp = await dio.get(
        'geocode/reverse',
        queryParameters: {'lat': lat, 'lon': lng},
      );
      final data = resp.data;
      if (data is! Map || data['found'] != true) return null;

      final address = data['address'];
      if (address is String && address.isNotEmpty) return address;

      final full = data['full_address'];
      if (full is String && full.isNotEmpty) {
        return full.split(',').take(2).join(', ').trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
