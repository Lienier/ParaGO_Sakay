import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/core/network/api_client.dart';
import 'package:parago_mobile/models/operations/ride_session.dart';
import 'package:parago_mobile/services/ride_session_service.dart';
import 'package:parago_mobile/widgets/confirm_unload_dialog.dart';

class GroupApi extends ApiClient {
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
      'data': {
        '_id': 'ride',
        'status': 'onboard',
        'remainingCount': 2,
        'partySize': 4,
        'revision': 1
      }
    };
  }
}

void main() {
  test(
      'partial unloading carries count and revision, stable across lost-response retry',
      () async {
    final api = GroupApi();
    final service = RideSessionService(api);
    final ride = RideSessionModel.fromJson({
      '_id': 'ride',
      'status': 'onboard',
      'partySize': 4,
      'remainingCount': 3,
      'revision': 0
    });
    await service.completeRideSession(ride.id, ride: ride, count: 1);
    final first = Map.of(api.sent!);
    expect(first['count'], 1);
    expect(first['revision'], 0);
    await service.completeRideSession(ride.id, ride: ride, count: 1);
    expect(api.sent, first);
    expect(ride.onboardCount, 3);
  });
  testWidgets(
      'count confirmation identifies the booking and cancel does not unload',
      (tester) async {
    int? result = 99;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () async {
                        result = await confirmPassengerCount(context,
                            title: 'How many got off?',
                            identity: 'Booking ABC123',
                            maximum: 3,
                            actionLabel: 'Confirm unloaded');
                      },
                      child: const Text('Open'),
                    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Booking ABC123'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
