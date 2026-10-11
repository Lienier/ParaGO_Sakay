import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/services/waiting_movement_guard.dart';
import 'package:parago_passenger/widgets/waiting_check_card.dart';

void main() {
  testWidgets('Waiting and Cancel remain readable at 320 pixels and 200% text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var waiting = 0, cancel = 0;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 740), textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: WaitingCheckCard(
                        reason: WaitingMovementReason.distance,
                        onWaiting: () => waiting++,
                        onCancel: () => cancel++))))));
    await tester.tap(find.text('Waiting'));
    await tester.tap(find.text('Cancel'));
    expect(waiting, 1);
    expect(cancel, 1);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OutlinedButton).first).height,
        greaterThanOrEqualTo(48));
  });
}
