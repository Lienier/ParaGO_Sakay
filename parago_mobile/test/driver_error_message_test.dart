import 'package:flutter_test/flutter_test.dart';

import 'package:parago_mobile/core/exceptions/api_exception.dart';
import 'package:parago_mobile/core/utils/driver_error_message.dart';
import 'package:parago_mobile/models/trip/trip_session.dart';

void main() {
  test('maps terminal GPS codes to a reason and corrective action', () {
    final result = DriverErrorMessage.from(ApiException(
      409,
      'Driver is 120 meters from the terminal',
      code: 'OUTSIDE_TERMINAL_RADIUS',
    ));

    expect(result.title, 'Outside terminal area');
    expect(result.message, contains('Move closer'));
    expect(result.message, isNot(contains('120 meters')));
  });

  test('does not expose raw unknown exception text', () {
    final result = DriverErrorMessage.from(StateError('Mongo stack trace secret'));

    expect(result.message, isNot(contains('Mongo')));
    expect(result.message, contains('Refresh'));
  });

  test('route trip status is On route after terminal departure', () {
    final trip = TripSession.fromJson({
      '_id': 'trip',
      'jeepneyId': 'jeep',
      'driverId': 'driver',
      'routeId': 'route',
      'status': 'active',
      'operatingMode': 'route',
      'terminalQueueStatus': 'departed',
      'driverStatus': {
        'state': 'on_route',
        'label': 'On route',
        'detail': 'Terminal departure is complete.',
        'nextAction': 'Accept pickup requests or end the trip.',
      },
    });

    expect(trip.driverState, 'on_route');
    expect(trip.driverStateLabel, 'On route');
    expect(trip.driverNextAction, contains('Accept'));
  });
}
