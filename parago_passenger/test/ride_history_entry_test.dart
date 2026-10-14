import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/operations/ride_session.dart';
import 'package:parago_passenger/widgets/glass_surface.dart';
import 'package:parago_passenger/widgets/ride_history_entry.dart';

void main() {
  testWidgets(
      'completed group history explains each fare at narrow enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ride = RideSessionModel.fromJson({
      '_id': 'ride',
      'status': 'completed',
      'flowVersion': 2,
      'boardedCount': 2,
      'remainingCount': 0,
      'estimatedFare': 21,
      'regularTotal': 46,
      'members': [
        for (var i = 0; i < 2; i++)
          {
            'memberId': 'm$i',
            'organizer': i == 0,
            'label': i == 0 ? 'You' : 'Passenger 2',
            'destinationStopRef': i == 0 ? 'College' : 'Market',
            'status': 'completed',
            'destinationLocation': {
              'type': 'Point',
              'coordinates': [121.05, 14.915 + i * .01]
            },
            'fareSnapshot': {'amount': i == 0 ? 21 : 25},
          }
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child:
                        GlassSurface(child: RideHistoryEntry(ride: ride)))))));
    expect(find.text('You: College'), findsOneWidget);
    expect(find.text('Passenger 2: Market'), findsOneWidget);
    expect(find.text('Unloaded • ₱21.00'), findsOneWidget);
    expect(find.text('Unloaded • ₱25.00'), findsOneWidget);
    expect(find.text('Total: ₱46.00'), findsOneWidget);
    expect(find.textContaining('fare/person'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(passengerCountLabel(1), '1 passenger');
  });
}
