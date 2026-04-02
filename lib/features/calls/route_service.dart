import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import 'route_model.dart';

class RouteService {
  final Dio _dio =
      dio; // Uses the Dio instance pre-configured for /api/v1/guard

  /// Primary endpoint: Get route from guard to active call
  /// This is what you call when the guard opens or refreshes the active call screen
  Future<CallRouteData> getRouteToCall(
    int callId, {
    bool withSteps = false,
  }) async {
    final response = await _dio.get(
      '/route/call/$callId',
      queryParameters: {'with_steps': withSteps},
    );
    return CallRouteData.fromJson(response.data);
  }

  /// Quick ETA only (lightweight, for showing ETA before accepting)
  Future<int> getETA(double destLat, double destLng) async {
    final response = await _dio.get(
      '/route/eta',
      queryParameters: {'dest_lat': destLat, 'dest_lng': destLng},
    );
    return response.data['eta_minutes'] as int;
  }

  /// Calculate standalone route
  Future<RouteData> calculateRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool withSteps = false,
  }) async {
    final response = await _dio.post(
      '/route/calculate',
      data: {
        'origin_lat': originLat,
        'origin_lng': originLng,
        'dest_lat': destLat,
        'dest_lng': destLng,
        'with_steps': withSteps,
      },
    );
    return RouteData.fromJson(response.data);
  }
}
