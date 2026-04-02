import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/token_storage.dart';

class NotificationsRepository {
  // Notifications endpoints are under /api/v1 (not /api/v1/guard)
  final Dio _dio = dioPublic;

  Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final token = await TokenStorage().getAccessToken();
      final response = await _dio.get(
        '/notifications',
        queryParameters: {'limit': limit, 'offset': offset},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to fetch notifications');
    }
  }

  Future<void> markRead(int notificationId) async {
    try {
      final token = await TokenStorage().getAccessToken();
      await _dio.patch(
        '/notifications/$notificationId/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to mark notification as read');
    }
  }

  Future<void> markAllRead() async {
    try {
      final token = await TokenStorage().getAccessToken();
      await _dio.post(
        '/notifications/read-all',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['detail'] ?? 'Failed to mark all notifications as read');
    }
  }
}
