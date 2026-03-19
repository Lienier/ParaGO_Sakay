class TripSession {
  const TripSession({
    required this.id,
    required this.jeepneyId,
    required this.driverId,
    required this.routeId,
    required this.status,
    this.routeName,
    this.routeCode,
    this.jeepneyPlateNumber,
    this.jeepneyName,
    this.driverName,
    this.jeepneyLatitude,
    this.jeepneyLongitude,
    this.startedAt,
    this.endedAt,
    this.acceptRequests,
    this.occupancyCount,
    this.active,
    this.notes,
  });

  final String id;
  final String jeepneyId;
  final String driverId;
  final String routeId;
  final String status;
  final String? routeName;
  final String? routeCode;
  final String? jeepneyPlateNumber;
  final String? jeepneyName;
  final String? driverName;
  final double? jeepneyLatitude;
  final double? jeepneyLongitude;
  final String? startedAt;
  final String? endedAt;
  final bool? acceptRequests;
  final int? occupancyCount;
  final bool? active;
  final String? notes;

  factory TripSession.fromJson(Map<String, dynamic> json) {
    final route = json['routeId'];
    final jeepney = json['jeepneyId'];
    final driver = json['driverId'];
    final jeepneyLocation = jeepney is Map
        ? jeepney['lastKnownLocation']
        : null;
    final coordinates = jeepneyLocation is Map
        ? jeepneyLocation['coordinates']
        : null;
    final jeepneyCoordinates = _readCoordinatePair(coordinates);
    return TripSession(
      id: json['_id']?.toString() ?? '',
      jeepneyId: _readId(jeepney),
      driverId: _readId(driver),
      routeId: _readId(route),
      status: json['status']?.toString() ?? '',
      routeName: _readMapString(route, const ['name']),
      routeCode: _readMapString(route, const ['code']),
      jeepneyPlateNumber: _readMapString(jeepney, const ['plateNumber']),
      jeepneyName: _readMapString(jeepney, const ['jeepneyName', 'vehicleTag']),
      driverName: _readMapString(driver, const ['fullName', 'name']),
      jeepneyLatitude: jeepneyCoordinates?.$2,
      jeepneyLongitude: jeepneyCoordinates?.$1,
      startedAt: json['startedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
      acceptRequests: json['acceptRequests'] as bool?,
      occupancyCount: json['occupancyCount'] as int?,
      active: json['active'] as bool?,
      notes: json['notes']?.toString(),
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

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
