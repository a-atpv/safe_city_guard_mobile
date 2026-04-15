import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/api_constants.dart';
import '../../core/token_storage.dart';

class AuthRepository {
  final Dio _dio = dio;
  final TokenStorage _tokenStorage = TokenStorage();

  Future<bool> requestOtp(String email) async {
    try {
      final response = await dioPublic.post(ApiConstants.login, data: {'email': email});
      final data = response.data;

      // Backend response example:
      // {"success":true,"message":"OTP sent successfully","data":{"email":"..."}}
      if (data is Map && data['success'] != null) {
        final success = data['success'];
        if (success is bool) return success;
        if (success is num) return success != 0;
        if (success is String) return success.toLowerCase() == 'true';
      }

      // If the server doesn't include `success` but returned 2xx, treat as success.
      return true;
    } on DioException catch (e) {
      // In case the backend returns non-2xx but still includes `success`,
      // try to interpret it instead of immediately failing.
      final data = e.response?.data;
      if (data is Map && data['success'] != null) {
        final success = data['success'];
        if (success is bool) return success;
        if (success is num) return success != 0;
        if (success is String) return success.toLowerCase() == 'true';
      }
      throw Exception(ApiClient.extractError(e, 'Failed to request OTP'));
    } catch (e) {
      throw Exception('Failed to request OTP');
    }
  }

  Future<void> verifyOtp(String email, String code) async {
    try {
      final response = await dioPublic.post(ApiConstants.verifyOtp, data: {'email': email, 'code': code});
      final data = response.data;
      await _tokenStorage.saveTokens(
        data['access_token'],
        data['refresh_token'],
        role: data['role'],
      );
      // Device registration is now handled by the controller
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to verify OTP'));
    } catch (e) {
      throw Exception('Failed to verify OTP');
    }
  }

  Future<void> registerDevice(String token) async {
    try {
      await _dio.post(ApiConstants.registerDevice, data: {
        'device_token': token,
        'device_type': Platform.isIOS ? 'ios' : 'android',
        'device_model': 'Guard Mobile Device',
        'app_version': '1.0.0',
      });
    } catch (e) {
      throw Exception('Failed to register device');
    }
  }

  Future<void> unregisterDevice(String token) async {
    try {
      await _dio.delete(ApiConstants.unregisterDevice + token);
    } catch (e) {
      throw Exception('Failed to unregister device');
    }
  }

  Future<void> logout([String? deviceToken]) async {
    if (deviceToken != null) {
      try {
        await unregisterDevice(deviceToken);
      } catch (e) {
        debugPrint('Device unregistration failed, but proceeding: $e');
      }
    }
    await _tokenStorage.clearTokens();
  }

  Future<bool> isLoggedIn() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null;
  }
}
