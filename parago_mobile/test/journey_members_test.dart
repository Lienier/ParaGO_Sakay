import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/models/operations/pickup_request.dart';
import 'package:parago_mobile/widgets/journey_members.dart';

void main() {
  const members = [
    JourneyMemberModel(
        memberId: '1',
        organizer: true,
        label: 'You',
        destinationStopRef: 'Municipal Hall',
        latitude: 14,
        longitude: 121,
        fare: 17,
        status: 'completed'),
    JourneyMemberModel(
        memberId: '2',
        organizer: false,
        label: 'Passenger 2',
        destinationStopRef: 'College',
        latitude: 14,
        longitude: 121,
        fare: 19,
        status: 'onboard'),
    JourneyMemberModel(
        memberId: '3',
        organizer: false,
        label: 'Passenger 3',
        destinationStopRef: 'Mall',
        latitude: 14,
        longitude: 121,
        fare: 22,
        status: 'onboard'),
  ];
  testWidgets(
      'pickup label shows two destinations and overflow; tapping shows individual fares and total on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 180,
                    height: 112,
                    child: JourneyPickupPin(
                        members: members,
                        pickup: 'Shared pickup',
                        assignedJeepneyLabel: 'PW 123'))))));
    expect(find.textContaining('Municipal Hall\nCollege\n+1 more'),
        findsOneWidget);
    expect(find.textContaining('3 passengers · PW 123'), findsOneWidget);
    await tester.tap(find.byType(JourneyPickupPin));
    await tester.pumpAndSettle();
    expect(find.text('Passenger 3: Mall'), findsOneWidget);
    expect(find.text('Total: ₱58.00'), findsOneWidget);
    expect(find.text('Unloaded • ₱17.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'manual correction selects remaining members only and cancellation changes nothing',
      (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await chooseUnloadedMembers(context, members);
                    },
                    child: const Text('Correct'))))));
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('Passenger 2: College'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, ['2']);
  });
}
