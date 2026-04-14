import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/location_service.dart';
import '../../core/websocket/websocket_service.dart';
import '../calls/call_controller.dart';
import 'shift_repository.dart';

class ShiftState {
  final bool isOnline;
  final bool isLoading;
  final String? error;

  const ShiftState({
    this.isOnline = false,
    this.isLoading = true,
    this.error,
  });

  ShiftState copyWith({
    bool? isOnline,
    bool? isLoading,
    String? error,
  }) {
    return ShiftState(
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final shiftRepositoryProvider = Provider((ref) => ShiftRepository());

final shiftControllerProvider =
    NotifierProvider<ShiftController, ShiftState>(ShiftController.new);

class ShiftController extends Notifier<ShiftState> {
  late final ShiftRepository _repository;
  LocationService? _locationService;

  @override
  ShiftState build() {
    _repository = ref.read(shiftRepositoryProvider);
    Future.microtask(() => checkCurrentShift());

    final wsSubscription =
        webSocketServiceProvider.connectionStream.listen((isConnected) {
      if (isConnected) {
        ref.read(callControllerProvider.notifier).refresh();
      }
    });

    ref.onDispose(() {
      _stopLocationTracking();
      wsSubscription.cancel();
    });

    return const ShiftState();
  }

  Future<void> checkCurrentShift() async {
    try {
      final isOnline = await _repository.getCurrentShiftStatus();
      state = state.copyWith(isOnline: isOnline, isLoading: false);

      if (isOnline) {
        _onGoingOnline();
      }
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> toggleShift(bool value) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (value) {
        await _repository.startShift();
        _onGoingOnline();
      } else {
        await _repository.endShift();
        _onGoingOffline();
      }
      state = state.copyWith(isOnline: value, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void _onGoingOnline() {
    _startLocationTracking();
    webSocketServiceProvider.connect();
  }

  void _onGoingOffline() {
    _stopLocationTracking();
    webSocketServiceProvider.disconnect();
  }

  void _startLocationTracking() {
    _locationService ??= LocationService(
      onLocationUpdate: (lat, lng) {
        _repository.updateLocation(lat, lng);
      },
    );
    _locationService?.startTracking();
  }

  void _stopLocationTracking() {
    _locationService?.stopTracking();
  }

}
