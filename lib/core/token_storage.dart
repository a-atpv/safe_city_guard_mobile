import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _roleKey = 'role';

  /// Fires whenever the stored pair changes. The background-location SDK keeps
  /// its own copy of the tokens natively, so it subscribes to this to stay in
  /// step with renewals done on the Dart side. Isolate-local by nature — the
  /// headless isolate writes straight to SharedPreferences and the SDK there
  /// already holds the tokens it just renewed.
  static final StreamController<void> _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  Future<void> saveTokens(String accessToken, String refreshToken, {String? role}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (role != null) {
      await prefs.setString(_roleKey, role);
    }
    _changes.add(null);
  }

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_roleKey);
    _changes.add(null);
  }
}
