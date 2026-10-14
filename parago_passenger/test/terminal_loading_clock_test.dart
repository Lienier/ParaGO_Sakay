import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/widgets/terminal_loading_clock.dart';

void main() {
  test('old loading summary retains its elapsed age', () {
    final now = DateTime.utc(2026, 10, 14, 4, 5);
    expect(
        terminalSecondsRemaining({
          'remainingSeconds': 600,
          'serverTime':
              now.subtract(const Duration(minutes: 3)).toIso8601String()
        }, now),
        420);
    expect(
        terminalSecondsRemaining({
          'remainingSeconds': 20,
          'serverTime':
              now.subtract(const Duration(minutes: 1)).toIso8601String()
        }, now),
        0);
  });
}
