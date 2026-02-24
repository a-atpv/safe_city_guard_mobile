import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/token_storage.dart';

class AuthRepository {
  final Dio _dio = dio;
  final TokenStorage _tokenStorage = TokenStorage();

  Future<void> requestOtp(String email) async {
    try {
      await _dio.post('/auth/request-otp', data: {'email': email});
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to request OTP');
    }
  }

  Future<void> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post('/auth/verify-otp', data: {'email': email, 'code': code});
      final data = response.data;
      await _tokenStorage.saveTokens(
        data['access_token'],
        data['refresh_token'],
        role: data['role'],
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to verify OTP');
    }
  }

  Future<void> logout() async {
    await _tokenStorage.clearTokens();
  }

  Future<bool> isLoggedIn() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null;
  }
}
