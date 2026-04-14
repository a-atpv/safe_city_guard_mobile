import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class ShiftRepository {
  final Dio _dio = dio;

  Future<bool> getCurrentShiftStatus() async {
    try {
      final response = await _dio.get('/shift/current');
      return response.data['is_online'] ?? false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return false;
      }
      throw Exception(ApiClient.extractError(e, 'Failed to get shift status'));
    }
  }

  Future<void> startShift() async {
    try {
      await _dio.post('/shift/start');
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to start shift'));
    }
  }

  Future<void> endShift() async {
    try {
      await _dio.post('/shift/end');
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to end shift'));
    }
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    try {
      await _dio.post('/location', data: {
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      // Ignore location update errors to not spam the UI
      debugPrint('Failed to update location to backend: $e');
    }
  }
}
