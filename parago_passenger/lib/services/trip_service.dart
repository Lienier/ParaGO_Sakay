import '../core/network/api_client.dart';
import '../models/trip/passenger_jeep_eta.dart';
import '../models/trip/trip_session.dart';

class TripService {
  TripService(this._client);

  final ApiClient _client;

  Future<List<TripSession>> getActiveTrips({bool useCache = true}) async {
    final data =
        await _client.getList(path: '/trips/active', useCache: useCache);
    return data
        .map((e) => TripSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TripSession>> getMyTrips({bool useCache = true}) async {
    final data = await _client.getList(path: '/trips/mine', useCache: useCache);
    return data
        .map((e) => TripSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PassengerJeepEta> getPassengerEta({
    required String tripId,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/trips/$tripId/passenger-eta',
      body: {
        'destination': {
          'latitude': destinationLatitude,
          'longitude': destinationLongitude,
        },
      },
      useCache: false,
    );
    return PassengerJeepEta.fromJson(
      (response['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<TripSession> startTrip(String tripId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/start',
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TripSession> endTrip(String tripId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/end',
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TripSession> setTripAvailability(
      String tripId, bool acceptRequests) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/availability',
      body: {'acceptRequests': acceptRequests},
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }
}
