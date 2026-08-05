import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_city_guard_mobile/core/api_client.dart';
import 'package:safe_city_guard_mobile/core/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a 401 must and must not cost a guard.
///
/// Guards work where coverage drops, and the app renews a 30-minute access
/// token constantly. Treating "couldn't reach the renew endpoint" the same as
/// "the server says your session is over" is what used to throw them back to
/// the login screen mid-shift.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.onFetch);

  final Future<ResponseBody> Function(RequestOptions options) onFetch;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      onFetch(options);
}

ResponseBody _json(Map<String, dynamic> body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<void> logouts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('access_token', 'old-access');
    await prefs.setString('refresh_token', 'old-refresh');

    logouts = [];
    ApiClient.logoutStream.listen(logouts.add);
  });

  /// Lets the broadcast logout event reach its listener before we assert on it.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('unreachable renew endpoint keeps the session', () async {
    ApiClient.instance.httpClientAdapter =
        _FakeAdapter((_) async => _json({'detail': 'Invalid or expired token'}, 401));
    ApiClient.refreshHttpAdapter = _FakeAdapter(
      (options) async => throw DioException.connectionError(
        requestOptions: options,
        reason: 'no coverage',
      ),
    );

    await expectLater(ApiClient.instance.get('me'), throwsA(isA<DioException>()));
    await settle();

    expect(await TokenStorage().getAccessToken(), 'old-access');
    expect(await TokenStorage().getRefreshToken(), 'old-refresh');
    expect(logouts, isEmpty);
  });

  test('renew endpoint answering 5xx keeps the session', () async {
    ApiClient.instance.httpClientAdapter =
        _FakeAdapter((_) async => _json({'detail': 'Invalid or expired token'}, 401));
    ApiClient.refreshHttpAdapter =
        _FakeAdapter((_) async => _json({'detail': 'Bad gateway'}, 502));

    await expectLater(ApiClient.instance.get('me'), throwsA(isA<DioException>()));
    await settle();

    expect(await TokenStorage().getAccessToken(), 'old-access');
    expect(logouts, isEmpty);
  });

  test('refresh token rejected by the server ends the session', () async {
    ApiClient.instance.httpClientAdapter =
        _FakeAdapter((_) async => _json({'detail': 'Invalid or expired token'}, 401));
    ApiClient.refreshHttpAdapter =
        _FakeAdapter((_) async => _json({'detail': 'Invalid refresh token'}, 401));

    await expectLater(ApiClient.instance.get('me'), throwsA(isA<DioException>()));
    await settle();

    expect(await TokenStorage().getAccessToken(), isNull);
    expect(await TokenStorage().getRefreshToken(), isNull);
    expect(logouts, hasLength(1));
  });

  test('"Invalid guard token" is renewed like any other 401, not signed out', () async {
    var mainCalls = 0;
    String? retryAuthHeader;
    ApiClient.instance.httpClientAdapter = _FakeAdapter((options) async {
      mainCalls++;
      if (mainCalls == 1) return _json({'detail': 'Invalid guard token'}, 401);
      retryAuthHeader = options.headers['Authorization'] as String?;
      return _json({'ok': true}, 200);
    });
    ApiClient.refreshHttpAdapter = _FakeAdapter(
      (_) async => _json({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
      }, 200),
    );

    final response = await ApiClient.instance.get('me');
    await settle();

    expect(response.data['ok'], isTrue);
    expect(mainCalls, 2);
    expect(retryAuthHeader, 'Bearer new-access');
    expect(await TokenStorage().getAccessToken(), 'new-access');
    expect(await TokenStorage().getRefreshToken(), 'new-refresh');
    expect(logouts, isEmpty);
  });

  test('a request is retried once, not endlessly', () async {
    var mainCalls = 0;
    ApiClient.instance.httpClientAdapter = _FakeAdapter((_) async {
      mainCalls++;
      return _json({'detail': 'Invalid or expired token'}, 401);
    });
    ApiClient.refreshHttpAdapter = _FakeAdapter(
      (_) async => _json({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
      }, 200),
    );

    await expectLater(ApiClient.instance.get('me'), throwsA(isA<DioException>()));
    await settle();

    expect(mainCalls, 2, reason: 'original request + exactly one retry');
  });

  test('parallel 401s share a single renew', () async {
    var refreshCalls = 0;
    var mainCalls = 0;
    ApiClient.instance.httpClientAdapter = _FakeAdapter((options) async {
      mainCalls++;
      if (options.headers['Authorization'] == 'Bearer new-access') {
        return _json({'ok': true}, 200);
      }
      return _json({'detail': 'Invalid or expired token'}, 401);
    });
    ApiClient.refreshHttpAdapter = _FakeAdapter((_) async {
      refreshCalls++;
      return _json({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
      }, 200);
    });

    final responses = await Future.wait([
      ApiClient.instance.get('me'),
      ApiClient.instance.get('shift/current'),
      ApiClient.instance.get('calls/available'),
    ]);
    await settle();

    expect(responses.every((r) => r.statusCode == 200), isTrue);
    expect(refreshCalls, 1);
    expect(mainCalls, 6, reason: '3 originals + 3 retries');
    expect(logouts, isEmpty);
  });
}
