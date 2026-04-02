import 'package:dio/dio.dart';
import '../../core/api_client.dart';

class CallRepository {
  final Dio _dio = dio;

  Future<Map<String, dynamic>?> getActiveCall() async {
    try {
      final response = await _dio.get('/call/active');
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch active call');
    }
  }

  Future<void> acceptCall(String callId) async {
    try {
      await _dio.post('/call/$callId/accept');
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to accept call');
    }
  }

  Future<void> declineCall(String callId) async {
    try {
      await _dio.post('/call/$callId/decline');
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to decline call');
    }
  }

  Future<void> enRoute(String callId) async {
    try {
      await _dio.post('/call/$callId/en-route');
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to update status to en-route');
    }
  }

  Future<void> arrived(String callId) async {
    try {
      await _dio.post('/call/$callId/arrived');
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to update status to arrived');
    }
  }

  Future<void> complete(String callId) async {
    try {
      await _dio.post('/call/$callId/complete');
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to complete call');
    }
  }

  Future<void> report(String callId, String category, String text) async {
    try {
      await _dio.post('/call/$callId/report', data: {
        'category': category,
        'report_text': text,
      });
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to send report');
    }
  }

  Future<void> sendMessage(String callId, String text) async {
    try {
      await _dio.post('/call/$callId/message', data: {
        'message': text,
      });
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to send message');
    }
  }

  Future<Map<String, dynamic>> getMessages(String callId) async {
    try {
      final response = await _dio.get('/call/$callId/messages');
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch messages');
    }
  }

  Future<Map<String, dynamic>> getCallHistory({
    int limit = 20,
    int offset = 0,
    String? statusFilter,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      if (statusFilter != null) {
        queryParams['status_filter'] = statusFilter;
      }
      final response = await _dio.get('/history', queryParameters: queryParams);
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch call history');
    }
  }
}
