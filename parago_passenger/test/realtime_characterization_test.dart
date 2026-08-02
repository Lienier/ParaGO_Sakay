import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/config/app_config.dart';
import 'package:parago_passenger/models/trip/trip_session.dart';
import 'package:parago_passenger/services/passenger_route_vehicle_batch.dart';
import 'package:parago_passenger/services/passenger_vehicle_reconciliation.dart';
import 'package:parago_passenger/services/realtime_subscription_registry.dart';

TripSession trip({
  required String id,
  required String jeepneyId,
  required String routeId,
  String status = 'active',
  bool? active,
}) {
  return TripSession(
    id: id,
    jeepneyId: jeepneyId,
    driverId: 'driver-$id',
    routeId: routeId,
    status: status,
    active: active,
  );
}

void main() {
  group('passenger realtime subscription characterization', () {
    test('restores only server-authorized route and trip subscriptions', () {
      final registry = RealtimeSubscriptionRegistry();

      expect(registry.addRoute(' route-a '), isTrue);
      expect(registry.addRoute('route-a'), isFalse);
      expect(registry.addTrip(' trip-a '), isTrue);
      expect(registry.addTrip('trip-a'), isFalse);
      expect(registry.addRoute(' '), isFalse);
      expect(registry.restorationEvents, isEmpty);
      expect(
        registry.pendingAuthorizationEvents
            .map((entry) => '${entry.eventName}:${entry.identifier}')
            .toList(),
        <String>[
          'subscribe.route:route-a',
          'subscribe.trip:trip-a',
        ],
      );

      registry.markAuthorized('subscribe.route', 'route-a');
      registry.markAuthorized('subscribe.trip', 'trip-a');

      final restored = registry.restorationEvents
          .map((entry) => '${entry.eventName}:${entry.identifier}')
          .toList();
      expect(
        restored,
        <String>[
          'subscribe.route:route-a',
          'subscribe.trip:trip-a',
        ],
      );
    });

    test('route replacement and rejection prevent unauthorized restoration',
        () {
      final registry = RealtimeSubscriptionRegistry()
        ..addRoute('route-a')
        ..addTrip('trip-a');
      registry.markAuthorized('subscribe.route', 'route-a');
      registry.markAuthorized('subscribe.trip', 'trip-a');

      expect(registry.addRoute('route-b'), isTrue);
      expect(
        registry.restorationEvents.map((entry) => entry.identifier).toList(),
        <String>['trip-a'],
      );
      expect(
        registry.pendingAuthorizationEvents
            .map((entry) => entry.identifier)
            .toList(),
        <String>['route-b'],
      );

      registry.reject('subscribe.route', 'route-b');
      registry.reject('subscribe.trip', 'trip-a');
      expect(registry.restorationEvents, isEmpty);
      expect(registry.pendingAuthorizationEvents, isEmpty);
    });

    test('unsubscribe and disconnect clearing remove all subscription state',
        () {
      final registry = RealtimeSubscriptionRegistry()
        ..addRoute('route-a')
        ..addTrip('trip-a');
      registry.markAuthorized('subscribe.route', 'route-a');
      registry.markAuthorized('subscribe.trip', 'trip-a');

      expect(registry.removeRoute(' route-a '), isTrue);
      expect(
        registry.restorationEvents.map((entry) => entry.eventName).toList(),
        <String>['subscribe.trip'],
      );
      registry.clear();
      expect(registry.restorationEvents, isEmpty);
      expect(registry.pendingAuthorizationEvents, isEmpty);
    });

    test('normalizes dynamic socket payload maps and rejects non-maps', () {
      expect(
        normalizeRealtimePayload(<dynamic, dynamic>{
          1: 'value',
          'tripId': 'trip-a',
        }),
        <String, dynamic>{'1': 'value', 'tripId': 'trip-a'},
      );
      expect(normalizeRealtimePayload('not-a-map'), isEmpty);
    });
  });

  group('passenger vehicle reconciliation characterization', () {
    const policy = PassengerVehicleReconciliationPolicy();
    final receivedAt = DateTime.parse('2026-07-29T08:00:10Z');
    final trips = <TripSession>[
      trip(id: 'trip-a', jeepneyId: 'jeep-a', routeId: 'route-a'),
      trip(id: 'trip-b', jeepneyId: 'jeep-b', routeId: 'route-b'),
      trip(
        id: 'trip-c',
        jeepneyId: 'jeep-c',
        routeId: 'route-c',
        status: 'completed',
      ),
    ];

    test('parses numeric strings and falls back to receive time', () {
      final decision = policy.decide(
        payload: <String, dynamic>{
          'tripId': 'trip-a',
          'latitude': '14.5995',
          'longitude': '120.9816',
          'timestamp': 'invalid',
        },
        trips: trips,
        receivedAt: receivedAt,
      );

      expect(decision.shouldApply, isTrue);
      expect(decision.event!.latitude, 14.5995);
      expect(decision.event!.longitude, 120.9816);
      expect(decision.event!.sampleAt, receivedAt);
    });

    test('matches markers by trip, then jeepney, then live route', () {
      final byTrip = policy.decide(
        payload: <String, dynamic>{
          'tripId': 'trip-b',
          'jeepneyId': 'jeep-a',
          'routeId': 'route-a',
          'latitude': 14.6,
          'longitude': 120.98,
        },
        trips: trips,
        receivedAt: receivedAt,
      );
      expect(byTrip.tripIndex, 1);

      final byJeep = policy.decide(
        payload: <String, dynamic>{
          'jeepneyId': 'jeep-a',
          'routeId': 'route-b',
          'latitude': 14.6,
          'longitude': 120.98,
        },
        trips: trips,
        receivedAt: receivedAt,
      );
      expect(byJeep.tripIndex, 0);

      final byRoute = policy.decide(
        payload: <String, dynamic>{
          'routeId': 'route-b',
          'latitude': 14.6,
          'longitude': 120.98,
        },
        trips: trips,
        receivedAt: receivedAt,
      );
      expect(byRoute.tripIndex, 1);

      final completedRoute = policy.decide(
        payload: <String, dynamic>{
          'routeId': 'route-c',
          'latitude': 14.6,
          'longitude': 120.98,
        },
        trips: trips,
        receivedAt: receivedAt,
      );
      expect(completedRoute.hasMatchingTrip, isFalse);
      expect(completedRoute.shouldApply, isFalse);
    });

    test('invalid coordinates do not reconcile a marker', () {
      final decision = policy.decide(
        payload: <String, dynamic>{
          'tripId': 'trip-a',
          'latitude': 'invalid',
          'longitude': 120.98,
        },
        trips: trips,
        receivedAt: receivedAt,
      );

      expect(decision.hasValidEvent, isFalse);
      expect(decision.shouldApply, isFalse);
    });

    test('KNOWN GAP: older vehicle samples are detected but still applied', () {
      final decision = policy.decide(
        payload: <String, dynamic>{
          'tripId': 'trip-a',
          'latitude': 14.5995,
          'longitude': 120.9816,
          'timestamp': '2026-07-29T08:00:00Z',
        },
        trips: trips,
        receivedAt: receivedAt,
        previousSampleAt: DateTime.parse('2026-07-29T08:00:05Z').toLocal(),
      );

      expect(decision.isOlderThanPrevious, isTrue);
      expect(decision.shouldApply, isTrue);
    });
  });

  group('passenger route vehicle batch protocol', () {
    final trips = <TripSession>[
      trip(id: 'trip-a', jeepneyId: 'jeep-a', routeId: 'route-a'),
      trip(id: 'trip-b', jeepneyId: 'jeep-b', routeId: 'route-a'),
      trip(id: 'trip-c', jeepneyId: 'jeep-c', routeId: 'route-b'),
    ];

    Map<String, dynamic> batch({
      required int sequence,
      String routeId = 'route-a',
      String generatedAt = '2026-07-29T10:00:00.000Z',
      bool snapshot = false,
      List<Map<String, dynamic>>? vehicles,
    }) {
      return <String, dynamic>{
        'routeId': routeId,
        'sequence': sequence,
        'generatedAt': generatedAt,
        if (snapshot) 'snapshot': true,
        'vehicles': vehicles ??
            <Map<String, dynamic>>[
              <String, dynamic>{
                'tripId': 'trip-a',
                'jeepneyId': 'jeep-a',
                'latitude': 14.6,
                'longitude': 120.98,
                'speedMetersPerSecond': 7,
                'headingDegrees': 90,
                'lastSeenAt': '2026-07-29T10:00:00.000Z',
              },
            ],
      };
    }

    test('batched route locations remain disabled by default', () {
      expect(AppConfig.enableRouteLocationBatches, isFalse);
    });

    test('parses valid vehicles and keeps only the newest duplicate jeep', () {
      final parsed = PassengerRouteVehicleBatch.tryParse(
        batch(
          sequence: 1,
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'tripId': 'trip-a',
              'jeepneyId': 'jeep-a',
              'latitude': 14.5,
              'longitude': 120.9,
              'lastSeenAt': '2026-07-29T09:59:59.000Z',
            },
            <String, dynamic>{
              'tripId': 'trip-a',
              'jeepneyId': 'jeep-a',
              'latitude': 14.6,
              'longitude': 121,
              'lastSeenAt': '2026-07-29T10:00:00.000Z',
            },
            <String, dynamic>{
              'tripId': 'trip-b',
              'jeepneyId': 'jeep-b',
              'latitude': 95,
              'longitude': 121,
              'lastSeenAt': '2026-07-29T10:00:00.000Z',
            },
          ],
        ),
      );

      expect(parsed, isNotNull);
      expect(parsed!.vehicles, hasLength(1));
      expect(parsed.vehicles.single.latitude, 14.6);
      expect(parsed.vehicles.single.longitude, 121);
    });

    test('ignores wrong routes, duplicate sequences, and stale vehicle times',
        () {
      final reconciler = PassengerRouteVehicleBatchReconciler();

      final wrongRoute = reconciler.reconcile(
        payload: batch(sequence: 1, routeId: 'route-b'),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(wrongRoute.acceptedSequence, isFalse);

      final first = reconciler.reconcile(
        payload: batch(sequence: 1),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(first.shouldApply, isTrue);
      expect(reconciler.lastSequence, 1);

      final duplicateSequence = reconciler.reconcile(
        payload: batch(sequence: 1),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(duplicateSequence.acceptedSequence, isFalse);

      final staleVehicle = reconciler.reconcile(
        payload: batch(
          sequence: 2,
          generatedAt: '2026-07-29T10:00:01.000Z',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'tripId': 'trip-a',
              'jeepneyId': 'jeep-a',
              'latitude': 14.4,
              'longitude': 120.8,
              'lastSeenAt': '2026-07-29T09:59:59.000Z',
            },
          ],
        ),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(staleVehicle.acceptedSequence, isTrue);
      expect(staleVehicle.acceptedVehicles, isEmpty);
    });

    test('route changes clear sequence and vehicle freshness state', () {
      final reconciler = PassengerRouteVehicleBatchReconciler();
      expect(
        reconciler
            .reconcile(
              payload: batch(sequence: 20),
              selectedRouteId: 'route-a',
              trips: trips,
            )
            .shouldApply,
        isTrue,
      );

      final changedRoute = reconciler.reconcile(
        payload: batch(
          sequence: 1,
          routeId: 'route-b',
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'tripId': 'trip-c',
              'jeepneyId': 'jeep-c',
              'latitude': 14.7,
              'longitude': 121.1,
              'lastSeenAt': '2026-07-29T10:00:01.000Z',
            },
          ],
        ),
        selectedRouteId: 'route-b',
        trips: trips,
      );

      expect(changedRoute.shouldApply, isTrue);
      expect(reconciler.selectedRouteId, 'route-b');
      expect(reconciler.lastSequence, 1);
    });

    test(
        'new reconnect snapshot can reset sequence but an older snapshot cannot',
        () {
      final reconciler = PassengerRouteVehicleBatchReconciler();
      reconciler.reconcile(
        payload: batch(
          sequence: 50,
          generatedAt: '2026-07-29T10:00:10.000Z',
        ),
        selectedRouteId: 'route-a',
        trips: trips,
      );

      final delayedSnapshot = reconciler.reconcile(
        payload: batch(
          sequence: 40,
          generatedAt: '2026-07-29T10:00:09.000Z',
          snapshot: true,
        ),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(delayedSnapshot.acceptedSequence, isFalse);
      expect(reconciler.lastSequence, 50);

      final restartedServerSnapshot = reconciler.reconcile(
        payload: batch(
          sequence: 0,
          generatedAt: '2026-07-29T10:00:11.000Z',
          snapshot: true,
          vehicles: <Map<String, dynamic>>[
            <String, dynamic>{
              'tripId': 'trip-a',
              'jeepneyId': 'jeep-a',
              'latitude': 14.8,
              'longitude': 121.2,
              'lastSeenAt': '2026-07-29T10:00:11.000Z',
            },
          ],
        ),
        selectedRouteId: 'route-a',
        trips: trips,
      );
      expect(restartedServerSnapshot.shouldApply, isTrue);
      expect(reconciler.lastSequence, 0);
    });

    test('parsing remains bounded when a server sends an oversized batch', () {
      final parsed = PassengerRouteVehicleBatch.tryParse(
        batch(
          sequence: 1,
          vehicles: List<Map<String, dynamic>>.generate(
            maxPassengerRouteVehicleBatchSize + 25,
            (index) => <String, dynamic>{
              'tripId': 'trip-$index',
              'jeepneyId': 'jeep-$index',
              'latitude': 14.5,
              'longitude': 120.9,
              'lastSeenAt': '2026-07-29T10:00:00.000Z',
            },
          ),
        ),
      );

      expect(parsed, isNotNull);
      expect(parsed!.vehicles, hasLength(maxPassengerRouteVehicleBatchSize));
    });
  });
}
