import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class ProfileRepository {
  final Dio _dio = dio;

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await _dio.get('/me');
      return response.data;
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to get profile'));
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      await _dio.patch('/me', data: data);
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to update profile'));
    }
  }

  Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await _dio.get('/settings');
      return response.data;
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to get settings'));
    }
  }

  Future<void> updateSettings(Map<String, dynamic> data) async {
    try {
      await _dio.patch('/settings', data: data);
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to update settings'));
    }
  }
}
