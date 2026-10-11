import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/services/realtime_subscription_registry.dart';

void main() {
  group('driver realtime subscription characterization', () {
    test(
        'route subscriptions restore only after authorization and stop on route change',
        () {
      final registry = RealtimeSubscriptionRegistry();
      expect(registry.addRoute(' route-a '), isTrue);
      expect(registry.addRoute('route-a'), isFalse);
      expect(registry.addRoute(' '), isFalse);
      expect(registry.restorationEvents, isEmpty);
      expect(registry.pendingAuthorizationEvents.single.eventName,
          'subscribe.route');
      registry.markAuthorized('subscribe.route', 'route-a');
      expect(registry.restorationEvents.single.identifier, 'route-a');
      expect(registry.pendingAuthorizationEvents, isEmpty);
      registry.removeRoute('route-a');
      registry.addRoute('route-b');
      expect(registry.restorationEvents, isEmpty);
      registry.reject('subscribe.route', 'route-b');
      expect(registry.pendingAuthorizationEvents, isEmpty);
      registry.addRoute('route-c');
      registry.markAuthorized('subscribe.route', 'route-c');
      registry.clear();
      expect(registry.restorationEvents, isEmpty);
    });

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
