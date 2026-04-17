import 'package:latlong2/latlong.dart';

class TripSession {
  const TripSession({
    required this.id,
    required this.jeepneyId,
    required this.driverId,
    required this.routeId,
    required this.status,
    this.routeName,
    this.routeCode,
    this.routePathSnapshotPoints = const <LatLng>[],
    this.jeepneyPlateNumber,
    this.jeepneyName,
    this.jeepneyCapacity,
    this.driverName,
    this.jeepneyLatitude,
    this.jeepneyLongitude,
    this.startedAt,
    this.endedAt,
    this.acceptRequests,
    this.occupancyCount,
    this.active,
    this.notes,
    this.operatingMode,
    this.terminalQueueStatus,
    this.terminalQueueNumber,
    this.terminalStopRef,
    this.terminalLatitude,
    this.terminalLongitude,
  });

  final String id;
  final String jeepneyId;
  final String driverId;
  final String routeId;
  final String status;
  final String? routeName;
  final String? routeCode;
  final List<LatLng> routePathSnapshotPoints;
  final String? jeepneyPlateNumber;
  final String? jeepneyName;
  final int? jeepneyCapacity;
  final String? driverName;
  final double? jeepneyLatitude;
  final double? jeepneyLongitude;
  final String? startedAt;
  final String? endedAt;
  final bool? acceptRequests;
  final int? occupancyCount;
  final bool? active;
  final String? notes;
  final String? operatingMode;
  final String? terminalQueueStatus;
  final int? terminalQueueNumber;
  final String? terminalStopRef;
  final double? terminalLatitude;
  final double? terminalLongitude;

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
      routeName: _readMapString(route, const ['name']),
      routeCode: _readMapString(route, const ['code']),
      routePathSnapshotPoints: _readLinePoints(json['routePathSnapshot']),
      jeepneyPlateNumber: _readMapString(jeepney, const ['plateNumber']),
      jeepneyName: _readMapString(jeepney, const ['jeepneyName', 'vehicleTag']),
      jeepneyCapacity: int.tryParse(
        _readMapString(jeepney, const ['capacity']) ?? '',
      ),
      driverName: _readMapString(driver, const ['fullName', 'name']),
      jeepneyLatitude: jeepneyCoordinates?.$2,
      jeepneyLongitude: jeepneyCoordinates?.$1,
      startedAt: json['startedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
      acceptRequests: json['acceptRequests'] as bool?,
      occupancyCount: _toInt(json['occupancyCount']),
      active: json['active'] as bool?,
      notes: json['notes']?.toString(),
      operatingMode: json['operatingMode']?.toString(),
      terminalQueueStatus: json['terminalQueueStatus']?.toString(),
      terminalQueueNumber: _toInt(json['terminalQueueNumber']),
      terminalStopRef: json['terminalStopRef']?.toString(),
      terminalLatitude: _readLatitudeFromPoint(json['terminalLocation']),
      terminalLongitude: _readLongitudeFromPoint(json['terminalLocation']),
    );
  }

  String get routeLabel {
    if ((routeCode ?? '').isNotEmpty && (routeName ?? '').isNotEmpty) {
      return '$routeCode - $routeName';
    }
    return (routeName?.isNotEmpty ?? false) ? routeName! : routeId;
  }

  String get jeepneyLabel {
    if ((jeepneyPlateNumber ?? '').isNotEmpty &&
        (jeepneyName ?? '').isNotEmpty) {
      return '$jeepneyPlateNumber - $jeepneyName';
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
    String? routeName,
    String? routeCode,
    List<LatLng>? routePathSnapshotPoints,
    String? jeepneyPlateNumber,
    String? jeepneyName,
    int? jeepneyCapacity,
    String? driverName,
    double? jeepneyLatitude,
    double? jeepneyLongitude,
    String? startedAt,
    String? endedAt,
    bool? acceptRequests,
    int? occupancyCount,
    bool? active,
    String? notes,
    String? operatingMode,
    String? terminalQueueStatus,
    int? terminalQueueNumber,
    String? terminalStopRef,
    double? terminalLatitude,
    double? terminalLongitude,
  }) {
    return TripSession(
      id: id ?? this.id,
      jeepneyId: jeepneyId ?? this.jeepneyId,
      driverId: driverId ?? this.driverId,
      routeId: routeId ?? this.routeId,
      status: status ?? this.status,
      routeName: routeName ?? this.routeName,
      routeCode: routeCode ?? this.routeCode,
      routePathSnapshotPoints:
          routePathSnapshotPoints ?? this.routePathSnapshotPoints,
      jeepneyPlateNumber: jeepneyPlateNumber ?? this.jeepneyPlateNumber,
      jeepneyName: jeepneyName ?? this.jeepneyName,
      jeepneyCapacity: jeepneyCapacity ?? this.jeepneyCapacity,
      driverName: driverName ?? this.driverName,
      jeepneyLatitude: jeepneyLatitude ?? this.jeepneyLatitude,
      jeepneyLongitude: jeepneyLongitude ?? this.jeepneyLongitude,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      acceptRequests: acceptRequests ?? this.acceptRequests,
      occupancyCount: occupancyCount ?? this.occupancyCount,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      operatingMode: operatingMode ?? this.operatingMode,
      terminalQueueStatus: terminalQueueStatus ?? this.terminalQueueStatus,
      terminalQueueNumber: terminalQueueNumber ?? this.terminalQueueNumber,
      terminalStopRef: terminalStopRef ?? this.terminalStopRef,
      terminalLatitude: terminalLatitude ?? this.terminalLatitude,
      terminalLongitude: terminalLongitude ?? this.terminalLongitude,
    );
  }
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

List<LatLng> _readLinePoints(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List) {
    return const <LatLng>[];
  }
  return coordinates
      .map((entry) {
        if (entry is! List || entry.length < 2) {
          return null;
        }
        final lng = _toDouble(entry[0]);
        final lat = _toDouble(entry[1]);
        if (lat == null || lng == null) {
          return null;
        }
        return LatLng(lat, lng);
      })
      .whereType<LatLng>()
      .toList(growable: false);
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
  if (coordinates is! List || coordinates.length < 2) {
    return null;
  }
  return _toDouble(coordinates[1]);
}

double? _readLongitudeFromPoint(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) {
    return null;
  }
  return _toDouble(coordinates[0]);
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
