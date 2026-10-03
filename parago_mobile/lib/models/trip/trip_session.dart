import 'package:latlong2/latlong.dart';

const _unchanged = Object();

class TripSession {
  const TripSession({
    required this.id,
    required this.jeepneyId,
    required this.driverId,
    required this.routeId,
    required this.status,
    this.routePathSnapshotPoints = const <LatLng>[],
    this.routeName,
    this.routeCode,
    this.jeepneyPlateNumber,
    this.jeepneyName,
    this.jeepneyCapacity,
    this.driverName,
    this.jeepneyLatitude,
    this.jeepneyLongitude,
    this.startedAt,
    this.endedAt,
    this.acceptRequests,
    this.inactivityPausedAt,
    this.terminalSummary,
    this.snapshotUpdatedAt,
    this.manualOccupancyCount,
    this.occupancyCount,
    this.active,
    this.notes,
    this.operatingMode,
    this.terminalQueueStatus,
    this.terminalQueueNumber,
    this.terminalStopRef,
    this.terminalLatitude,
    this.terminalLongitude,
    this.driverStatus,
  });

  final String id;
  final String jeepneyId;
  final String driverId;
  final String routeId;
  final String status;
  final List<LatLng> routePathSnapshotPoints;
  final String? routeName;
  final String? routeCode;
  final String? jeepneyPlateNumber;
  final String? jeepneyName;
  final int? jeepneyCapacity;
  final String? driverName;
  final double? jeepneyLatitude;
  final double? jeepneyLongitude;
  final String? startedAt;
  final String? endedAt;
  final bool? acceptRequests;
  final String? inactivityPausedAt;
  final Map<String, dynamic>? terminalSummary;
  final DateTime? snapshotUpdatedAt;
  bool isNewerThan(TripSession other) =>
      snapshotUpdatedAt != null &&
      (other.snapshotUpdatedAt == null ||
          snapshotUpdatedAt!.isAfter(other.snapshotUpdatedAt!));

  /// Returns true when this local snapshot should win over an incoming one.
  /// Equal timestamps can occur when a realtime event and a refresh describe
  /// the same write; the later lifecycle state must not be rolled back.
  bool shouldKeepOver(TripSession incoming) {
    final currentAt = snapshotUpdatedAt;
    final incomingAt = incoming.snapshotUpdatedAt;
    if (currentAt != null && incomingAt != null) {
      if (currentAt.isAfter(incomingAt)) return true;
      if (incomingAt.isAfter(currentAt)) return false;
    } else if (currentAt != null && incomingAt == null) {
      return true;
    } else if (currentAt == null && incomingAt != null) {
      return false;
    }
    return _stateRank(driverState) > _stateRank(incoming.driverState);
  }

  final int? manualOccupancyCount;
  final int? occupancyCount;
  final bool? active;
  final String? notes;
  final String? operatingMode;
  final String? terminalQueueStatus;
  final int? terminalQueueNumber;
  final String? terminalStopRef;
  final double? terminalLatitude;
  final double? terminalLongitude;
  final Map<String, dynamic>? driverStatus;

  String get driverState =>
      driverStatus?['state']?.toString() ??
      (status == 'completed'
          ? 'completed'
          : status == 'cancelled'
              ? 'cancelled'
              : operatingMode == 'route' || terminalQueueStatus == 'departed'
                  ? 'on_route'
                  : terminalQueueStatus == 'loading'
                      ? 'loading'
                      : terminalQueueStatus == 'waiting' ||
                              terminalQueueStatus == 'skipped'
                          ? 'waiting'
                          : 'driving_to_terminal');

  String get driverStateLabel =>
      driverStatus?['label']?.toString() ??
      (driverState == 'on_route'
          ? 'On route'
          : driverState == 'completed'
              ? 'Completed'
              : driverState == 'cancelled'
                  ? 'Cancelled'
                  : driverState == 'loading'
                      ? 'Loading'
                      : driverState == 'waiting'
                          ? 'Waiting in terminal queue'
                          : 'Driving to terminal');

  String? get driverStateDetail => driverStatus?['detail']?.toString();
  String? get driverNextAction => driverStatus?['nextAction']?.toString();

