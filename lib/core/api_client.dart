import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'api_constants.dart';
import 'token_storage.dart';

class ApiClient {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.guardBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// Separate Dio for the renew call: no interceptors (no recursion) and a
  /// longer fuse than a normal request — losing the session is far worse than
  /// waiting a few extra seconds on a bad connection.
  static final Dio _refreshDio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.guardBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// Lets tests drive the renew endpoint without a network.
  @visibleForTesting
  static set refreshHttpAdapter(HttpClientAdapter adapter) =>
      _refreshDio.httpClientAdapter = adapter;

  static final StreamController<void> _logoutController = StreamController<void>.broadcast();
  static Stream<void> get logoutStream => _logoutController.stream;

  /// Marks a request that has already been retried once after a renew, so a
  /// server that keeps answering 401 can't spin the interceptor forever.
  static const String _retriedKey = 'auth_retried';

  static bool _isRefreshing = false;
  static Completer<String?>? _refreshCompleter;

  /// Renews the access token. Returns the new token, or null when it couldn't
  /// be renewed.
  ///
  /// Null does NOT mean "signed out". The session is only ended when the server
  /// explicitly rejects our refresh token (401/403) or there is no refresh
  /// token left to try — see [_renew]. Everything else (timeout, no coverage,
  /// dyno restart, 5xx) leaves the tokens in place so the next call can try
  /// again: a guard on a flaky connection must not be thrown back to the login
  /// screen mid-shift.
  static Future<String?> refreshToken() async {
    if (_isRefreshing) {
      log('ApiClient: Already refreshing, waiting for existing completer...');
      return _refreshCompleter?.future;
    }

    log('ApiClient: Starting token refresh process...');
    _isRefreshing = true;
    final completer = Completer<String?>();
    _refreshCompleter = completer;

    String? newAccessToken;
    try {
      newAccessToken = await _renew();
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
      completer.complete(newAccessToken);
    }
    return newAccessToken;
  }

  static Future<String?> _renew() async {
    final refreshToken = await TokenStorage().getRefreshToken();
    if (refreshToken == null) {
      log('ApiClient: No refresh token found in storage.');
      await _endSession();
      return null;
    }

    try {
      log('ApiClient: Calling refresh endpoint: ${ApiConstants.refresh}');
      final response = await _refreshDio.post(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );

      final data = response.data;
      final newAccessToken = data is Map ? data['access_token'] as String? : null;
      final newRefreshToken = data is Map ? data['refresh_token'] as String? : null;

      if (newAccessToken == null || newRefreshToken == null) {
        // 2xx with an unusable body is a server-side glitch, not a dead
        // session — keep what we have and let the next call retry.
        log('ApiClient: Refresh response missing tokens; keeping current session.');
        return null;
      }

      log('ApiClient: Token refresh successful. Saving new tokens.');
      await TokenStorage().saveTokens(newAccessToken, newRefreshToken);
      return newAccessToken;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // The refresh token itself is expired or invalid — this is the only
        // case where the guard genuinely has to log in again.
        log('ApiClient: Refresh token rejected by server ($status). Ending session.');
        await _endSession();
        return null;
      }
      log('ApiClient: Token refresh unavailable (${e.type}, status $status). Keeping session.');
      return null;
    } catch (e) {
      log('ApiClient: Token refresh failed unexpectedly: $e. Keeping session.');
      return null;
    }
  }

  static Future<void> _endSession() async {
    log('ApiClient: Clearing tokens and triggering global logout.');
    await TokenStorage().clearTokens();
    _logoutController.add(null);
  }

  /// Proactively ensures a fresh token is available.
  /// For now, it returns the current token if available.
  /// Potential future improvement: decode JWT and refresh if close to expiry.
  static Future<String?> ensureFreshToken() async {
    final token = await TokenStorage().getAccessToken();
    return token;
  }

  /// True for the responses that mean "this access token isn't good enough":
  /// 401 from our own deps, plus FastAPI's 403 "Not authenticated" when the
  /// Authorization header never made it onto the request. Every other 403 is a
  /// permission/state answer (inactive guard, owner-only route) and must not
  /// touch the session.
  static bool _isAuthFailure(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return true;
    if (status != 403) return false;
    final data = e.response?.data;
    final detail = data is Map ? (data['detail'] ?? '').toString() : '';
    return detail.toLowerCase().contains('authenticated');
  }

  static bool _interceptorsAdded = false;

  static Dio get instance {
    if (!_interceptorsAdded) {
      _interceptorsAdded = true;

      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = await TokenStorage().getAccessToken();
            if (token != null) {
              log('ApiClient: Adding Authorization header for ${options.uri}');
              options.headers['Authorization'] = 'Bearer $token';
            } else {
              log('ApiClient: No token found in storage for ${options.uri}');
            }
            return handler.next(options);
          },
          onError: (DioException e, handler) async {
            if (!_isAuthFailure(e)) return handler.next(e);
            if (e.requestOptions.extra[_retriedKey] == true) {
              log('ApiClient: Already retried ${e.requestOptions.uri} after a renew.');
              return handler.next(e);
            }

            log('ApiClient: Authentication error on ${e.requestOptions.uri} '
                '(${e.response?.statusCode}). Renewing token.');

            // Any auth failure is worth one renew attempt: whether the token is
            // expired, malformed or simply missing, the refresh token is what
            // decides if the session is still alive.
            final newToken = await refreshToken();
            if (newToken == null) {
              log('ApiClient: Renew did not produce a token. Error propagates.');
              return handler.next(e);
            }

            final opts = e.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            opts.extra[_retriedKey] = true;
            try {
              final retryResponse = await _dio.fetch(opts);
              return handler.resolve(retryResponse);
            } catch (retryError) {
              return handler.next(e);
            }
          },
        ),
      );

      if (kDebugMode) {
        _dio.interceptors.add(LogInterceptor(
          request: true,
          requestHeader: true, // Enabled headers for debugging tokens
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
        ));
      }
    }
    return _dio;
  }

  static String extractError(dynamic e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        // Структурированные ошибки бэкенда ({code, message, ...} — контракт
        // outside_service_area, guard_too_far_from_call и т.п.): человеку
        // показываем message, а не Map.toString().
        if (detail is Map) {
          final message = detail['message'];
          if (message is String && message.isNotEmpty) return message;
        }
        return detail.toString();
      }
      if (data is String && data.isNotEmpty) {
        return data;
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'No internet connection';
      }
    }
    return fallback;
  }
}

/// Global Dio instance for authenticated guard endpoints
final dio = ApiClient.instance;

/// Separate Dio for public endpoints (login, OTP)
final dioPublic = Dio(
  BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);

/// Public Dio for guard auth endpoints (/api/v1/guard/*) without attaching a Bearer token.
final dioGuardPublic = Dio(
  BaseOptions(
    baseUrl: ApiConstants.guardBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
