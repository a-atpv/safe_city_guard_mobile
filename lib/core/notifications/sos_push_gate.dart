import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Последний рубеж перед запуском сирены: решает, имеет ли SOS-пуш право
/// звучать *сейчас*, на этом телефоне.
///
/// Нужен, потому что data-пуш может доехать до Dart-кода с опозданием в
/// минуты: приёмник firebase_messaging иногда «паркует» сообщение в LiveData
/// под неактивного наблюдателя, и оно доигрывается при следующем resume
/// активности (2026-08-14: «голая» сирена без шторки уже после завершения
/// вызова — телефон проиграл копию пуша, отправленного ещё до принятия).
/// Сервер такой повтор отфильтровать не может: в момент отправки пуш был
/// легален и протух уже внутри телефона. Поэтому серверные проверки
/// (SOS_PUSH_TTL, статус вызова перед отложенным повтором) дополняются этой,
/// в точке доставки.
///
/// Два независимых вето:
///  * возраст — пуш старше [maxAge] заведомо не «живой» оффер: живой долетает
///    за секунды, а дольше двух минут сервер и сам не шлёт (FCM TTL);
///  * память об обработанных вызовах — id принятого/отклонённого/закрытого
///    вызова запоминается, и его копии больше сирену не поднимают. Хранится в
///    SharedPreferences, потому что у фонового изолята FCM своя память и
///    состояние из основного изолята ему иначе не видно.
///
/// ИНВАРИАНТ: пишет только основной изолят (принятие, отказ и закрытие — всё
/// в UI). Фоновый изолят только читает: его свежий экземпляр prefs читает
/// диск, поэтому reload() не нужен ни там, ни здесь. Начни писать из фонового
/// изолята — основной перестанет видеть эти записи без reload().
class SosPushGate {
  SosPushGate._();

  /// Старше этого — повтор или «парковка», сирене не быть. 90 секунд оставляют
  /// запас и на медленную доставку, и на расхождение часов телефона с FCM.
  static const Duration maxAge = Duration(seconds: 90);

  /// Сколько помнить обработанный вызов. Дольше не нужно: всё, что доехало
  /// позже, отсечётся возрастом, — а вечная память могла бы заглушить
  /// легитимное повторное предложение того же вызова (например, назначенное
  /// админом вручную).
  static const Duration handledTtl = Duration(minutes: 10);

  static const String _handledKey = 'sos_gate_handled_calls_v1';

  /// Запомнить, что вызов обработан на этом телефоне (принят, отклонён или
  /// закрыт) — с этого момента его SOS-пуши глушатся.
  static Future<void> markHandled(String callId, {DateTime? now}) async {
    if (callId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final moment = now ?? DateTime.now();
      final handled = _readHandled(prefs, moment);
      handled[callId] = moment.millisecondsSinceEpoch;
      await prefs.setString(_handledKey, jsonEncode(handled));
    } catch (e) {
      // Не смогли запомнить — хуже не станет: без записи сирена лишний раз
      // прозвучит, а не промолчит.
      debugPrint('SosPushGate: markHandled($callId) failed: $e');
    }
  }

  /// null — сирене быть; иначе строка с причиной, по которой пуш глушится.
  /// Причину печатает вызывающий — по ней случай ищется в logcat.
  static Future<String?> vetoReason({
    required Map<String, dynamic> data,
    required DateTime? sentTime,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();

    // sentTime проставляет сервер FCM, часам телефона он не верит. Нет
    // отметки — проверку пропускаем: лучше лишняя сирена, чем немой вызов.
    if (sentTime != null) {
      final age = moment.difference(sentTime);
      if (age > maxAge) {
        return 'пуш протух (возраст ${age.inSeconds} с > ${maxAge.inSeconds} с)';
      }
    }

    final String callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_readHandled(prefs, moment).containsKey(callId)) {
        return 'вызов $callId уже обработан на этом телефоне';
      }
    } catch (e) {
      debugPrint('SosPushGate: prefs не прочитались, пуш идёт без вето: $e');
    }

    return null;
  }

  /// Карта callId → millisecondsSinceEpoch отметки, уже без протухших записей.
  static Map<String, dynamic> _readHandled(
    SharedPreferences prefs,
    DateTime now,
  ) {
    final raw = prefs.getString(_handledKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
      final cutoff = now.subtract(handledTtl).millisecondsSinceEpoch;
      decoded.removeWhere((_, ts) => ts is! int || ts < cutoff);
      return decoded;
    } catch (_) {
      // Битый JSON — начинаем с чистого листа, это всего лишь кэш.
      return <String, dynamic>{};
    }
  }
}
