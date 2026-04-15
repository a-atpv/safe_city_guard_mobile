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

  static final StreamController<void> _logoutController = StreamController<void>.broadcast();
  static Stream<void> get logoutStream => _logoutController.stream;

  static bool _isRefreshing = false;
  static Completer<String?>? _refreshCompleter;

  static Future<String?> refreshToken() async {
    if (_isRefreshing) {
      log('ApiClient: Already refreshing, waiting for existing completer...');
      return _refreshCompleter?.future;
    }

    log('ApiClient: Starting token refresh process...');
    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await TokenStorage().getRefreshToken();
      if (refreshToken == null) {
        log('ApiClient: No refresh token found in storage.');
        throw Exception('No refresh token available');
      }

      // Use a separate Dio instance for refreshing to avoid interceptor recursion
      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      log('ApiClient: Calling refresh endpoint: ${ApiConstants.refresh}');
      final response = await refreshDio.post(
        ApiConstants.refresh,
        data: {'refresh_token': refreshToken},
      );

      final newAccessToken = response.data['access_token'];
      final newRefreshToken = response.data['refresh_token'];

      if (newAccessToken == null) {
        log('ApiClient: Refresh response did not contain access_token.');
        throw Exception('Invalid refresh response');
      }

      log('ApiClient: Token refresh successful. Saving new tokens.');
      // Save new tokens
      await TokenStorage().saveTokens(newAccessToken, newRefreshToken);
      
      // Complete the completer so other waiting requests can proceed
      _refreshCompleter!.complete(newAccessToken);
      return newAccessToken;
    } catch (refreshError) {
      log('ApiClient: Token refresh failed: $refreshError');
      _refreshCompleter!.complete(null);
      
      // Refresh failed - clear tokens and trigger logout
      log('ApiClient: Clearing tokens and triggering global logout.');
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
            final responseData = e.response?.data;
            final String detail = responseData is Map ? (responseData['detail'] ?? '').toString() : '';
            final statusCode = e.response?.statusCode;

            // Check if the error is a 401 Unauthorized or a 403 Forbidden (used by backend for auth issues)
            if (statusCode == 401 || (statusCode == 403 && detail.toLowerCase().contains('authenticated'))) {
              log('ApiClient: Authentication error encountered ($statusCode). Detail: $detail');

              // If it's a specific "Invalid guard token" error, don't even try to refresh
              if (detail.contains('Invalid guard token')) {
                log('ApiClient: Token is explicitly invalid. Triggering logout.');
                await TokenStorage().clearTokens();
                _logoutController.add(null);
                return handler.next(e);
              }

              final newToken = await refreshToken();
              if (newToken != null) {
                log('ApiClient: Token refreshed successfully. Retrying request.');
                // Retry the original request with the new token
                final opts = e.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                try {
                  final retryResponse = await _dio.fetch(opts);
                  return handler.resolve(retryResponse);
                } catch (retryError) {
                  return handler.next(e);
                }
              } else {
                log('ApiClient: Token refresh failed. Error will propagate.');
              }
            }
            return handler.next(e);
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
        return data['detail'].toString();
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
