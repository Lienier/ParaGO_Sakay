import '../core/network/api_client.dart';
import '../models/operations/stop_alert.dart';

class StopAlertService {
  StopAlertService(this._client);

  final ApiClient _client;

  Future<StopAlertModel> sendStopAlert({
    required String tripSessionId,
    required String stopRef,
    String? note,
    double? lat,
    double? lng,
  }) async {
    final Map<String, dynamic> body = {
      'tripSessionId': tripSessionId,
      'stopRef': stopRef,
      'note': note,
    };
    if (lat != null && lng != null) {
      body['location'] = {
        'type': 'Point',
        'coordinates': [lng, lat],
      };
    }
    final response = await _client.request(
      method: 'POST',
      path: '/stop-alerts',
      body: body,
    );
    return StopAlertModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<List<StopAlertModel>> getTripStopAlerts(String tripSessionId) async {
    final data =
        await _client.getList(path: '/stop-alerts/trip/$tripSessionId');
    return data
        .map((e) => StopAlertModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> acknowledgeStopAlert(String alertId) async {
    await _client.request(
      method: 'PATCH',
      path: '/stop-alerts/$alertId/acknowledge',
      body: {},
    );
  }
}
