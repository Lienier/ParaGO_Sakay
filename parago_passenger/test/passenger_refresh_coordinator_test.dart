import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/services/passenger_refresh_coordinator.dart';

void main() {
  group('passenger domain refresh coordination', () {
    test('coalesces concurrent requests for the same domain', () async {
      final coordinator = PassengerRefreshCoordinator();
      final response = Completer<List<String>>();
      var calls = 0;

      Future<List<String>> load() {
        calls += 1;
        return response.future;
      }

      final first = coordinator.run(PassengerRefreshDomain.trips, load);
      final second = coordinator.run(PassengerRefreshDomain.trips, load);
      expect(calls, 1);

      response.complete(<String>['trip-a']);
      expect((await first).value, <String>['trip-a']);
      expect((await second).value, <String>['trip-a']);
      expect(coordinator.isPending(PassengerRefreshDomain.trips), isFalse);
    });

    test('replacement generation prevents an older HTTP response winning',
        () async {
      final coordinator = PassengerRefreshCoordinator();
      final older = Completer<String>();
      final newer = Completer<String>();

      final oldRequest = coordinator.run(
        PassengerRefreshDomain.bookings,
        () => older.future,
      );
      final newRequest = coordinator.run(
        PassengerRefreshDomain.bookings,
        () => newer.future,
        replacePending: true,
      );

      newer.complete('new');
      older.complete('old');
      expect((await newRequest).isCurrent, isTrue);
      expect((await oldRequest).isCurrent, isFalse);
    });

    test('one failed domain does not block another domain or future retries',
        () async {
      final coordinator = PassengerRefreshCoordinator();
      final trips = coordinator.run(
        PassengerRefreshDomain.trips,
        () async => <String>['trip-a'],
      );
      final failed = coordinator.run<List<String>>(
        PassengerRefreshDomain.notifications,
        () async => throw Exception('notifications unavailable'),
      );

      expect((await trips).value, <String>['trip-a']);
      await expectLater(failed, throwsException);
      final retry = await coordinator.run(
        PassengerRefreshDomain.notifications,
        () async => <String>['notification-a'],
      );
      expect(retry.isCurrent, isTrue);
    });
  });

  group('passenger reconnect reconciliation gate', () {
    test('buffers only the newest vehicle state until snapshot completion', () {
      final gate = PassengerRealtimeReconciliationGate();
      gate.bufferLegacy(<String, dynamic>{
        'tripId': 'trip-a',
        'latitude': 14.5,
      });
      gate.bufferLegacy(<String, dynamic>{
        'tripId': 'trip-a',
        'latitude': 14.6,
      });
      gate.bufferBatch(<String, dynamic>{'sequence': 1});
      gate.bufferBatch(<String, dynamic>{'sequence': 2});

      final buffered = gate.completeSnapshot();
      expect(gate.awaitingSnapshot, isFalse);
      expect(buffered.legacyLocations, hasLength(1));
      expect(buffered.legacyLocations.single['latitude'], 14.6);
      expect(buffered.latestBatch?['sequence'], 2);
    });

    test('disconnect and route changes discard unsafe buffered events', () {
      final gate = PassengerRealtimeReconciliationGate();
      gate.bufferBatch(<String, dynamic>{'routeId': 'route-a'});
      gate.disconnected();
      gate.socketReady();
      gate.bufferBatch(<String, dynamic>{'routeId': 'route-a'});
      gate.routeChanged();

      final buffered = gate.completeSnapshot();
      expect(buffered.latestBatch, isNull);
      expect(buffered.legacyLocations, isEmpty);
    });
  });
}
