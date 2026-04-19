import '../core/network/api_client.dart';
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

  Future<TripSession> createTrip({
    required String jeepneyId,
    required String routeId,
    String operatingMode = 'route',
    String status = 'active',
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/trips',
      body: {
        'jeepneyId': jeepneyId,
        'routeId': routeId,
        'operatingMode': operatingMode,
        'status': status,
      },
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
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

  Future<TripSession> updateTripManualOccupancy(
    String tripId,
    int manualOccupancyCount,
  ) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/occupancy',
      body: {'manualOccupancyCount': manualOccupancyCount},
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }
}
