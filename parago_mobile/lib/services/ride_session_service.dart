import '../core/network/api_client.dart';
import '../models/operations/ride_session.dart';

class RideSessionService {
  RideSessionService(this._client);

  final ApiClient _client;

  Future<List<RideSessionModel>> getTripRides(
    String tripSessionId, {
    bool useCache = true,
  }) async {
    final data = await _client.getList(
      path: '/ride-sessions/trip/$tripSessionId',
      useCache: useCache,
    );
    return data
        .map(
            (entry) => RideSessionModel.fromJson(entry as Map<String, dynamic>))
        .toList();
  }
}
