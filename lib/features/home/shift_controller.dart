import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/guard_location_tracker.dart';
import '../../core/location/geolocator_location_service.dart';
import '../../core/location/location_service.dart';
import '../../core/websocket/websocket_service.dart';
import '../calls/call_controller.dart';
import 'shift_repository.dart';

/// Which background-location backend the guard app uses on shift.
///
/// `true`  → free `GeolocatorLocationService` (foreground service; backgrounded-only) —
///           on trial for the dedicated Samsung A70 fleet.
/// `false` → paid `LocationService` (Transistorsoft; survives app-kill/reboot).
///
/// Flip this one line to fall back if the A70 field test doesn't hold up.
const bool kUseFreeLocationStack = true;

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

class ShiftController extends Notifier<ShiftState> with WidgetsBindingObserver {
  late final ShiftRepository _repository;
  GuardLocationTracker? _locationService;

  @override
  ShiftState build() {
    _repository = ref.read(shiftRepositoryProvider);
    Future.microtask(() => checkCurrentShift());

    // Listen for WebSocket connection to refresh calls
    final wsSubscription =
        webSocketServiceProvider.connectionStream.listen((isConnected) {
      if (isConnected) {
        ref.read(callControllerProvider.notifier).refresh();
      }
    });

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _stopLocationTracking();
      wsSubscription.cancel();
    });

    return const ShiftState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkCurrentShift();
    }
  }

  Future<void> checkCurrentShift() async {
    try {
      final isOnline = await _repository.getCurrentShiftStatus();
      state = state.copyWith(isOnline: isOnline, isLoading: false);

      if (isOnline) {
        _onGoingOnline();
      } else {
        _onGoingOffline();
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
    ref.read(callControllerProvider.notifier).startPolling();
  }

  void _onGoingOffline() {
    _stopLocationTracking();
    webSocketServiceProvider.disconnect();
    ref.read(callControllerProvider.notifier).stopPolling();
  }

  void _startLocationTracking() {
    _locationService ??=
        kUseFreeLocationStack ? GeolocatorLocationService() : LocationService();
    // Fire-and-forget: the background SDK persists and uploads fixes natively
    // (even when the app is killed), so we don't block the UI on it — just log
    // a startup failure.
    _locationService!.start().catchError(
      (e) => debugPrint('LocationService.start failed: $e'),
    );
  }

  void _stopLocationTracking() {
    _locationService?.stop().catchError(
      (e) => debugPrint('LocationService.stop failed: $e'),
    );
  }
}
