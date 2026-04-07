import 'dart:async';
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

  static final StreamController<void> _logoutController = StreamController<void>.broadcast();
  static Stream<void> get logoutStream => _logoutController.stream;

  static bool _isRefreshing = false;
  static Completer<String?>? _refreshCompleter;

  static Future<String?> refreshToken() async {
    if (_isRefreshing) {
      return _refreshCompleter?.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await TokenStorage().getRefreshToken();
      if (refreshToken == null) {
        throw Exception('No refresh token available');
      }

      // Use a separate Dio instance for refreshing to avoid interceptor recursion
      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConstants.guardBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await refreshDio.post(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );

      final newAccessToken = response.data['access_token'];
      final newRefreshToken = response.data['refresh_token'];

      // Save new tokens
      await TokenStorage().saveTokens(newAccessToken, newRefreshToken);
      
      // Complete the completer so other waiting requests can proceed
      _refreshCompleter!.complete(newAccessToken);
      return newAccessToken;
    } catch (refreshError) {
      _refreshCompleter!.complete(null);
      
      // Refresh failed - clear tokens and trigger logout
      await TokenStorage().clearTokens();
      _logoutController.add(null);
      
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  /// Proactively ensures a fresh token is available.
  /// For now, it returns the current token if available.
  /// Potential future improvement: decode JWT and refresh if close to expiry.
  static Future<String?> ensureFreshToken() async {
    final token = await TokenStorage().getAccessToken();
    return token;
  }

  static bool _interceptorsAdded = false;

  static Dio get instance {
    if (!_interceptorsAdded) {
      _interceptorsAdded = true;

      _dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ));

      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = await TokenStorage().getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            return handler.next(options);
          },
          onError: (DioException e, handler) async {
            // Check if the error is a 401 Unauthorized
            if (e.response?.statusCode == 401) {
              final newToken = await refreshToken();
              if (newToken != null) {
                // Retry the original request with the new token
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                try {
                  final retryResponse = await _dio.fetch(opts);
                  return handler.resolve(retryResponse);
                } catch (retryError) {
                  return handler.next(e);
                }
              }
            }
            return handler.next(e);
          },
        ),
      );
    }
    return _dio;
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
