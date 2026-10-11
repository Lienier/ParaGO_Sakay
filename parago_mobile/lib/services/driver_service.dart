import '../core/network/api_client.dart';
import '../core/exceptions/api_exception.dart';
import '../models/operations/driver_location_update.dart';
import '../models/operations/pickup_request.dart';

class DriverService {
  DriverService(this._client);

  final ApiClient _client;

  Future<void> pingServer() async {
    await _client.request(
      method: 'GET',
      path: '/',
      useCache: false,
    );
  }

  Future<Map<String, dynamic>> getProfile({bool useCache = true}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/drivers/me',
      useCache: useCache,
    );
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getLicenseDocuments() async {
    final response = await _client.request(
      method: 'GET',
      path: '/drivers/me/license-documents',
      useCache: false,
    );
    final data = response['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<void> setStatus({required bool active}) async {
    final body = {'status': active ? 'active' : 'inactive'};
    ApiException? lastError;
    final attempts = <String>['PATCH', 'POST', 'PUT'];

    for (final method in attempts) {
      try {
        await _client.request(
          method: method,
          path: '/drivers/me/status',
          body: body,
        );
        return;
      } on ApiException catch (error) {
        lastError = error;
        if (error.statusCode != 404 && error.statusCode != 405) {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw StateError('No driver status endpoint was attempted');
  }

  Future<DriverLocationAcknowledgement> updateLocation(
    DriverLocationUpdate update,
  ) async {
    final body = update.toJson();

    ApiException? lastError;
    final attempts = <Map<String, String>>[
      {'method': 'PATCH', 'path': '/drivers/location'},
      {'method': 'PATCH', 'path': '/drivers/me/location'},
      {'method': 'POST', 'path': '/drivers/location'},
      {'method': 'POST', 'path': '/drivers/me/location'},
      {'method': 'PUT', 'path': '/drivers/location'},
    ];

    bool isRouteNotFound(ApiException error) {
      return error.statusCode == 404 &&
          error.message.toLowerCase().contains('route not found');
    }

    for (final attempt in attempts) {
      try {
        final response = await _client.request(
          method: attempt['method']!,
          path: attempt['path']!,
          body: body,
        );
        return DriverLocationAcknowledgement.fromJson(
          response['data'] as Map<String, dynamic>,
        );
      } on ApiException catch (error) {
        lastError = error;
        if (!isRouteNotFound(error)) {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw StateError('No driver location endpoint was attempted');
  }

  Future<List<PickupRequestModel>> getRequestsForRoute(String routeId) async {
    final data = await _client.getList(
        path: '/pickup-requests/route/$routeId', useCache: false);
    return data
        .map((e) => PickupRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PickupRequestModel>> getRequestsForTrip(
    String tripSessionId, {
    bool useCache = true,
  }) async {
    final data = await _client.getList(
      path: '/pickup-requests/trip/$tripSessionId',
      useCache: useCache,
    );
    return data
        .map((e) => PickupRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PickupRequestModel> acknowledgeRequest(String requestId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/pickup-requests/$requestId/acknowledge',
      body: {},
    );
    return PickupRequestModel.fromJson(
        response['data'] as Map<String, dynamic>);
  }

  Future<PickupRequestModel> completeRequest(String requestId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/pickup-requests/$requestId/complete',
      body: {},
    );
    return PickupRequestModel.fromJson(
        response['data'] as Map<String, dynamic>);
  }
}
