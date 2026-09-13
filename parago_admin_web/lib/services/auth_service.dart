import '../core/network/api_client.dart';
import '../models/auth/auth_models.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  Future<AuthSession> loginEmail({
    required String email,
    required String password,
    String? role,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };
    if (role != null && role.trim().isNotEmpty) {
      body['role'] = role.trim().toUpperCase();
    }
    final response = await _client.request(
      method: 'POST',
      path: '/auth/login-email',
      body: body,
    );
    return AuthSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<AdminLoginChallenge> startAdminLogin({
    required String email,
    required String password,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/admin/login/start',
      body: {
        'email': email.trim(),
        'password': password,
      },
      useCache: false,
    );
    return AdminLoginChallenge.fromJson(
      response['data'] as Map<String, dynamic>,
    );
  }

  Future<AuthSession> verifyAdminLogin({
    required String challengeId,
    required String code,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/admin/login/verify',
      body: {
        'challengeId': challengeId,
        'code': code.trim(),
      },
      useCache: false,
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
