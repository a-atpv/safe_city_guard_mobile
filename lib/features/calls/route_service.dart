import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/api_constants.dart';
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
      ApiConstants.routeToCall(callId),

      queryParameters: {'with_steps': withSteps},
    );
    return CallRouteData.fromJson(response.data);
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
      ApiConstants.routeCalculate,

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
