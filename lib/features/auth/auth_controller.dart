import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? error;

  const AuthState({this.isLoggedIn = false, this.isLoading = false, this.error});

  AuthState copyWith({bool? isLoggedIn, bool? isLoading, String? error}) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.read(authRepositoryProvider);
    return const AuthState();
  }

  Future<void> checkLoginStatus() async {
    final isLoggedIn = await _repository.isLoggedIn();
    state = state.copyWith(isLoggedIn: isLoggedIn);
  }

  Future<void> requestOtp(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.requestOtp(email);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> verifyOtp(String email, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.verifyOtp(email, code);
      state = state.copyWith(isLoading: false, isLoggedIn: true);
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
