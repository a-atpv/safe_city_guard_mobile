import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository.dart';

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

  @override
  AuthState build() {
    _repository = ref.read(authRepositoryProvider);
    // Check for saved tokens on startup
    Future.microtask(() => _initAuth());
    return const AuthState(); // isInitialized = false → splash shown
  }

  Future<void> _initAuth() async {
    final isLoggedIn = await _repository.isLoggedIn();
    state = state.copyWith(isLoggedIn: isLoggedIn, isInitialized: true);
  }

  Future<bool> requestOtp(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.requestOtp(email);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String email, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.verifyOtp(email, code);
      state = state.copyWith(isLoading: false, isLoggedIn: true, isInitialized: true);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(isLoggedIn: false);
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
