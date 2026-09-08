import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/services/passenger_service.dart';
import 'package:parago_passenger/models/operations/pickup_request.dart';

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
  test(
      'transfer acceptance sends offer identity without changing destination or fare',
      () async {
    final api = RecordingApi();
    final booking = PickupRequestModel.fromJson({
      '_id': 'booking',
      'status': 'transfer_offered',
      'transferOfferId': 'offer',
      'destinationStopRef': 'Saved stop'
    });
    await PassengerService(api).decideTransfer(booking, true);
    expect(api.lastPath, '/pickup-requests/booking/transfer/accept');
    expect(api.lastBody, {'offerId': 'offer'});
    expect(booking.destinationStopRef, 'Saved stop');
  });
}
