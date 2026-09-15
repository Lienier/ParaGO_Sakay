import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/operations/pickup_request.dart';
import 'package:parago_passenger/models/operations/ride_session.dart';
import 'package:parago_passenger/services/passenger_booking_guard.dart';

void main() {
  final now = DateTime.utc(2026, 9, 15);
  PickupRequestModel booking(String status, DateTime expiry) =>
      PickupRequestModel.fromJson({'_id': 'booking', 'status': status,
        'tripSessionId': 'another-jeep', 'expiresAt': expiry.toIso8601String()});
  RideSessionModel ride(String status) => RideSessionModel.fromJson({
    '_id': 'ride', 'status': status, 'tripSessionId': 'another-jeep',
  });
  test('onboard and waiting journeys block across jeeps, completed rides do not', () {
    for (final status in ['onboard', 'waiting']) {
      expect(passengerBookingBlockedReason(rides: [ride(status)], requests: [], now: now), isNotNull);
    }
    expect(passengerBookingBlockedReason(rides: [ride('completed')], requests: [], now: now), isNull);
  });
  test('pending transfers block, but cancellation and expiry allow a new request', () {
    for (final status in ['pending', 'acknowledged', 'transfer_offered']) {
      expect(passengerBookingBlockedReason(rides: [], requests: [booking(status, now.add(const Duration(minutes: 5)))], now: now), isNotNull);
      expect(passengerBookingBlockedReason(rides: [], requests: [booking(status, now)], now: now), isNull);
    }
    for (final status in ['completed', 'cancelled', 'expired']) {
      expect(passengerBookingBlockedReason(rides: [], requests: [booking(status, now.add(const Duration(minutes: 5)))], now: now), isNull);
    }
  });
}
