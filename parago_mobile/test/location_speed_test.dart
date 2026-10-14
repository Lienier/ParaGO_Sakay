import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/services/location_speed.dart';

void main() {
  test('unavailable or invalid speed cannot mean stopped', () {
    for (final value in <double?>[null, -1, double.nan, double.infinity]) {
      expect(sensorSpeed(value), -1);
    }
  });
  test('real stationary and moving observations retain their speed', () {
    expect(sensorSpeed(0), 0);
    expect(sensorSpeed(8.5), 8.5);
  });
}
