import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Готовые адреса бэкенда.
enum BackendPreset {
  prod('Прод', 'safe-city-back-7c8ed50edd7d.herokuapp.com'),
  test('Тест', 'safe-city-back-test-d2f8b35b15f0.herokuapp.com');

  const BackendPreset(this.label, this.host);

  final String label;
  final String host;
}

/// Какой бэкенд слушает приложение.
///
/// Переключатель адреса удобен на тестировании и опасен в сторе, поэтому
/// правила намеренно жёсткие:
///
///  * **Release без флага — всегда прод.** Сохранённый выбор в этом случае
///    даже не читается, так что сборка для App Store не может уехать на
///    staging, чем бы её ни кормили из SharedPreferences.
///  * **Меню видно** в debug/profile всегда, в release — только с
///    `--dart-define=SAFECITY_DEV_MENU=true` (сборка для внутреннего
///    тестирования / TestFlight).
///  * **`--dart-define=SAFECITY_API_HOST=...` прибивает хост намертво** и
///    выигрывает у выбора в приложении — так CI и скрипты получают заведомо
///    предсказуемый билд; в UI такой адрес показывается только для чтения.
class BackendEnv {
  BackendEnv._();

  static const String _prefsKey = 'backend_host';

  static const String _pinnedHost = String.fromEnvironment('SAFECITY_API_HOST');
  static const bool _devMenu = bool.fromEnvironment('SAFECITY_DEV_MENU');

  /// Показывать ли раздел выбора сервера в настройках.
  static bool get isVisible => kDebugMode || _devMenu;

  /// Адрес задан флагом сборки — из приложения его не поменять.
  static bool get isPinned => _pinnedHost.isNotEmpty;

  /// Можно ли менять адрес из приложения.
  static bool get isEditable => isVisible && !isPinned;

  static String _host = BackendPreset.prod.host;

  /// Текущий хост без схемы: `safe-city-back-…herokuapp.com`.
  static String get host => isPinned ? normalizeHost(_pinnedHost) : _host;

  /// Пресет, если адрес совпал с одним из них; иначе null — «свой адрес».
  static BackendPreset? get preset {
    for (final p in BackendPreset.values) {
      if (p.host == host) return p;
    }
    return null;
  }

  static String get label => preset?.label ?? 'Свой адрес';

  /// Локальные адреса (эмулятор, LAN) ходят по http/ws, остальные — по TLS.
  static bool get _isLocal =>
      host.startsWith('localhost') ||
      host.startsWith('127.') ||
      host.startsWith('10.0.2.2') ||
      host.startsWith('192.168.');

  static String get apiBaseUrl =>
      '${_isLocal ? 'http' : 'https'}://$host/api/v1';

  static String get wsBaseUrl => '${_isLocal ? 'ws' : 'wss'}://$host/api/v1';

  /// Читает сохранённый выбор. Вызывать в `main()` ДО первого сетевого вызова:
  /// Dio создаётся лениво и запоминает baseUrl в момент создания.
  static Future<void> load() async {
    if (!isEditable) return; // прибито флагом либо release без dev-меню
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) _host = saved;
  }

  /// Сохраняет новый адрес и возвращает его нормализованный вид.
  static Future<String> select(String rawHost) async {
    final next = normalizeHost(rawHost);
    if (!isEditable || next.isEmpty) return host;
    _host = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next);
    return next;
  }

  /// Приводит что угодно (`https://foo.com/api/v1/`, `foo.com`) к голому хосту.
  static String normalizeHost(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'\s'), '');
    value = value.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    return value.split('/').first;
  }
}
