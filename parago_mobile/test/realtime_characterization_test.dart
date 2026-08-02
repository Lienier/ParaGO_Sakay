import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/services/realtime_subscription_registry.dart';

void main() {
  group('driver realtime subscription characterization', () {
    test('restores only server-authorized trip subscriptions', () {
      final registry = RealtimeSubscriptionRegistry();

      expect(registry.addTrip(' trip-a '), isTrue);
      expect(registry.addTrip('trip-a'), isFalse);
      expect(registry.addTrip(' '), isFalse);
      expect(registry.restorationEvents, isEmpty);
      expect(
        registry.pendingAuthorizationEvents
            .map((entry) => entry.identifier)
            .toList(),
        <String>['trip-a'],
      );

      registry.markAuthorized('subscribe.trip', 'trip-a');

      final restored = registry.restorationEvents.toList();
      expect(restored, hasLength(1));
      expect(restored.single.eventName, 'subscribe.trip');
      expect(restored.single.identifier, 'trip-a');
    });

    test('unsubscribe and disposal clearing remove restoration events', () {
      final registry = RealtimeSubscriptionRegistry()
        ..addTrip('trip-a')
        ..addTrip('trip-b');
      registry.markAuthorized('subscribe.trip', 'trip-a');
      registry.markAuthorized('subscribe.trip', 'trip-b');

      expect(registry.removeTrip(' trip-a '), isTrue);
      expect(
        registry.restorationEvents.map((entry) => entry.identifier).toList(),
        <String>['trip-b'],
      );

      registry.clear();
      expect(registry.restorationEvents, isEmpty);
      expect(registry.pendingAuthorizationEvents, isEmpty);
    });

    test('rejected trip subscriptions are not retried on reconnect', () {
      final registry = RealtimeSubscriptionRegistry()..addTrip('trip-a');

      registry.reject('subscribe.trip', 'trip-a');

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
      expect(normalizeRealtimePayload(123), isEmpty);
    });
  });
}
