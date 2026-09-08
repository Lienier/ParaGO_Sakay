import '../core/network/api_client.dart';
import '../models/operations/pickup_request.dart';
import '../models/operations/ride_session.dart';

class PassengerService {
  PassengerService(this._client);

  final ApiClient _client;

  Future<void> decideTransfer(PickupRequestModel request, bool accept) async {
    await _client.request(
        method: 'POST',
        path:
            '/pickup-requests/${request.id}/transfer/${accept ? "accept" : "decline"}',
        body: {'offerId': request.transferOfferId});
  }

  Future<List<PickupRequestModel>> getMyPickupRequests({
    bool useCache = true,
  }) async {
    final data = await _client.getList(
      path: '/pickup-requests/mine',
      useCache: useCache,
    );
    return data
        .map((e) => PickupRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PickupRequestModel> createPickupRequest({
    required String routeId,
    required double currentLat,
    required double currentLng,
    required String pickupType,
    double? pickupLat,
    double? pickupLng,
    required String destinationStopRef,
    required double destinationLat,
    required double destinationLng,
    String? stopRef,
    String? sourceNote,
  }) async {
    final body = <String, dynamic>{
      'routeId': routeId,
      'pickupType': pickupType,
      'stopRef': stopRef,
      'destinationStopRef': destinationStopRef,
      'sourceNote': sourceNote,
      if (pickupLat != null && pickupLng != null)
        'pickupLocation': {
          'type': 'Point',
          'coordinates': [pickupLng, pickupLat],
        },
      'currentLocation': {
        'type': 'Point',
        'coordinates': [currentLng, currentLat],
      },
      'destinationLocation': {
        'type': 'Point',
        'coordinates': [destinationLng, destinationLat],
      },
    };
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

  Future<String?> reverseGeocodeLabel({
    required double lat,
    required double lng,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/pickup-requests/reverse-geocode',
      queryParameters: {
        'lat': lat,
        'lng': lng,
      },
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }
    final rawLabel = data['label']?.toString().trim();
    if (rawLabel == null || rawLabel.isEmpty) {
      return null;
    }
    return rawLabel;
  }

  Future<List<RideSessionModel>> getMyRides({bool useCache = true}) async {
    final data = await _client.getList(
      path: '/ride-sessions/mine',
      useCache: useCache,
    );
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

  Future<PassengerLocationAutomationResult> updateLocationForRideAutomation({
    required double lat,
    required double lng,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/passengers/me/location',
      body: {
        'lat': lat,
        'lng': lng,
      },
      useCache: false,
    );
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return const PassengerLocationAutomationResult();
    }
    return PassengerLocationAutomationResult(
      autoBoardedRide: _readRideSession(data['autoBoardedRideSession']),
      autoCompletedRide: _readRideSession(data['autoCompletedRideSession']),
    );
  }

  Future<RideSessionModel> completeRideSession(String rideSessionId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/ride-sessions/$rideSessionId/complete',
      body: const <String, dynamic>{},
    );
    return RideSessionModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}

class PassengerLocationAutomationResult {
  const PassengerLocationAutomationResult({
    this.autoBoardedRide,
    this.autoCompletedRide,
  });

  final RideSessionModel? autoBoardedRide;
  final RideSessionModel? autoCompletedRide;
}

RideSessionModel? _readRideSession(dynamic value) {
  if (value is Map<String, dynamic>) {
    return RideSessionModel.fromJson(value);
  }
  if (value is Map) {
    return RideSessionModel.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}
