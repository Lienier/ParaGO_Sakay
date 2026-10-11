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

  Future<RideSessionModel> confirmGroupBoarding(
      String requestId, int count) async {
    final response = await _client.request(
        method: 'POST',
        path: '/pickup-requests/$requestId/group-board',
        body: {
          'count': count,
          'requestId': 'board-$requestId-$count',
        });
    return RideSessionModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<RideSessionModel> completeRideSession(String rideSessionId,
      {RideSessionModel? ride, int? count, List<String>? memberIds}) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/ride-sessions/$rideSessionId/complete',
      body: ride?.flowVersion == 2
          ? {
              'memberIds': memberIds,
              'revision': ride!.revision,
              'requestId': '$rideSessionId-${ride.revision}-manual-correction',
            }
          : ride?.isGroup == true
              ? {
                  'count': count,
                  'revision': ride!.revision,
                  'requestId': 'driver-$rideSessionId-${ride.revision}-$count',
                }
              : const <String, dynamic>{},
    );
    return RideSessionModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
