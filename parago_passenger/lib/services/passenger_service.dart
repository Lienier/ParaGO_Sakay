import '../core/network/api_client.dart';
import '../models/operations/pickup_request.dart';
import '../models/operations/ride_session.dart';

class PassengerService {
  PassengerService(this._client);

  final ApiClient _client;

  Future<List<PickupRequestModel>> getMyPickupRequests() async {
    final data = await _client.getList(path: '/pickup-requests/mine');
    return data
        .map((e) => PickupRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PickupRequestModel> createPickupRequest({
    required String tripSessionId,
    required String routeId,
    String? stopRef,
    double? lat,
    double? lng,
    String? sourceNote,
  }) async {
    final body = <String, dynamic>{
      'tripSessionId': tripSessionId,
      'routeId': routeId,
      'stopRef': stopRef,
      'sourceNote': sourceNote,
    };
    if (lat != null && lng != null) {
      body['pickupLocation'] = {
        'type': 'Point',
        'coordinates': [lng, lat],
      };
    }
    final response = await _client.request(
      method: 'POST',
      path: '/pickup-requests',
      body: body,
    );
    return PickupRequestModel.fromJson(
        response['data'] as Map<String, dynamic>);
  }

  Future<PickupRequestModel> cancelPickupRequest(String requestId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/pickup-requests/$requestId/cancel',
      body: {},
    );
    return PickupRequestModel.fromJson(
        response['data'] as Map<String, dynamic>);
  }

  Future<List<RideSessionModel>> getMyRides() async {
    final data = await _client.getList(path: '/ride-sessions/mine');
    return data
        .map((e) => RideSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RideSessionModel> validateBoarding({
    required String tripSessionId,
    required String pickupRequestId,
    double? lat,
    double? lng,
  }) async {
    final body = {
      'tripSessionId': tripSessionId,
      'pickupRequestId': pickupRequestId,
      'lat': lat,
      'lng': lng,
    };
    final response = await _client.request(
      method: 'POST',
      path: '/boarding/validate',
      body: body,
    );
    return RideSessionModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
