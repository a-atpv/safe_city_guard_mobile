import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/api_client.dart';
import 'dart:developer';
import 'dart:async';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final bool isInitialized;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.isLoading = false,
    this.isInitialized = false,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    bool? isInitialized,
    String? error,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;
  StreamSubscription? _logoutSubscription;

  @override
  AuthState build() {
    _repository = ref.read(authRepositoryProvider);

    // Listen for global logout events (e.g., from API interceptor on refresh failure)
    _logoutSubscription = ApiClient.logoutStream.listen((_) {
      state = state.copyWith(isLoggedIn: false);
    });

    ref.onDispose(() {
      _logoutSubscription?.cancel();
    });

    // Check for saved tokens on startup
    Future.microtask(() => _initAuth());
    return const AuthState(); // isInitialized = false → splash shown
  }

  Future<void> _initAuth() async {
    final isLoggedIn = await _repository.isLoggedIn();
    if (isLoggedIn) {
      _registerDevice();
    }
    state = state.copyWith(isLoggedIn: isLoggedIn, isInitialized: true);
  }

  Future<void> _registerDevice() async {
    try {
      final token = await PushNotificationService().getFcmToken();
      if (token != null) {
        await _repository.registerDevice(token);
        log('Device registered successfully with token');
      }
    } catch (e) {
      log('Failed to register device: $e');
    }
  }

  Future<void> _unregisterDevice() async {
    try {
      final token = await PushNotificationService().getFcmToken();
      if (token != null) {
        await _repository.unregisterDevice(token);
      }
    } catch (e) {
      log('Failed to unregister device: $e');
    }
  }

  Future<bool> requestOtp(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _repository.requestOtp(email);
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String email, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.verifyOtp(email, code);
      await _registerDevice();
      state = state.copyWith(isLoading: false, isLoggedIn: true, isInitialized: true);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    await _unregisterDevice();
    await _repository.logout();
    state = state.copyWith(isLoggedIn: false);
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
