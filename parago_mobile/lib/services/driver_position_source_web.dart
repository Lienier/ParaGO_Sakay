import 'dart:async';
import 'dart:js_interop';

import 'package:geolocator/geolocator.dart';
import 'package:web/web.dart' as web;

import 'location_speed.dart';

// geolocator_web 4.1.3 replaces coords.speed=null with zero. Read the raw
// browser fix for both the watch and fallback paths so unknown stays unknown.
Position _position(web.GeolocationPosition fix) {
  final c = fix.coords;
  return Position(
    latitude: c.latitude,
    longitude: c.longitude,
    timestamp: DateTime.fromMillisecondsSinceEpoch(fix.timestamp),
    accuracy: c.accuracy,
    altitude: c.altitude ?? 0,
    altitudeAccuracy: c.altitudeAccuracy ?? 0,
    heading: c.heading ?? -1,
    headingAccuracy: 0,
    speed: sensorSpeed(c.speed),
    speedAccuracy: 0,
  );
}

Exception _error(web.GeolocationPositionError e) => switch (e.code) {
      1 => PermissionDeniedException(e.message),
      3 => TimeoutException(e.message),
      _ => PositionUpdateException(e.message),
    };

web.PositionOptions _options(LocationSettings settings) => web.PositionOptions(
      enableHighAccuracy: true,
      maximumAge: 0,
      // Browser timeouts are milliseconds, not microseconds.
      timeout: settings.timeLimit?.inMilliseconds ?? 86400000,
    );

Stream<Position> driverPositionStream(LocationSettings settings) {
  int? watch;
  late final StreamController<Position> controller;
  controller = StreamController<Position>(onListen: () {
    watch = web.window.navigator.geolocation.watchPosition(
      ((web.GeolocationPosition fix) {
        if (!controller.isClosed) controller.add(_position(fix));
      }).toJS,
      ((web.GeolocationPositionError e) {
        if (!controller.isClosed) controller.addError(_error(e));
      }).toJS,
      _options(settings),
    );
  }, onCancel: () {
    if (watch != null) web.window.navigator.geolocation.clearWatch(watch!);
  });
  return controller.stream;
}

Future<Position> driverCurrentPosition(LocationSettings settings) {
  final result = Completer<Position>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition fix) => result.complete(_position(fix))).toJS,
    ((web.GeolocationPositionError e) => result.completeError(_error(e))).toJS,
    _options(settings),
  );
  return result.future;
}
