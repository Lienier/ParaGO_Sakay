import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/core/network/api_client.dart';
import 'package:parago_mobile/services/trip_service.dart';

class RecordingApi extends ApiClient {
  String? lastPath;
  dynamic lastBody;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    lastPath = path;
    lastBody = body;
    return {
      'data': {'_id': 'trip', 'status': 'active', 'operatingMode': 'route'}
    };
  }
}

void main() {
  test('terminal departure uses a distinct endpoint and an idempotency key',
      () async {
    final api = RecordingApi();
    final service = TripService(api);
    final trip = await service.terminalAction('trip', 'depart');
    expect(api.lastPath, '/trips/trip/terminal/depart');
    expect(api.lastBody['requestId'], isNotEmpty);
    expect(trip.status, 'active');
  });

  test('new driver trips enter terminal flow by default', () async {
    final api = RecordingApi();
    final service = TripService(api);
    await service.createTrip(jeepneyId: 'jeep', routeId: 'route');
    expect(api.lastPath, '/trips');
    expect(api.lastBody['operatingMode'], 'terminal_queue');
    expect(api.lastBody['status'], 'scheduled');
  });
}
