import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../models/auth/auth_models.dart';
import 'auth_service.dart';
import 'firebase_auth_service.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _storage = tokenStorage;

  final ApiClient _apiClient;
  final TokenStorage _storage;

  UserProfile? _user;
  String? _accessToken;
  String? _refreshToken;
  bool _loading = true;

  bool get isLoading => _loading;
  UserProfile? get user => _user;
  String? get token => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _user != null && _accessToken != null;
  ApiClient get apiClient => _apiClient;

  Future<void> restore() async {
    final tokens = await _storage.loadTokens();
    final accessToken = tokens['accessToken'];
    final refreshToken = tokens['refreshToken'];
    if (accessToken == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    _apiClient.setAccessToken(accessToken);
    try {
      final user = await AuthService(_apiClient).getCurrentUser();
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      _user = user;
    } catch (_) {
      await clear(notify: false);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void applySession(AuthSession session) {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _user = session.user;
    _apiClient.setAccessToken(_accessToken);
    notifyListeners();
  }

  Future<void> saveAuth(AuthSession session) async {
    applySession(session);
    await _storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
  }

  Future<void> logout() async {
    final refreshToken = _refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await AuthService(_apiClient).logout(refreshToken: refreshToken);
      } catch (_) {
        // Clear local session even if server-side revoke fails.
      }
    }
    try {
      await FirebaseAuthService().signOut();
    } catch (_) {
      // Keep logout resilient even when Firebase was not initialized.
    }
    await clear();
  }

  Future<void> clear({bool notify = true}) async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _apiClient.setAccessToken(null);
    await _apiClient.clearCache();
    await _storage.clearTokens();
    if (notify) {
      notifyListeners();
    }
  }
}
