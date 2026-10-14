import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/widgets/terminal_loading_clock.dart';

void main() {
  final start = DateTime.utc(2026, 10, 14, 4);
  final summary = {
    'remainingSeconds': 600,
    'serverTime': start.toIso8601String(),
    'loadingDeadline': start.add(const Duration(minutes: 10)).toIso8601String()
  };
  test('reopening an old summary does not restart the loading period', () {
    expect(
        terminalSecondsRemaining(
            summary, start.add(const Duration(minutes: 3))),
        420);
    expect(
        terminalSecondsRemaining(
            summary, start.add(const Duration(minutes: 11))),
        0);
  });
  testWidgets('expired cached summary shows loading closed immediately',
      (tester) async {
    final old = DateTime.now().subtract(const Duration(minutes: 11));
    await tester.pumpWidget(MaterialApp(
        home: TerminalLoadingClock(summary: {
      'remainingSeconds': 600,
      'serverTime': old.toIso8601String(),
      'loadingDeadline': old.add(const Duration(minutes: 10)).toIso8601String(),
    })));
    expect(find.text('Loading closed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
