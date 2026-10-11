import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/theme/app_theme.dart';
import 'package:parago_mobile/widgets/glass_surface.dart';
import 'package:parago_mobile/widgets/walk_in_controls.dart';

void main() {
  Future<void> show(WidgetTester tester,
      {int count = 5,
      int onboard = 5,
      int capacity = 20,
      bool enabled = true,
      double scale = 1,
      required List<int> applied}) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: GlassSurface(
                    padding: const EdgeInsets.all(20),
                    child: WalkInControls(
                        enabled: enabled,
                        manualCount: count,
                        displayedOnboard: onboard,
                        capacity: capacity,
                        onAdjust: applied.add))))));
  }

  testWidgets('six buttons send their exact delta once', (tester) async {
    final applied = <int>[];
    await show(tester, applied: applied);
    for (final label in ['-1', '-3', '-5', '+1', '+3', '+5']) {
      await tester.tap(find.text(label));
    }
    expect(applied, [-1, -3, -5, 1, 3, 5]);
  });
  testWidgets('negative count and capacity limits disable invalid bulk changes',
      (tester) async {
    final applied = <int>[];
    await show(tester, count: 2, onboard: 4, capacity: 6, applied: applied);
    bool enabled(String label) =>
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed !=
        null;
    expect(enabled('-1'), isTrue);
    expect(enabled('-3'), isFalse);
    expect(enabled('-5'), isFalse);
    expect(enabled('+1'), isTrue);
    expect(enabled('+3'), isFalse);
    expect(enabled('+5'), isFalse);
    await show(tester, enabled: false, applied: applied);
    for (final label in ['-1', '-3', '-5', '+1', '+3', '+5']) {
      expect(enabled(label), isFalse);
    }
  });
  testWidgets('six controls fit a narrow screen with double-size text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final applied = <int>[];
    await show(tester, scale: 2, applied: applied);
    expect(tester.takeException(), isNull);
    for (final label in ['-1', '-3', '-5', '+1', '+3', '+5']) {
      final bounds = tester.getRect(find.widgetWithText(OutlinedButton, label));
      expect(bounds.right, lessThanOrEqualTo(300));
      expect(bounds.height, greaterThanOrEqualTo(52));
    }
    await tester.tap(find.text('+5'));
    expect(applied, [5]);
  });
}
