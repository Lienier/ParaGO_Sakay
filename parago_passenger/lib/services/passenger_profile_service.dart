import '../core/network/api_client.dart';
import '../models/passenger/passenger_profile.dart';

class PassengerProfileService {
  PassengerProfileService(this._client);

  final ApiClient _client;

  Future<PassengerProfileModel> getProfile({bool useCache = true}) async {
    final userResponse = await _client.request(
      method: 'GET',
      path: '/auth/me',
      useCache: useCache,
    );
    final passengerResponse = await _client.request(
      method: 'GET',
      path: '/passengers/me',
      useCache: useCache,
    );
    final user = (userResponse['data'] as Map<String, dynamic>? ??
            const <String, dynamic>{})['user'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final passenger = passengerResponse['data'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return PassengerProfileModel.fromResponses(
      user: user,
      passenger: passenger,
    );
  }

  Future<void> updateAccount({
    required String fullName,
    required String email,
  }) async {
    await _client.request(
      method: 'PUT',
      path: '/users/me',
      body: {
        'fullName': fullName.trim(),
        'email': email.trim(),
      },
      useCache: false,
    );
  }

  Future<void> updatePassengerProfile({
    String? phone,
    String? photoUrl,
    String? defaultRouteId,
    String? emergencyContactName,
    String? emergencyContactPhone,
  }) async {
    await _client.request(
      method: 'PUT',
      path: '/passengers/me',
      body: {
        'phone': (phone ?? '').trim(),
        'photoUrl': (photoUrl ?? '').trim(),
        'defaultRouteId': (defaultRouteId ?? '').trim().isEmpty
            ? null
            : defaultRouteId!.trim(),
        'emergencyContact': (emergencyContactName ?? '').trim().isEmpty &&
                (emergencyContactPhone ?? '').trim().isEmpty
            ? null
            : {
                'name': (emergencyContactName ?? '').trim(),
                'phone': (emergencyContactPhone ?? '').trim(),
              },
      },
      useCache: false,
    );
  }
}
