import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_repository.dart';
import '../home/shift_controller.dart';

class CallState {
  final Map<String, dynamic>? activeCall;
  final bool isLoading;
  final String? error;

  const CallState({
    this.activeCall,
    this.isLoading = true,
    this.error,
  });

  CallState copyWith({
    Map<String, dynamic>? Function()? activeCall,
    bool? isLoading,
    String? error,
  }) {
    return CallState(
      activeCall: activeCall != null ? activeCall() : this.activeCall,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final callRepositoryProvider = Provider((ref) => CallRepository());

final callControllerProvider =
    NotifierProvider<CallController, CallState>(CallController.new);

class CallController extends Notifier<CallState> {
  late final CallRepository _repository;
  Timer? _pollingTimer;

  @override
  CallState build() {
    _repository = ref.read(callRepositoryProvider);

    // Listen to shift status
    ref.listen<ShiftState>(shiftControllerProvider, (previous, next) {
      if (next.isOnline) {
        _startPolling();
      } else {
        _stopPolling();
      }
    });

    final isOnline = ref.read(shiftControllerProvider).isOnline;
    if (isOnline) {
      _startPolling();
    }

    ref.onDispose(() {
      _pollingTimer?.cancel();
    });

    return const CallState();
  }

  void _startPolling() {
    _fetchActiveCall(); // Initial fetch
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchActiveCall();
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    state = state.copyWith(activeCall: () => null, isLoading: false);
  }

  Future<void> _fetchActiveCall() async {
    try {
      final callInfo = await _repository.getActiveCall();
      state = state.copyWith(
        activeCall: () => callInfo,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to fetch active call: $e',
      );
    }
  }

  Future<void> acceptCall(String callId) async {
    try {
      await _repository.acceptCall(callId);
      await _fetchActiveCall();
    } catch (e) {
      state = state.copyWith(error: 'Accept failed: $e');
    }
  }

  Future<void> declineCall(String callId) async {
    try {
      await _repository.declineCall(callId);
      // Wait for it to clear from active calls
      await _fetchActiveCall();
    } catch (e) {
      state = state.copyWith(error: 'Decline failed: $e');
    }
  }

  Future<void> updateStatus(String callId, String status) async {
    try {
      if (status == 'en-route') {
        await _repository.enRoute(callId);
      } else if (status == 'arrived') {
        await _repository.arrived(callId);
      } else if (status == 'complete') {
        await _repository.complete(callId);
      }
      await _fetchActiveCall();
    } catch (e) {
      state = state.copyWith(error: 'Update status failed: $e');
    }
  }

  Future<void> sendReport(String callId, String category, String text) async {
    try {
      await _repository.report(callId, category, text);
    } catch (e) {
      state = state.copyWith(error: 'Failed to send report: $e');
      rethrow;
    }
  }

}
