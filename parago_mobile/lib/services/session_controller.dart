import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/storage/token_storage.dart';
import '../models/auth/auth_models.dart';
import '../models/user_role.dart';
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

  bool _isStaffUser(UserProfile? user) {
    final role = user?.role;
    return role == UserRole.driver;
  }

  Future<bool> _tryRefreshSession(String? refreshToken) async {
    final token = refreshToken?.trim() ?? '';
    if (token.isEmpty) {
      return false;
    }

    final session = await AuthService(_apiClient).refreshSession(
      refreshToken: token,
    );
    if (!_isStaffUser(session.user)) {
      await clear(notify: false);
      return false;
    }
    _applySession(session, notify: false);
    await _storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    return true;
  }

  void _applySession(AuthSession session, {bool notify = true}) {
    if (!_isStaffUser(session.user)) {
      throw StateError('Invalid email/password');
    }
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _user = session.user;
    _apiClient.setAccessToken(_accessToken);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> restore() async {
    final tokens = await _storage.loadTokens();
    final accessToken = tokens['accessToken'];
    final refreshToken = tokens['refreshToken'];

    try {
      final trimmedAccessToken = accessToken?.trim() ?? '';
      if (trimmedAccessToken.isNotEmpty) {
        _apiClient.setAccessToken(trimmedAccessToken);
        final user = await AuthService(_apiClient).getCurrentUser();
        if (_isStaffUser(user)) {
          _accessToken = trimmedAccessToken;
          _refreshToken = refreshToken;
          _user = user;
        } else {
          await clear(notify: false);
        }
      } else {
        final restored = await _tryRefreshSession(refreshToken);
        if (!restored) {
          await clear(notify: false);
        }
      }
    } catch (_) {
      try {
        final restored = await _tryRefreshSession(refreshToken);
        if (!restored) {
          await clear(notify: false);
        }
      } catch (_) {
        await clear(notify: false);
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void applySession(AuthSession session) {
    _applySession(session);
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
