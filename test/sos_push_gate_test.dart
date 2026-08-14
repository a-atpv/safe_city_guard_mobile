// Почему этот тест существует.
//
// 2026-08-14 охранник получил «голую» сирену — без шторки, без вызова — через
// минуты после того, как завершил вызов. Сервер к тому моменту не отправлял
// ничего: телефон проиграл припаркованную в LiveData копию старого пуша,
// доставленную при очередном resume активности. Отфильтровать такое может
// только сам телефон — этим занимается SosPushGate, и тест фиксирует его
// контракт: живому офферу — звучать, трупу — нет.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_city_guard_mobile/core/notifications/sos_push_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 14, 12, 0, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<String?> veto({
    String callId = '1152',
    DateTime? sentTime,
    DateTime? at,
  }) {
    return SosPushGate.vetoReason(
      data: {'call_id': callId, 'type': 'call_offer'},
      sentTime: sentTime,
      now: at ?? now,
    );
  }

  test('свежий пуш по незнакомому вызову — сирене быть', () async {
    expect(
      await veto(sentTime: now.subtract(const Duration(seconds: 3))),
      isNull,
    );
  });

  test('пуш без sentTime проходит — лучше лишняя сирена, чем немой вызов',
      () async {
    expect(await veto(sentTime: null), isNull);
  });

  test('протухший пуш глушится (сценарий парковки от 2026-08-14)', () async {
    final reason =
        await veto(sentTime: now.subtract(const Duration(minutes: 3)));
    expect(reason, contains('протух'));
  });

  test('пуш на границе возраста ещё проходит', () async {
    expect(
      await veto(sentTime: now.subtract(SosPushGate.maxAge)),
      isNull,
    );
  });

  test('обработанный вызов больше не звучит, даже свежим пушем', () async {
    await SosPushGate.markHandled('1152', now: now);
    final reason = await veto(
      sentTime: now.subtract(const Duration(seconds: 2)),
      at: now.add(const Duration(seconds: 5)),
    );
    expect(reason, contains('обработан'));
  });

  test('другой вызов при этом звучит', () async {
    await SosPushGate.markHandled('1152', now: now);
    expect(
      await veto(
        callId: '1153',
        sentTime: now.subtract(const Duration(seconds: 2)),
      ),
      isNull,
    );
  });

  test('память об обработанном вызове истекает через handledTtl', () async {
    await SosPushGate.markHandled('1152', now: now);
    final later = now.add(SosPushGate.handledTtl + const Duration(minutes: 1));
    expect(
      await veto(
        sentTime: later.subtract(const Duration(seconds: 2)),
        at: later,
      ),
      isNull,
    );
  });

  test('битый JSON в prefs не роняет гейт и не глушит вызов', () async {
    SharedPreferences.setMockInitialValues(
        {'sos_gate_handled_calls_v1': '{oops'});
    expect(
      await veto(sentTime: now.subtract(const Duration(seconds: 2))),
      isNull,
    );
  });

  test('markHandled вычищает протухшие записи, а не копит их вечно', () async {
    final old = now.subtract(const Duration(hours: 2));
    SharedPreferences.setMockInitialValues({
      'sos_gate_handled_calls_v1':
          jsonEncode({'900': old.millisecondsSinceEpoch}),
    });
    await SosPushGate.markHandled('1152', now: now);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('sos_gate_handled_calls_v1')!)
        as Map<String, dynamic>;
    expect(stored.containsKey('900'), isFalse);
    expect(stored.containsKey('1152'), isTrue);
  });
}
