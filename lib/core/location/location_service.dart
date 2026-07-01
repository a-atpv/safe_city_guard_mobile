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

    // Continuous stream instead of a fixed 20s timer: emit on every ~10 m of
    // movement so the guard marker on the dispatcher map / user app moves
    // smoothly and with minimal delay (each fix is pushed on via WebSocket),
    // while staying quiet and battery-friendly when the guard is stationary.
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (position) => onLocationUpdate(position.latitude, position.longitude),
      onError: (e) => debugPrint('Error in location stream: $e'),
    );
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}
