import '../core/network/api_client.dart';
import '../models/auth/auth_models.dart';

class AuthService {
  static const legalPolicyVersion = '2026-10-03';
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

  Future<UserProfile> getCurrentUser() async {
    final response =
        await _client.request(method: 'GET', path: '/auth/me', useCache: false);
    final data =
        response['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return UserProfile.fromJson(
        (data['user'] as Map? ?? <String, dynamic>{}).cast<String, dynamic>());
  }

  Future<UserProfile> acceptLegalPolicies() async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/legal-acceptance',
      body: {
        'termsVersion': legalPolicyVersion,
        'privacyVersion': legalPolicyVersion,
      },
      useCache: false,
    );
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return UserProfile.fromJson(
      (data['user'] as Map? ?? {}).cast<String, dynamic>(),
    );
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
