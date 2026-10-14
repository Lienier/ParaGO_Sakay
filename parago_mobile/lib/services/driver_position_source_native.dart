import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'location_speed.dart';

String? get _channelSuffix => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS || TargetPlatform.macOS => 'apple',
      _ => null,
    };

// Android omits speed when Location.hasSpeed() is false. Position.fromMap
// otherwise replaces that omission with zero. Preserve it before conversion.
Position driverPositionFromMap(Map<dynamic, dynamic> raw) => Position.fromMap({
      ...raw,
      'speed': sensorSpeed((raw['speed'] as num?)?.toDouble()),
    });

Stream<Position> driverPositionStream(LocationSettings settings) {
  final suffix = _channelSuffix;
  if (suffix == null) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }
  return EventChannel('flutter.baseflow.com/geolocator_updates_$suffix')
      .receiveBroadcastStream(settings.toJson())
      .map((raw) => driverPositionFromMap(raw as Map));
}

int _requestSequence = 0;
Future<Position> driverCurrentPosition(LocationSettings settings) async {
  final suffix = _channelSuffix;
  if (suffix == null) {
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }
  final channel = MethodChannel('flutter.baseflow.com/geolocator_$suffix');
  final requestId =
      'driver-${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
  var request =
      channel.invokeMapMethod<dynamic, dynamic>('getCurrentPosition', {
    ...settings.toJson(),
    if (suffix == 'android') 'requestId': requestId,
  });
  try {
    if (settings.timeLimit != null) {
      request = request.timeout(settings.timeLimit!);
    }
    final raw = await request;
    if (raw == null) throw const PositionUpdateException('No location fix');
    return driverPositionFromMap(raw);
  } on TimeoutException {
    if (suffix == 'android') {
      await channel
          .invokeMethod('cancelGetCurrentPosition', {'requestId': requestId});
    }
    rethrow;
  }
}
