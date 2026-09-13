import '../core/network/api_client.dart';
import '../core/exceptions/api_exception.dart';
import '../models/auth/auth_models.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  Future<AuthSession> registerEmail({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/register-email',
      body: {
        'email': email.trim(),
        'password': password.trim(),
        'fullName': fullName.trim(),
        'role': role.toUpperCase(),
      },
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<AuthSession> loginEmail({
    required String email,
    required String password,
    String? role,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/login-email',
      body: {
        'email': email.trim(),
        'password': password,
        if ((role ?? '').trim().isNotEmpty) 'role': role!.trim().toUpperCase(),
      },
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<AuthSession> socialLogin({
    required String provider,
    required String token,
    required String role,
  }) async {
    if (!['google', 'facebook'].contains(provider)) {
      throw ApiException(400, 'Unsupported social provider');
    }
    final response = await _client.request(
      method: 'POST',
      path: '/auth/social/$provider',
      body: {'token': token, 'role': role.toUpperCase()},
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<AuthSession> firebaseGoogleLogin({
    required String idToken,
    required String role,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/firebase/google',
      body: {
        'idToken': idToken,
        'role': role.toUpperCase(),
      },
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<UserProfile> getCurrentUser() async {
    final response = await _client.request(method: 'GET', path: '/auth/me', useCache: false);
    final data =
        response['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return UserProfile.fromJson(
        (data['user'] as Map? ?? <String, dynamic>{}).cast<String, dynamic>());
  }

  Future<AuthSession> refreshSession({required String refreshToken}) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/refresh',
      body: {'refreshToken': refreshToken},
      useCache: false,
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> logout({required String refreshToken}) async {
    await _client.request(
      method: 'POST',
      path: '/auth/logout',
      body: {'refreshToken': refreshToken},
    );
  }
}
