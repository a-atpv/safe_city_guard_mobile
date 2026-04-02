import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class SupportRepository {
  // Support endpoints are under /api/v1 (not /api/v1/guard)
  final Dio _dio = dioPublic;

  Future<Map<String, dynamic>> getContacts() async {
    try {
      final response = await _dio.get('/support/contacts');
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch support contacts');
    }
  }

  Future<List<dynamic>> getFAQ() async {
    try {
      final response = await _dio.get('/support/faq', queryParameters: {'target': 'guard'});
      return response.data['items'] ?? [];
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch FAQ');
    }
  }
}
