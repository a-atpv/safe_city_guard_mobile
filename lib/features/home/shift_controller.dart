import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/location_service.dart';
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

// We must also define a singleton LocationService or let Riverpod manage it.
// Here we wire them together.
final shiftControllerProvider =
    NotifierProvider<ShiftController, ShiftState>(ShiftController.new);

class ShiftController extends Notifier<ShiftState> {
  late final ShiftRepository _repository;
  LocationService? _locationService;

  @override
  ShiftState build() {
    _repository = ref.read(shiftRepositoryProvider);
    Future.microtask(() => checkCurrentShift());

    ref.onDispose(() {
      _stopLocationTracking();
    });

    return const ShiftState();
  }

  Future<void> checkCurrentShift() async {
    try {
      final isOnline = await _repository.getCurrentShiftStatus();
      state = state.copyWith(isOnline: isOnline, isLoading: false);

      if (isOnline) {
        _startLocationTracking();
      }
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Failed to fetch shift status');
    }
  }

  Future<void> toggleShift(bool value) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (value) {
        await _repository.startShift();
        _startLocationTracking();
      } else {
        await _repository.endShift();
        _stopLocationTracking();
      }
      state = state.copyWith(isOnline: value, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
