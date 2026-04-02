import 'package:dio/dio.dart';
import 'token_storage.dart';

class ApiClient {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/guard',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

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
            if (e.response?.statusCode == 401) {
              final refreshToken = await TokenStorage().getRefreshToken();
              if (refreshToken != null) {
                try {
                  // Use a fresh Dio to avoid interceptor loop
                  final refreshDio = Dio(BaseOptions(
                    baseUrl: 'https://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1/guard',
                    connectTimeout: const Duration(seconds: 10),
                    receiveTimeout: const Duration(seconds: 10),
                  ));

                  final refreshResponse = await refreshDio.post(
                    '/auth/refresh',
                    data: {'refresh_token': refreshToken},
                  );

                  final newAccessToken = refreshResponse.data['access_token'];
                  final newRefreshToken = refreshResponse.data['refresh_token'];

                  await TokenStorage().saveTokens(newAccessToken, newRefreshToken);

                  // Retry the original request with the new token
                  final opts = e.requestOptions;
                  opts.headers['Authorization'] = 'Bearer $newAccessToken';
                  final retryResponse = await _dio.fetch(opts);
                  return handler.resolve(retryResponse);
                } catch (refreshError) {
                  await TokenStorage().clearTokens();
                  return handler.next(e);
                }
              } else {
                await TokenStorage().clearTokens();
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

/// Global Dio instance for guard endpoints (/api/v1/guard/*)
final dio = ApiClient.instance;

/// Separate Dio for non-guard endpoints (/api/v1/*)
final dioPublic = Dio(
  BaseOptions(
    baseUrl: 'https://safe-city-back-7c8ed50edd7d.herokuapp.com/api/v1',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
