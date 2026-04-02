import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository.dart';

class ProfileState {
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final bool isLoading;
  final String? error;

  const ProfileState({
    this.profile,
    this.settings,
    this.isLoading = true,
    this.error,
  });

  ProfileState copyWith({
    Map<String, dynamic>? profile,
    Map<String, dynamic>? settings,
    bool? isLoading,
    String? error,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final profileRepositoryProvider = Provider((ref) => ProfileRepository());

final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileState>(ProfileController.new);

class ProfileController extends Notifier<ProfileState> {
  late final ProfileRepository _repository;

  @override
  ProfileState build() {
    _repository = ref.read(profileRepositoryProvider);
    // Trigger data fetch without awaiting in build
    Future.microtask(() => fetchData());
    return const ProfileState();
  }

  Future<void> fetchData() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repository.getProfile();
      final settings = await _repository.getSettings();
      state = state.copyWith(
        profile: profile,
        settings: settings,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateSettings(Map<String, dynamic> data) async {
    try {
      await _repository.updateSettings(data);
      // Optimistic update
      final newSettings = Map<String, dynamic>.from(state.settings ?? {})..addAll(data);
      state = state.copyWith(settings: newSettings);
    } catch (e) {
      state = state.copyWith(error: 'Failed to update settings: $e');
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      await _repository.updateProfile(data);
      final newProfile = Map<String, dynamic>.from(state.profile ?? {})..addAll(data);
      state = state.copyWith(profile: newProfile);
    } catch (e) {
      state = state.copyWith(error: 'Failed to update profile: $e');
    }
  }
}
