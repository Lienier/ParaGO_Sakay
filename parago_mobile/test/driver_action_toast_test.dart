import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/widgets/driver_action_toast.dart';

void main() {
  testWidgets(
      'stable request selection, duplicate-tap guard and pending fallback',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    DriverToastAction action(String id) => DriverToastAction(
        id: id,
        title: 'Request $id',
        detail: 'Booking $id',
        label: 'Acknowledge',
        run: () async {
          calls++;
          await gate.future;
        });
    Future<void> show(List<DriverToastAction> actions) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DriverActionToast(actions: actions))));
    await show([action('one'), action('two')]);
    await tester.tap(find.text('Next action'));
    await tester.pump();
    expect(find.text('Request two'), findsOneWidget);
    await show([action('new'), action('one'), action('two')]);
    expect(find.text('Request two'), findsOneWidget);
    await tester.tap(find.text('Acknowledge'));
    await tester.pump();
    await tester.tap(find.text('Working...'));
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Minimize actions'));
    await tester.pump();
    expect(find.text('3 driver actions'), findsOneWidget);
    expect(find.text('Acknowledge'), findsNothing);
    await show([action('one')]);
    await tester.tap(find.byTooltip('Show actions'));
    await tester.pump();
    expect(find.text('Request one'), findsOneWidget);
  });

  testWidgets('failed action stays available with error at phone width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DriverActionToast(actions: [
      DriverToastAction(
          id: 'one',
          title: 'Pickup request',
          detail: 'Long pickup destination ' * 10,
          label: 'Acknowledge',
          run: () async => throw StateError('Request expired')),
    ]))));
    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Request expired'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
