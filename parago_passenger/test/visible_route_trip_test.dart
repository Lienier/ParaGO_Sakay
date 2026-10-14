import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/transport/route_summary.dart';
import 'package:parago_passenger/models/trip/trip_session.dart';
import 'package:parago_passenger/services/visible_route_trip.dart';

void main() {
  const route = RouteSummaryModel(
      id: 'a',
      name: 'Main Route',
      code: 'MAIN',
      direction: 'up',
      status: 'active');
  TripSession trip(String id, String routeId) => TripSession.fromJson({
        '_id': id,
        'routeId': {'_id': routeId, 'name': 'Main Route', 'code': 'MAIN'},
        'status': 'active',
      });
  test('no selected-route jeep never falls back to a jeep from another route',
      () {
    final other = trip('other', 'b');
    expect(
        selectVisibleRouteTrip(
            route: route,
            preferred: other,
            onboard: null,
            candidates: [other],
            isEligible: (_) => true),
        isNull);
  });
  test('route IDs distinguish routes sharing a name and code', () {
    expect(tripMatchesSelectedRoute(trip('other', 'b'), route), isFalse);
  });
  test('wrong preference resolves to an eligible matching route', () {
    final own = trip('own', 'a');
    expect(
        selectVisibleRouteTrip(
            route: route,
            preferred: trip('other', 'b'),
            onboard: null,
            candidates: [own],
            isEligible: (_) => true)?.id,
        'own');
    expect(
        selectVisibleRouteTrip(
            route: route,
            preferred: own,
            onboard: null,
            candidates: [own],
            isEligible: (_) => false),
        isNull);
  });
  test(
      'an existing ride remains visible when its jeep stops accepting requests',
      () {
    final own = trip('own', 'a');
    expect(
        selectVisibleRouteTrip(
            route: route,
            preferred: own,
            onboard: own,
            candidates: [],
            isEligible: (_) => false)?.id,
        'own');
  });
}
