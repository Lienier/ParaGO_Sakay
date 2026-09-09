import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/utils/automation_location.dart';

void main() {
  test('automation rejects stale, future and inaccurate GPS fixes', () {
    final now = DateTime.utc(2026, 9, 9);
    bool usable(int age, double accuracy) => isUsableAutomationLocation(
      capturedAt: now.subtract(Duration(seconds: age)), now: now,
      accuracyMeters: accuracy,
    );
    expect(usable(5, 10), isTrue);
    expect(usable(15, 35), isTrue);
    expect(usable(16, 10), isFalse);
    expect(usable(-1, 10), isFalse);
    expect(usable(0, 36), isFalse);
    expect(usable(0, double.nan), isFalse);
    expect(usable(0, -1), isFalse);
  });
}
