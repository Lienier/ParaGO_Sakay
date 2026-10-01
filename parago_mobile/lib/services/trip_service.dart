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
    String operatingMode = 'terminal_queue',
    String status = 'scheduled',
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/trips',
      body: {
        'jeepneyId': jeepneyId,
        'routeId': routeId,
        'operatingMode': operatingMode,
        'status': status,
        'requestId': 'checkin-${DateTime.now().microsecondsSinceEpoch}',
      },
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TripSession> startTrip(String tripId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/start',
      body: {'requestId': 'start-${DateTime.now().microsecondsSinceEpoch}'},
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TripSession> terminalAction(String tripId, String action) async {
    final response = await _client.request(
        method: 'PATCH',
        path: '/trips/$tripId/terminal/$action',
        body: {
          'requestId': 'terminal-${DateTime.now().microsecondsSinceEpoch}'
        });
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<TripSession> endTrip(String tripId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/end',
      body: {'requestId': 'end-${DateTime.now().microsecondsSinceEpoch}'},
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
    int delta,
    String operationId,
  ) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/trips/$tripId/occupancy',
      body: {'delta': delta, 'operationId': operationId},
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }
}
