import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;
  final Function(double lat, double lng) onLocationUpdate;

  LocationService({required this.onLocationUpdate});

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> startTracking() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    // Send the first location immediately
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      onLocationUpdate(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error getting initial location: $e');
    }

    // Set up a position stream / timer. For tracking every 15-30 seconds, a stream with distance filter or time interval is good.
    // iOS and Android support distance filter. To guarantee time updates, we can also just use a timer.
    // Let's use a Timer to fetch explicit location every 20 seconds.
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        onLocationUpdate(position.latitude, position.longitude);
      } catch (e) {
        debugPrint('Error getting periodic location: $e');
      }
    });
  }

  Timer? _timer;

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _timer?.cancel();
    _timer = null;
  }
}
