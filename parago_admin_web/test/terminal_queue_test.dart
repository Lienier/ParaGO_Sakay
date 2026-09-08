import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/services/admin_service.dart';

class RecordingApi extends ApiClient {
  String? lastPath;
  dynamic lastBody;
  bool failNext = false;
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
    if (failNext) {
      failNext = false;
      throw Exception('Connection interrupted');
    }
    return {
      'data': {'_id': 'trip', 'status': 'active', 'operatingMode': 'route'}
    };
  }
}

void main() {
  test('retry after a lost response reuses the same terminal action ID',
      () async {
    final api = RecordingApi()..failNext = true;
    final service = AdminService(api);
    await expectLater(
        service.reorderTerminalQueueTrip(
            tripId: 'retry-trip', direction: 'up', reason: 'Arrival order'),
        throwsException);
    final id = api.lastBody['requestId'];
    await service.reorderTerminalQueueTrip(
        tripId: 'retry-trip', direction: 'up', reason: 'Arrival order');
    expect(api.lastBody['requestId'], id);
  });

  test('admin override sends reason and unique action ID', () async {
    final api = RecordingApi();
    await AdminService(api).setTerminalQueueStatus(
        tripId: 'trip',
        terminalQueueStatus: 'departed',
        reason: 'Driver asked to depart');
    expect(api.lastPath, '/admin/terminal-queue/trip/status');
    expect(api.lastBody['reason'], 'Driver asked to depart');
    expect(api.lastBody['requestId'], isNotEmpty);
  });
}
