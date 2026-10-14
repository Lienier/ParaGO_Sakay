import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:parago_mobile/services/driver_position_source_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
  Map<String, dynamic> raw(double? speed) => {
        'latitude': 14.9,
        'longitude': 121.05,
        'accuracy': 5.0,
        'timestamp': 1791936000000,
        if (speed != null) 'speed': speed,
      };
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('native raw fix distinguishes unavailable and genuine zero speed', () {
    expect(driverPositionFromMap(raw(null)).speed, -1);
    expect(driverPositionFromMap({...raw(null), 'speed': null}).speed, -1);
    expect(driverPositionFromMap(raw(0)).speed, 0);
    expect(driverPositionFromMap(raw(8)).speed, 8);
    expect(driverPositionFromMap(raw(-1)).speed, -1);
  });
  test('Android fallback retains missing speed and foreground settings',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCurrentPosition');
      expect(call.arguments['requestId'], startsWith('driver-'));
      expect(call.arguments['distanceFilter'], 1);
      return raw(null);
    });
    final fix = await driverCurrentPosition(AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      timeLimit: const Duration(seconds: 4),
    ));
    expect(fix.speed, -1);
    expect(fix.latitude, 14.9);
  });
}
