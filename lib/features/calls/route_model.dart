class RouteStep {
  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
  final String name;

  RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.name,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) => RouteStep(
    instruction: json['instruction'] ?? '',
    distanceMeters: (json['distance_meters'] ?? 0).toDouble(),
    durationSeconds: (json['duration_seconds'] ?? 0).toDouble(),
    name: json['name'] ?? '',
  );
}

class RouteData {
  final String geometry;
  final List<List<double>> coordinates;
  final double distanceMeters;
  final double durationSeconds;
  final int etaMinutes;
  final String distanceText;
  final List<RouteStep> steps;

  RouteData({
    required this.geometry,
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.etaMinutes,
    required this.distanceText,
    this.steps = const [],
  });

  factory RouteData.fromJson(Map<String, dynamic> json) => RouteData(
    geometry: json['geometry'] ?? '',
    coordinates: (json['coordinates'] as List)
        .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
    distanceMeters: (json['distance_meters'] ?? 0).toDouble(),
    durationSeconds: (json['duration_seconds'] ?? 0).toDouble(),
    etaMinutes: json['eta_minutes'] ?? 0,
    distanceText: json['distance_text'] ?? '',
    steps: (json['steps'] as List? ?? [])
        .map((s) => RouteStep.fromJson(s))
        .toList(),
  );
}

class CallRouteData {
  final int callId;
  final String callStatus;
  final double userLatitude;
  final double userLongitude;
  final String? userAddress;
  /// Возраст точки вызывающего на момент ответа сервера. Бэкенд всегда отдаёт
  /// самую свежую известную точку и её возраст — молчаливой подмены на место
  /// нажатия SOS больше нет, поэтому устаревание видно в интерфейсе.
  final int? userLocationAgeSeconds;
  /// Погрешность фикса в метрах (null — точка вызова, погрешность неизвестна).
  final double? userLocationAccuracy;
  final bool userLocationIsLive;
  /// `live` — отслеживаемая позиция человека, `call` — место нажатия SOS.
  final String userLocationSource;
  final double? guardLatitude;
  final double? guardLongitude;
  final RouteData? route;
  final String? guardName;
  final String? guardAvatarUrl;
  final double? guardRating;
  final int? guardTotalReviews;
  final String? guardPhone;
  final String? userName;
  final String? userPhone;
 
   CallRouteData({
     required this.callId,
     required this.callStatus,
     required this.userLatitude,
     required this.userLongitude,
     this.userAddress,
     this.userLocationAgeSeconds,
     this.userLocationAccuracy,
     this.userLocationIsLive = false,
     this.userLocationSource = 'call',
     this.guardLatitude,
     this.guardLongitude,
     this.route,
     this.guardName,
     this.guardAvatarUrl,
     this.guardRating,
     this.guardTotalReviews,
     this.guardPhone,
     this.userName,
     this.userPhone,
   });
 
   factory CallRouteData.fromJson(Map<String, dynamic> json) => CallRouteData(
     callId: json['call_id'],
     callStatus: json['call_status'],
     userLatitude: (json['user_latitude'] as num).toDouble(),
     userLongitude: (json['user_longitude'] as num).toDouble(),
     userAddress: json['user_address'],
     userLocationAgeSeconds: (json['user_location_age_seconds'] as num?)?.round(),
     userLocationAccuracy: (json['user_location_accuracy'] as num?)?.toDouble(),
     userLocationIsLive: json['user_location_is_live'] == true,
     userLocationSource: json['user_location_source'] ?? 'call',
     guardLatitude: (json['guard_latitude'] as num?)?.toDouble(),
     guardLongitude: (json['guard_longitude'] as num?)?.toDouble(),
     route: json['route'] != null ? RouteData.fromJson(json['route']) : null,
     guardName: json['guard_name'],
     guardAvatarUrl: json['guard_avatar_url'],
     guardRating: (json['guard_rating'] as num?)?.toDouble(),
     guardTotalReviews: json['guard_total_reviews'],
     guardPhone: json['guard_phone'],
     userName: json['user_name'],
     userPhone: json['user_phone'],
   );
 }
