import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/widgets/booking_fare_reference.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/services/passenger_service.dart';
import 'package:parago_passenger/models/operations/ride_session.dart';
import 'package:parago_passenger/models/operations/pickup_request.dart';

class BookingApi extends ApiClient {
  Map<String, dynamic>? sent;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    sent = Map<String, dynamic>.from(body as Map);
    return {
      'data': {'_id': 'booking', 'status': 'pending'}
    };
  }
}

void main() {
  test(
      'legacy counts default to one; completed rides release all remaining seats',
      () {
    expect(PickupRequestModel.fromJson({'_id': 'old'}).partySize, 1);
    expect(
        RideSessionModel.fromJson({'_id': 'old', 'status': 'onboard'})
            .onboardCount,
        1);
    expect(
        RideSessionModel.fromJson({'_id': 'old', 'status': 'completed'})
            .remainingCount,
        0);
  });
  test(
      'organizer unload sends the full remaining group and a stable revision reference',
      () async {
    final api = BookingApi();
    final ride = RideSessionModel.fromJson({
      '_id': 'ride',
      'status': 'onboard',
      'partySize': 4,
      'boardedCount': 3,
      'remainingCount': 2,
      'revision': 1
    });
    await PassengerService(api).completeRideSession(ride.id, ride: ride);
    final first = Map.of(api.sent!);
    expect(first['count'], 2);
    expect(first['revision'], 1);
    await PassengerService(api).completeRideSession(ride.id, ride: ride);
    expect(api.sent, first);
  });
  test('remote booking request does not require or send device GPS', () async {
    final api = BookingApi();
    await PassengerService(api).createPickupRequest(
        routeId: 'route',
        pickupType: 'roadside',
        pickupLat: 14,
        pickupLng: 121,
        destinationStopRef: 'School',
        destinationLat: 14.1,
        destinationLng: 121.1);
    expect(api.sent!.containsKey('currentLocation'), false);
    expect((api.sent!['pickupLocation'] as Map)['coordinates'], [121, 14]);
  });
  testWidgets(
      'discount reference is per person and regular group total stays unchanged',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: BookingFareReference(regular: 15.55, partySize: 3))));
    expect(find.textContaining('₱12.44'), findsOneWidget);
    expect(find.textContaining('₱46.65'), findsOneWidget);
    expect(find.textContaining('Eligibility is not verified'), findsOneWidget);
    expect(discountedFareCentavos(13.33), 1066);
  });
}
