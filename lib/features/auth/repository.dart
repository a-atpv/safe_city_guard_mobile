import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/token_storage.dart';

class AuthRepository {
  final Dio _dio = dio;
  final TokenStorage _tokenStorage = TokenStorage();

  String _dioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is String && data.isNotEmpty) return data;
    return fallback;
  }

  Future<void> requestOtp(String email) async {
    try {
      await _dio.post('/auth/request-otp', data: {'email': email});
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, 'Failed to request OTP'));
    } catch (e) {
      throw Exception('Failed to request OTP');
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
      
      // Attempt to register device with a dummy token for now
      try {
        await registerDevice('dummy_device_token');
      } catch (e) {
        print('Device registration failed, but proceeding: $e');
      }
    } on DioException catch (e) {
      throw Exception(_dioMessage(e, 'Failed to verify OTP'));
    } catch (e) {
      throw Exception('Failed to verify OTP');
    }
  }

  Future<void> registerDevice(String token) async {
    try {
      await _dio.post('/device/register', data: {
        'device_token': token,
        'device_type': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      throw Exception('Failed to register device');
    }
  }

  Future<void> unregisterDevice(String token) async {
    try {
      await _dio.delete('/device/$token');
    } catch (e) {
      throw Exception('Failed to unregister device');
    }
  }

  Future<void> logout([String? deviceToken]) async {
    try {
      // Unregister push notifications token before clearing tokens locally
      final tokenToUnregister = deviceToken ?? 'dummy_device_token';
      await unregisterDevice(tokenToUnregister);
    } catch (e) {
      print('Device unregistration failed, but proceeding: $e');
    }
    await _tokenStorage.clearTokens();
  }

  Future<bool> isLoggedIn() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null;
  }
}
