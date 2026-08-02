import '../models/trip/trip_session.dart';
import 'realtime_subscription_registry.dart';

class PassengerVehicleLocationEvent {
  const PassengerVehicleLocationEvent({
    required this.tripId,
    required this.routeId,
    required this.jeepneyId,
    required this.latitude,
    required this.longitude,
    required this.sampleAt,
    this.speedMetersPerSecond,
    this.headingDegrees,
  });

  final String tripId;
  final String routeId;
  final String jeepneyId;
  final double latitude;
  final double longitude;
  final DateTime sampleAt;
  final double? speedMetersPerSecond;
  final double? headingDegrees;

  static PassengerVehicleLocationEvent? tryParse(
    dynamic payload, {
    required DateTime receivedAt,
  }) {
    final normalized = normalizeRealtimePayload(payload);
    final latitude = _toDouble(normalized['latitude']);
    final longitude = _toDouble(normalized['longitude']);
    if (latitude == null || longitude == null) {
      return null;
    }

    return PassengerVehicleLocationEvent(
      tripId: normalized['tripId']?.toString() ?? '',
      routeId: normalized['routeId']?.toString() ?? '',
      jeepneyId: normalized['jeepneyId']?.toString() ?? '',
      latitude: latitude,
      longitude: longitude,
      sampleAt: _parseSampleTime(normalized['timestamp'], receivedAt),
      speedMetersPerSecond: _toDouble(
        normalized['speedMetersPerSecond'],
      ),
      headingDegrees: _toDouble(normalized['headingDegrees']),
    );
  }
}

class PassengerVehicleReconciliationDecision {
  const PassengerVehicleReconciliationDecision({
    required this.event,
    required this.tripIndex,
    required this.shouldApply,
    required this.isOlderThanPrevious,
  });

  final PassengerVehicleLocationEvent? event;
  final int tripIndex;
  final bool shouldApply;
  final bool isOlderThanPrevious;

  bool get hasValidEvent => event != null;
  bool get hasMatchingTrip => tripIndex >= 0;
}

class PassengerVehicleReconciliationPolicy {
  const PassengerVehicleReconciliationPolicy();

  PassengerVehicleReconciliationDecision decide({
    required dynamic payload,
    required List<TripSession> trips,
    required DateTime receivedAt,
    DateTime? previousSampleAt,
  }) {
    final event = PassengerVehicleLocationEvent.tryParse(
      payload,
      receivedAt: receivedAt,
    );
    if (event == null) {
      return const PassengerVehicleReconciliationDecision(
        event: null,
        tripIndex: -1,
        shouldApply: false,
        isOlderThanPrevious: false,
      );
    }

    final tripIndex = findTripIndex(trips, event);
    final isOlder =
        previousSampleAt != null && event.sampleAt.isBefore(previousSampleAt);

    // The legacy protocol preserves its existing ordering behavior until the
    // coordinated cutover. Batched events reject stale samples separately.
    return PassengerVehicleReconciliationDecision(
      event: event,
      tripIndex: tripIndex,
      shouldApply: tripIndex >= 0,
      isOlderThanPrevious: isOlder,
    );
  }

  int findTripIndex(
    List<TripSession> trips,
    PassengerVehicleLocationEvent event,
  ) {
    if (event.tripId.isNotEmpty) {
      final match = trips.indexWhere((trip) => trip.id == event.tripId);
      if (match >= 0) {
        return match;
      }
    }
    if (event.jeepneyId.isNotEmpty) {
      final match =
          trips.indexWhere((trip) => trip.jeepneyId == event.jeepneyId);
      if (match >= 0) {
        return match;
      }
    }
    if (event.routeId.isNotEmpty) {
      return trips.indexWhere(
        (trip) =>
            (trip.status == 'active' || trip.active == true) &&
            trip.routeId == event.routeId,
      );
    }
    return -1;
  }
}

DateTime _parseSampleTime(dynamic value, DateTime fallback) {
  if (value is DateTime) {
    return value.toLocal();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  return fallback;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
