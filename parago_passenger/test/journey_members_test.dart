import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/operations/pickup_request.dart';
import 'package:parago_passenger/widgets/journey_members.dart';

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
                        members: members, pickup: 'Shared pickup'))))));
    expect(find.text('Municipal Hall\nCollege\n+1 more'), findsOneWidget);
    await tester.tap(find.byType(JourneyPickupPin));
    await tester.pumpAndSettle();
    expect(find.text('Passenger 3: Mall'), findsOneWidget);
    expect(find.text('Total: \u20b158.00'), findsOneWidget);
    expect(find.text('Unloaded \u2022 \u20b117.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'automatic drop-off status uses stop order, not passenger row order',
      (tester) async {
    const reordered = [
      JourneyMemberModel(
          memberId: '1',
          organizer: true,
          label: 'You',
          destinationStopRef: 'Mall',
          latitude: 14.3,
          longitude: 121,
          fare: 22,
          status: 'onboard',
          destinationStopOrder: 3),
      JourneyMemberModel(
          memberId: '2',
          organizer: false,
          label: 'Passenger 2',
          destinationStopRef: 'College',
          latitude: 14.1,
          longitude: 121,
          fare: 17,
          status: 'onboard',
          destinationStopOrder: 1),
    ];
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AutomaticDropoffStatus(members: reordered))));
    expect(find.text('Next: College'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Who got off?'), findsNothing);
  });
  testWidgets(
      'completed passengers stay completed and unknown order is not guessed',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      AutomaticDropoffStatus(members: members),
      JourneyMembers(members: members)
    ]))));
    expect(find.text('Auto drop-off'), findsOneWidget);
    expect(find.textContaining('Next:'), findsNothing);
    expect(find.text('Unloaded \u2022 \u20b117.00'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });
  test('saved route stop order is read from the member fare snapshot', () {
    final member = JourneyMemberModel.fromJson({
      'memberId': '1',
      'organizer': true,
      'label': 'You',
      'destinationStopRef': 'College',
      'destinationLocation': {
        'coordinates': [121, 14]
      },
      'fareSnapshot': {'amount': 17, 'destinationStopOrder': 4},
      'status': 'onboard'
    });
    expect(member.destinationStopOrder, 4);
  });
}
