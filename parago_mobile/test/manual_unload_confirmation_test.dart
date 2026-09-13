import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/models/operations/ride_session.dart';
import 'package:parago_mobile/widgets/confirm_unload_dialog.dart';

void main() {
  const ride = RideSessionModel(id: 'ride', passengerId: 'passenger',
    tripSessionId: 'trip', pickupRequestId: '1234567890abcdef',
    status: 'onboard', pickupType: 'roadside',
    passengerDisplayName: 'Passenger One', destinationStopRef: 'Shared stop');
  for (final confirm in [false, true]) {
    testWidgets('identifies passenger and booking; ${confirm ? "confirm" : "cancel"} returns explicit choice', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () async { result = await confirmPassengerUnload(context, ride); }, child: const Text('Open')),
      ))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Passenger One'), findsOneWidget);
      expect(find.textContaining('90ABCDEF'), findsOneWidget);
      expect(find.textContaining('Shared stop'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text(confirm ? 'Mark unloaded' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(result, confirm);
    });
  }
}
