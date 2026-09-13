import 'dart:async';
import 'dart:convert';
import '../core/exceptions/api_exception.dart';
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
        _storage = tokenStorage {
    _apiClient.beforeAuthenticatedRequest = ensureFreshSession;
    _apiClient.onAuthenticationRejected = _handleRejection;
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(validateSession().catchError((Object _) {}));
    });
  }

  final ApiClient _apiClient;
  final TokenStorage _storage;
  Timer? _refreshTimer;
  Future<bool>? _refreshInFlight;
  int _sessionEpoch = 0;
  String? signedOutMessage;
  bool _validating = false;

  Future<void> _handleRejection() async {
    signedOutMessage = _apiClient.authenticationRejectionMessage;
    await clear();
  }

  Future<void> validateSession() async {
    if (!isAuthenticated || _validating) return;
    _validating = true;
    final epoch = _sessionEpoch;
    try {
      await ensureFreshSession();
      if (epoch == _sessionEpoch && isAuthenticated) {
        await AuthService(_apiClient).getCurrentUser();
      }
    } on ApiException catch (error) {
      if (epoch == _sessionEpoch && (error.statusCode == 401 || error.statusCode == 403)) {
        signedOutMessage = error.message;
        await clear();
      }
    } finally {
      _validating = false;
    }
  }

  Future<void> ensureFreshSession() async {
    if (_accessToken == null || _refreshToken == null) return;
    final epoch = _sessionEpoch;
    try {
      final claims = jsonDecode(utf8.decode(base64Url
          .decode(base64Url.normalize(_accessToken!.split('.')[1])))) as Map;
      final expires = (claims['exp'] as num).toInt() * 1000;
      if (DateTime.now().millisecondsSinceEpoch < expires - 60000) return;
      if (await _tryRefreshSession(_refreshToken)) notifyListeners();
    } on ApiException catch (error) {
      if (epoch == _sessionEpoch && (error.statusCode == 401 || error.statusCode == 403)) {
        signedOutMessage = error.message;
        await clear();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiClient.beforeAuthenticatedRequest = null;
    _apiClient.onAuthenticationRejected = null;
    super.dispose();
  }

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
    return role == UserRole.admin;
  }

  Future<bool> _tryRefreshSession(String? refreshToken) async {
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    final request = _performRefreshSession(_refreshToken ?? refreshToken);
    _refreshInFlight = request;
    try {
      return await request;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> _performRefreshSession(String? refreshToken) async {
    final epoch = _sessionEpoch;
    final token = refreshToken?.trim() ?? '';
    if (token.isEmpty) {
      return false;
    }

    final session = await AuthService(_apiClient).refreshSession(
      refreshToken: token,
    );
    if (epoch != _sessionEpoch) return false;
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
    signedOutMessage = null;
    _apiClient.authenticationRejectionMessage = null;
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
      } catch (error) {
        if (error is ApiException && error.statusCode == 401) signedOutMessage = error.message;
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
    _sessionEpoch++;
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
    _sessionEpoch++;
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
