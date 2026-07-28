import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/trip/passenger_jeep_eta.dart';

void main() {
  test('PassengerJeepEta parses Google traffic ETA payload', () {
    final eta = PassengerJeepEta.fromJson({
      'tripId': 'trip-1',
      'jeepneyId': 'jeepney-1',
      'plateNumber': 'ABC 1234',
      'distanceMeters': 2450,
      'durationSeconds': 420,
      'rawDurationSeconds': 360,
      'trafficDelayInSeconds': 60,
      'source': 'google',
      'vehicleLocationLastSeenAt': '2026-07-28T03:30:00.000Z',
      'calculatedAt': '2026-07-28T03:30:05.000Z',
      'expiresAt': '2026-07-28T03:30:30.000Z',
    });

    expect(eta.tripId, 'trip-1');
    expect(eta.plateNumber, 'ABC 1234');
    expect(eta.distanceMeters, 2450);
    expect(eta.durationSeconds, 420);
    expect(eta.trafficDelayInSeconds, 60);
    expect(eta.source, 'google');
    expect(eta.vehicleLocationLastSeenAt, isNotNull);
    expect(eta.expiresAt, isNotNull);
  });

  test('PassengerJeepEta tolerates numeric strings and missing timestamps', () {
    final eta = PassengerJeepEta.fromJson({
      'tripId': 'trip-2',
      'jeepneyId': 'jeepney-2',
      'plateNumber': 'XYZ 9876',
      'distanceMeters': '900',
      'durationSeconds': '180',
      'rawDurationSeconds': '150',
      'trafficDelayInSeconds': '30',
      'source': 'google',
    });

    expect(eta.distanceMeters, 900);
    expect(eta.durationSeconds, 180);
    expect(eta.rawDurationSeconds, 150);
    expect(eta.vehicleLocationLastSeenAt, isNull);
  });
}