  factory TripSession.fromJson(Map<String, dynamic> json) {
    final route = json['routeId'];
    final jeepney = json['jeepneyId'];
    final driver = json['driverId'];
    final jeepneyLocation =
        jeepney is Map ? jeepney['lastKnownLocation'] : null;
    final coordinates =
        jeepneyLocation is Map ? jeepneyLocation['coordinates'] : null;
    final jeepneyCoordinates = _readCoordinatePair(coordinates);
    return TripSession(
      id: json['_id']?.toString() ?? '',
      jeepneyId: _readId(jeepney),
      driverId: _readId(driver),
      routeId: _readId(route),
      status: json['status']?.toString() ?? '',
      routePathSnapshotPoints: _readLinePoints(json['routePathSnapshot']),
      routeName: _readMapString(route, const ['name']),
      routeCode: _readMapString(route, const ['code']),
      jeepneyPlateNumber: _readMapString(jeepney, const ['plateNumber']),
      jeepneyName: _readMapString(jeepney, const ['jeepneyName', 'vehicleTag']),
      jeepneyCapacity: _toInt(
        jeepney is Map ? jeepney['capacity'] : null,
      ),
      driverName: _readMapString(driver, const ['fullName', 'name']),
      jeepneyLatitude: jeepneyCoordinates?.$2,
      jeepneyLongitude: jeepneyCoordinates?.$1,
      startedAt: json['startedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
      acceptRequests: json['acceptRequests'] as bool?,
      inactivityPausedAt: json['inactivityPausedAt']?.toString(),
      terminalSummary: json['terminalSummary'] is Map
          ? Map<String, dynamic>.from(json['terminalSummary'] as Map)
          : null,
      snapshotUpdatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      manualOccupancyCount: _toInt(json['manualOccupancyCount']),
      occupancyCount: _toInt(json['occupancyCount']),
      active: json['active'] as bool?,
      notes: json['notes']?.toString(),
      operatingMode: json['operatingMode']?.toString(),
      terminalQueueStatus: json['terminalQueueStatus']?.toString(),
      terminalQueueNumber:
          int.tryParse(json['terminalQueueNumber']?.toString() ?? ''),
      terminalStopRef: json['terminalStopRef']?.toString(),
      terminalLatitude: _readLatitudeFromPoint(json['terminalLocation']),
      terminalLongitude: _readLongitudeFromPoint(json['terminalLocation']),
      driverStatus: json['driverStatus'] is Map
          ? Map<String, dynamic>.from(json['driverStatus'] as Map)
          : null,
    );
  }

  String get routeLabel {
    if ((routeCode ?? '').isNotEmpty && (routeName ?? '').isNotEmpty) {
      return '$routeCode · $routeName';
    }
    return (routeName?.isNotEmpty ?? false) ? routeName! : routeId;
  }

  String get jeepneyLabel {
    if ((jeepneyPlateNumber ?? '').isNotEmpty &&
        (jeepneyName ?? '').isNotEmpty) {
      return '$jeepneyPlateNumber · $jeepneyName';
    }
    if ((jeepneyPlateNumber ?? '').isNotEmpty) return jeepneyPlateNumber!;
    if ((jeepneyName ?? '').isNotEmpty) return jeepneyName!;
    return jeepneyId;
  }

  TripSession copyWith({
    String? id,
    String? jeepneyId,
    String? driverId,
    String? routeId,
    String? status,
    List<LatLng>? routePathSnapshotPoints,
    String? routeName,
    String? routeCode,
    String? jeepneyPlateNumber,
    String? jeepneyName,
    int? jeepneyCapacity,
    String? driverName,
    double? jeepneyLatitude,
    double? jeepneyLongitude,
    String? startedAt,
    String? endedAt,
    bool? acceptRequests,
    int? manualOccupancyCount,
    int? occupancyCount,
    bool? active,
    String? notes,
    String? operatingMode,
    String? terminalQueueStatus,
    Object? terminalQueueNumber = _unchanged,
    Object? terminalStopRef = _unchanged,
    Object? terminalLatitude = _unchanged,
    Object? terminalLongitude = _unchanged,
    Object? driverStatus = _unchanged,
    Object? inactivityPausedAt = _unchanged,
    Object? terminalSummary = _unchanged,
    Object? snapshotUpdatedAt = _unchanged,
    bool clearDriverStatus = false,
    bool clearInactivityPausedAt = false,
    bool clearTerminalSummary = false,
    bool clearSnapshotUpdatedAt = false,
  }) {
    return TripSession(
      id: id ?? this.id,
      jeepneyId: jeepneyId ?? this.jeepneyId,
      driverId: driverId ?? this.driverId,
      routeId: routeId ?? this.routeId,
      status: status ?? this.status,
      routePathSnapshotPoints:
          routePathSnapshotPoints ?? this.routePathSnapshotPoints,
      routeName: routeName ?? this.routeName,
      routeCode: routeCode ?? this.routeCode,
      jeepneyPlateNumber: jeepneyPlateNumber ?? this.jeepneyPlateNumber,
      jeepneyName: jeepneyName ?? this.jeepneyName,
      jeepneyCapacity: jeepneyCapacity ?? this.jeepneyCapacity,
      driverName: driverName ?? this.driverName,
      jeepneyLatitude: jeepneyLatitude ?? this.jeepneyLatitude,
      jeepneyLongitude: jeepneyLongitude ?? this.jeepneyLongitude,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      acceptRequests: acceptRequests ?? this.acceptRequests,
      inactivityPausedAt: clearInactivityPausedAt
          ? null
          : identical(inactivityPausedAt, _unchanged)
              ? this.inactivityPausedAt
              : inactivityPausedAt as String?,
      terminalSummary: clearTerminalSummary
          ? null
          : identical(terminalSummary, _unchanged)
              ? this.terminalSummary
              : terminalSummary as Map<String, dynamic>?,
      snapshotUpdatedAt: clearSnapshotUpdatedAt
          ? null
          : identical(snapshotUpdatedAt, _unchanged)
              ? this.snapshotUpdatedAt
              : snapshotUpdatedAt as DateTime?,
      manualOccupancyCount: manualOccupancyCount ?? this.manualOccupancyCount,
      occupancyCount: occupancyCount ?? this.occupancyCount,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      operatingMode: operatingMode ?? this.operatingMode,
      terminalQueueStatus: terminalQueueStatus ?? this.terminalQueueStatus,
      terminalQueueNumber: identical(terminalQueueNumber, _unchanged)
          ? this.terminalQueueNumber
          : terminalQueueNumber as int?,
      terminalStopRef: identical(terminalStopRef, _unchanged)
          ? this.terminalStopRef
          : terminalStopRef as String?,
      terminalLatitude: identical(terminalLatitude, _unchanged)
          ? this.terminalLatitude
          : terminalLatitude as double?,
      terminalLongitude: identical(terminalLongitude, _unchanged)
          ? this.terminalLongitude
          : terminalLongitude as double?,
      driverStatus: identical(driverStatus, _unchanged)
          ? (clearDriverStatus ? null : this.driverStatus)
          : driverStatus as Map<String, dynamic>?,
    );
  }
}

int _stateRank(String state) => switch (state) {
      'scheduled' => 0,
      'driving_to_terminal' => 1,
      'waiting' => 2,
      'loading' => 3,
      'on_route' => 4,
      'completed' => 5,
      _ => 0,
    };

List<LatLng> _readLinePoints(dynamic value) {
  final coordinates = value is Map ? value['coordinates'] : null;
  if (coordinates is! List) return const <LatLng>[];

  return coordinates
      .map((entry) => _readLatLng(entry))
      .whereType<LatLng>()
      .toList(growable: false);
}

LatLng? _readLatLng(dynamic coordinates) {
  if (coordinates is! List || coordinates.length < 2) return null;
  final lng = _toDouble(coordinates[0]);
  final lat = _toDouble(coordinates[1]);
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

String _readId(dynamic value) {
  if (value is Map) return value['_id']?.toString() ?? '';
  return value?.toString() ?? '';
}

String? _readMapString(dynamic value, List<String> keys) {
  if (value is! Map) return null;
  for (final key in keys) {
    final match = value[key];
    if (match != null && match.toString().trim().isNotEmpty) {
      return match.toString();
    }
  }
  return null;
}

(double, double)? _readCoordinatePair(dynamic coordinates) {
  if (coordinates is! List || coordinates.length < 2) return null;
  final first = _toDouble(coordinates[0]);
  final second = _toDouble(coordinates[1]);
  if (first == null || second == null) return null;
  return (first, second);
}

double? _readLatitudeFromPoint(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) return null;
  return _toDouble(coordinates[1]);
}

double? _readLongitudeFromPoint(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) return null;
  return _toDouble(coordinates[0]);
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
