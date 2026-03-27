import 'package:latlong2/latlong.dart';

class RouteSummaryModel {
  const RouteSummaryModel({
    required this.id,
    required this.name,
    required this.code,
    required this.direction,
    required this.status,
    this.description,
    this.pathPoints = const <LatLng>[],
    this.waypointPoints = const <LatLng>[],
    this.stopPoints = const <RouteStopPoint>[],
    this.stopsCount = 0,
    this.originPoint,
    this.destinationPoint,
    this.mapBounds,
    this.distanceMeters,
    this.durationSeconds,
    this.navigationSource,
  });

  final String id;
  final String name;
  final String code;
  final String direction;
  final String status;
  final String? description;
  final List<LatLng> pathPoints;
  final List<LatLng> waypointPoints;
  final List<RouteStopPoint> stopPoints;
  final int stopsCount;
  final LatLng? originPoint;
  final LatLng? destinationPoint;
  final RouteMapBounds? mapBounds;
  final double? distanceMeters;
  final double? durationSeconds;
  final String? navigationSource;

  factory RouteSummaryModel.fromJson(Map<String, dynamic> json) {
    final stops = json['stops'];
    final stopPoints = _parseStopPoints(stops);
    final pathPoints = _parseLinePoints(json['path']);
    final waypointPoints = _parseWaypointPoints(json['waypoints']);
    final navigation = _asMap(json['navigation']);
    final originPoint = _parseLatLng(navigation?['origin']) ??
        _firstPoint(pathPoints, waypointPoints, stopPoints);
    final destinationPoint = _parseLatLng(navigation?['destination']) ??
        _lastPoint(pathPoints, waypointPoints, stopPoints);

    return RouteSummaryModel(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'circular',
      status: json['status']?.toString() ?? 'inactive',
      description: json['description']?.toString(),
      pathPoints: pathPoints,
      waypointPoints: waypointPoints,
      stopPoints: stopPoints,
      stopsCount: stops is List ? stops.length : 0,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      mapBounds: RouteMapBounds.fromJson(navigation?['bounds']),
      distanceMeters: _toDouble(navigation?['distanceMeters']),
      durationSeconds: _toDouble(navigation?['durationSeconds']),
      navigationSource: navigation?['source']?.toString(),
    );
  }

  String get label => code.isEmpty ? name : '$code - $name';

  List<LatLng> get mapPath {
    if (pathPoints.length >= 2) {
      return pathPoints;
    }
    if (waypointPoints.length >= 2) {
      return waypointPoints;
    }
    return stopPoints.map((stop) => stop.position).toList(growable: false);
  }

  List<LatLng> get referencePoints {
    final path = mapPath;
    if (path.isNotEmpty) {
      return path;
    }
    return stopPoints.map((stop) => stop.position).toList(growable: false);
  }

  bool get hasOfflineReadyView => mapPath.length >= 2 && mapBounds != null;
}

class RouteStopPoint {
  const RouteStopPoint({
    required this.name,
    required this.order,
    required this.position,
    this.code,
    this.fare = 0,
  });

  final String name;
  final int order;
  final LatLng position;
  final String? code;
  final double fare;
}

class RouteMapBounds {
  const RouteMapBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  LatLng get center => LatLng((north + south) / 2, (east + west) / 2);

  Map<String, double> toJson() => <String, double>{
        'north': north,
        'south': south,
        'east': east,
        'west': west,
      };

  static RouteMapBounds? fromJson(dynamic value) {
    final map = _asMap(value);
    if (map == null) {
      return null;
    }
    final north = _toDouble(map['north']);
    final south = _toDouble(map['south']);
    final east = _toDouble(map['east']);
    final west = _toDouble(map['west']);
    if (north == null || south == null || east == null || west == null) {
      return null;
    }
    return RouteMapBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  static RouteMapBounds? fromPoints(List<LatLng> points) {
    if (points.isEmpty) {
      return null;
    }

    var north = points.first.latitude;
    var south = points.first.latitude;
    var east = points.first.longitude;
    var west = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude > north) north = point.latitude;
      if (point.latitude < south) south = point.latitude;
      if (point.longitude > east) east = point.longitude;
      if (point.longitude < west) west = point.longitude;
    }

    return RouteMapBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }
}

List<LatLng> _parseLinePoints(dynamic value) {
  final rawCoordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (rawCoordinates is! List) {
    return const <LatLng>[];
  }
  return rawCoordinates
      .map(_parseLineCoordinate)
      .whereType<LatLng>()
      .toList(growable: false);
}

List<LatLng> _parseWaypointPoints(dynamic value) {
  if (value is! List) {
    return const <LatLng>[];
  }
  return value
      .map((entry) => entry is Map ? _parseLatLng(entry['location']) : null)
      .whereType<LatLng>()
      .toList(growable: false);
}

List<RouteStopPoint> _parseStopPoints(dynamic value) {
  if (value is! List) {
    return const <RouteStopPoint>[];
  }
  final points = value
      .map((entry) {
        if (entry is! Map) {
          return null;
        }
        final position = _parseLatLng(entry['location']);
        if (position == null) {
          return null;
        }
        return RouteStopPoint(
          name: entry['name']?.toString() ?? 'Route stop',
          code: entry['code']?.toString(),
          order: int.tryParse(entry['order']?.toString() ?? '') ?? 0,
          fare: _toDouble(entry['fare']) ?? 0,
          position: position,
        );
      })
      .whereType<RouteStopPoint>()
      .toList(growable: false);
  points.sort((a, b) => a.order.compareTo(b.order));
  return points;
}

LatLng? _parseLatLng(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) {
    return null;
  }
  final lng = _toDouble(coordinates[0]);
  final lat = _toDouble(coordinates[1]);
  if (lat == null || lng == null) {
    return null;
  }
  return LatLng(lat, lng);
}

LatLng? _parseLineCoordinate(dynamic value) {
  if (value is! List || value.length < 2) {
    return null;
  }
  final lng = _toDouble(value[0]);
  final lat = _toDouble(value[1]);
  if (lat == null || lng == null) {
    return null;
  }
  return LatLng(lat, lng);
}

Map? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value;
  }
  return null;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

LatLng? _firstPoint(
  List<LatLng> pathPoints,
  List<LatLng> waypointPoints,
  List<RouteStopPoint> stopPoints,
) {
  if (pathPoints.isNotEmpty) return pathPoints.first;
  if (waypointPoints.isNotEmpty) return waypointPoints.first;
  if (stopPoints.isNotEmpty) return stopPoints.first.position;
  return null;
}

LatLng? _lastPoint(
  List<LatLng> pathPoints,
  List<LatLng> waypointPoints,
  List<RouteStopPoint> stopPoints,
) {
  if (pathPoints.isNotEmpty) return pathPoints.last;
  if (waypointPoints.isNotEmpty) return waypointPoints.last;
  if (stopPoints.isNotEmpty) return stopPoints.last.position;
  return null;
}
