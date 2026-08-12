// Почему этот тест существует.
//
// Сирена в открытом приложении играется через flutter_ringtone_player, и в
// версии 4.0.0+4 у его play() есть ловушка: первая же строка —
//
//     if (fromAsset == null && android == null && ios == null)
//       throw "Please specify the sound source.";
//
// fromFile в этой проверке НЕ упомянут. То есть вызов, где задан только
// fromFile, всегда падает — не доходя до ветки, которая fromFile обрабатывает.
// Именно так и было: SosSiren.startInApp() звал play(fromFile: ...), исключение
// глохло в catch, и вместо сирены охранник слышал системный будильник из
// последнего средства.
//
// Тест фиксирует контракт плагина, а не наш код: если однажды обновление
// плагина починит fromFile или, наоборот, сломает fromAsset, красным станет
// здесь, а не на телефоне во время реального вызова.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_test/flutter_test.dart';

const String kSirenAsset = 'assets/sounds/sos_siren.mp3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_ringtone_player'),
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    // Плагин материализует ассет во временный файл, поэтому ему нужен
    // path_provider.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_ringtone_player'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  test('play(fromFile:) падает — так вызывать нельзя, это и была причина будильника',
      () async {
    await expectLater(
      FlutterRingtonePlayer().play(
        fromFile: '/tmp/sos_siren.mp3',
        looping: true,
        volume: 1.0,
        asAlarm: true,
      ),
      throwsA('Please specify the sound source.'),
    );
    expect(calls, isEmpty, reason: 'до нативной части вызов даже не дошёл');
  });

  test('play(fromAsset:) доходит до нативной части и несёт наш файл', () async {
    await FlutterRingtonePlayer().play(
      fromAsset: kSirenAsset,
      looping: true,
      volume: 1.0,
      asAlarm: true,
    );

    expect(calls, hasLength(1));
    final MethodCall call = calls.single;
    expect(call.method, 'play');

    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    expect(args['uri'], contains('sos_siren.mp3'),
        reason: 'играем свою сирену, а не системный звук');
    expect(args['looping'], isTrue, reason: 'сирена должна звучать по кругу');
    expect(args['asAlarm'], isTrue,
        reason: 'поток будильника: слышно при выключенном звонке');
    expect(args['volume'], 1.0);

    // Ключевое: аргумента android быть не должно. Нативная часть перезаписывает
    // uri системным звуком, если он пришёл ("The androidSound overrides
    // fromAsset if exists"), — то есть «подстраховка» android: AndroidSounds
    // .alarm тихо подменила бы сирену тем самым будильником.
    expect(args.containsKey('android'), isFalse);
  });
}
