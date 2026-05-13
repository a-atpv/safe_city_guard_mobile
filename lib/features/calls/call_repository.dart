import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/api_constants.dart';


class CallRepository {
  final Dio _dio = dio;

  Future<Map<String, dynamic>?> getActiveCall() async {
    try {
      final response = await _dio.get(ApiConstants.activeCall);

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw Exception(ApiClient.extractError(e, 'Failed to fetch active call'));
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableCalls() async {
    try {
      final response = await _dio.get(ApiConstants.availableCalls);

      final data = response.data;
      if (data is List) {
        return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (data is Map<String, dynamic>) {
        return [data];
      }
      return const [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const [];
      }
      throw Exception(ApiClient.extractError(e, 'Failed to fetch active call'));
    }
  }

  Future<void> acceptCall(String callId) async {
    try {
      await _dio.post(ApiConstants.acceptCall(callId));

    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to accept call'));
    }
  }

  Future<void> declineCall(String callId) async {
    try {
      await _dio.post(ApiConstants.declineCall(callId));

    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to decline call'));
    }
  }

  Future<void> enRoute(String callId) async {
    try {
      await _dio.post(ApiConstants.enRoute(callId));

    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to update status to en-route'));
    }
  }

  Future<void> arrived(String callId) async {
    try {
      await _dio.post(ApiConstants.arrived(callId));

    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to update status to arrived'));
    }
  }

  Future<void> complete(String callId) async {
    try {
      await _dio.post(ApiConstants.completeCall(callId));

    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to complete call'));
    }
  }

  Future<void> report(String callId, String category, String text) async {
    try {
      await _dio.post(ApiConstants.callReport(callId), data: {

        'category': category,
        'report_text': text,
      });
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to send report'));
    }
  }

  Future<void> sendMessage(String callId, String text) async {
    try {
      await _dio.post(ApiConstants.sendMessage(callId), data: {

        'message': text,
      });
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to send message'));
    }
  }

  Future<Map<String, dynamic>> getMessages(String callId) async {
    try {
      final response = await _dio.get(ApiConstants.callMessages(callId));

      return response.data;
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to fetch messages'));
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
      final response = await _dio.get(ApiConstants.callHistory, queryParameters: queryParams);

      return response.data;
    } on DioException catch (e) {
      throw Exception(ApiClient.extractError(e, 'Failed to fetch call history'));
    }
  }
}
