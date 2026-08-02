import '../models/trip/trip_session.dart';
import 'passenger_vehicle_reconciliation.dart';
import 'realtime_subscription_registry.dart';

const int maxPassengerRouteVehicleBatchSize = 100;

class PassengerRouteVehicleBatch {
  const PassengerRouteVehicleBatch({
    required this.routeId,
    required this.sequence,
    required this.generatedAt,
    required this.vehicles,
    required this.snapshot,
  });

  final String routeId;
  final int sequence;
  final DateTime generatedAt;
  final List<PassengerVehicleLocationEvent> vehicles;
  final bool snapshot;

  static PassengerRouteVehicleBatch? tryParse(
    dynamic payload,
  ) {
    final normalized = normalizeRealtimePayload(payload);
    final routeId = normalized['routeId']?.toString().trim() ?? '';
    final sequence = _toInt(normalized['sequence']);
    final generatedAt = _toDateTime(normalized['generatedAt']);
    final rawVehicles = normalized['vehicles'];
    if (routeId.isEmpty ||
        sequence == null ||
        sequence < 0 ||
        generatedAt == null ||
        rawVehicles is! List) {
      return null;
    }

    final byJeepney = <String, PassengerVehicleLocationEvent>{};
    for (final rawVehicle
        in rawVehicles.take(maxPassengerRouteVehicleBatchSize)) {
      final vehicle = _parseVehicle(
        rawVehicle,
        routeId: routeId,
      );
      if (vehicle == null) continue;
      final previous = byJeepney[vehicle.jeepneyId];
      if (previous == null || vehicle.sampleAt.isAfter(previous.sampleAt)) {
        byJeepney[vehicle.jeepneyId] = vehicle;
      }
    }

    return PassengerRouteVehicleBatch(
      routeId: routeId,
      sequence: sequence,
      generatedAt: generatedAt,
      vehicles: List.unmodifiable(byJeepney.values),
      snapshot: normalized['snapshot'] == true,
    );
  }
}

class PassengerRouteVehicleBatchDecision {
  const PassengerRouteVehicleBatchDecision({
    required this.batch,
    required this.acceptedVehicles,
    required this.unmatchedVehicleCount,
    required this.acceptedSequence,
  });

  final PassengerRouteVehicleBatch? batch;
  final List<PassengerVehicleLocationEvent> acceptedVehicles;
  final int unmatchedVehicleCount;
  final bool acceptedSequence;

  bool get shouldApply =>
      acceptedSequence && acceptedVehicles.isNotEmpty && batch != null;
}

class PassengerRouteVehicleBatchReconciler {
  String? _selectedRouteId;
  int? _lastSequence;
  DateTime? _lastGeneratedAt;
  final Map<String, DateTime> _lastVehicleSampleAt = <String, DateTime>{};

  int? get lastSequence => _lastSequence;
  String? get selectedRouteId => _selectedRouteId;

  void selectRoute(String? routeId) {
    final normalized = routeId?.trim() ?? '';
    final next = normalized.isEmpty ? null : normalized;
    if (next == _selectedRouteId) return;
    _selectedRouteId = next;
    _lastSequence = null;
    _lastGeneratedAt = null;
    _lastVehicleSampleAt.clear();
  }

  void clear() {
    _selectedRouteId = null;
    _lastSequence = null;
    _lastGeneratedAt = null;
    _lastVehicleSampleAt.clear();
  }

  PassengerRouteVehicleBatchDecision reconcile({
    required dynamic payload,
    required String? selectedRouteId,
    required List<TripSession> trips,
  }) {
    selectRoute(selectedRouteId);
    final batch = PassengerRouteVehicleBatch.tryParse(payload);
    if (batch == null || batch.routeId != _selectedRouteId) {
      return PassengerRouteVehicleBatchDecision(
        batch: batch,
        acceptedVehicles: const <PassengerVehicleLocationEvent>[],
        unmatchedVehicleCount: 0,
        acceptedSequence: false,
      );
    }

    final previousSequence = _lastSequence;
    final sequenceAccepted = batch.snapshot
        ? _lastGeneratedAt == null ||
            !batch.generatedAt.isBefore(_lastGeneratedAt!)
        : previousSequence == null || batch.sequence > previousSequence;
    if (!sequenceAccepted) {
      return PassengerRouteVehicleBatchDecision(
        batch: batch,
        acceptedVehicles: const <PassengerVehicleLocationEvent>[],
        unmatchedVehicleCount: 0,
        acceptedSequence: false,
      );
    }

    _lastSequence = batch.sequence;
    _lastGeneratedAt = batch.generatedAt;
    const policy = PassengerVehicleReconciliationPolicy();
    final accepted = <PassengerVehicleLocationEvent>[];
    var unmatched = 0;
    for (final vehicle in batch.vehicles) {
      final previousSample = _lastVehicleSampleAt[vehicle.jeepneyId];
      if (previousSample != null && !vehicle.sampleAt.isAfter(previousSample)) {
        continue;
      }
      if (policy.findTripIndex(trips, vehicle) < 0) {
        unmatched += 1;
        continue;
      }
      _lastVehicleSampleAt[vehicle.jeepneyId] = vehicle.sampleAt;
      accepted.add(vehicle);
    }

    return PassengerRouteVehicleBatchDecision(
      batch: batch,
      acceptedVehicles: List.unmodifiable(accepted),
      unmatchedVehicleCount: unmatched,
      acceptedSequence: true,
    );
  }
}

PassengerVehicleLocationEvent? _parseVehicle(
  dynamic payload, {
  required String routeId,
}) {
  final normalized = normalizeRealtimePayload(payload);
  final tripId = normalized['tripId']?.toString().trim() ?? '';
  final jeepneyId = normalized['jeepneyId']?.toString().trim() ?? '';
  final latitude = _toDouble(normalized['latitude']);
  final longitude = _toDouble(normalized['longitude']);
  final lastSeenAt = _toDateTime(normalized['lastSeenAt']);
  final speed = _toDouble(normalized['speedMetersPerSecond']);
  final heading = _toDouble(normalized['headingDegrees']);
  if (tripId.isEmpty ||
      jeepneyId.isEmpty ||
      latitude == null ||
      longitude == null ||
      lastSeenAt == null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180 ||
      (speed != null && (speed < 0 || !speed.isFinite)) ||
      (heading != null &&
          (!heading.isFinite || heading < 0 || heading > 360))) {
    return null;
  }

  return PassengerVehicleLocationEvent(
    tripId: tripId,
    routeId: routeId,
    jeepneyId: jeepneyId,
    latitude: latitude,
    longitude: longitude,
    sampleAt: lastSeenAt,
    speedMetersPerSecond: speed,
    headingDegrees: heading,
  );
}

DateTime? _toDateTime(dynamic value) {
  if (value is DateTime) return value.toLocal();
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value);
  return null;
}
