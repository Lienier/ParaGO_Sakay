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

  factory RouteSummaryModel.fromJson(Map<String, dynamic> json) {
    final stops = json['stops'];
    final stopPoints = _parseStopPoints(stops);
    return RouteSummaryModel(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'circular',
      status: json['status']?.toString() ?? 'inactive',
      description: json['description']?.toString(),
      pathPoints: _parseLinePoints(json['path']),
      waypointPoints: _parseWaypointPoints(json['waypoints']),
      stopPoints: stopPoints,
      stopsCount: stops is List ? stops.length : 0,
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
}

class RouteStopPoint {
  const RouteStopPoint({
    required this.name,
    required this.order,
    required this.position,
    this.code,
  });

  final String name;
  final int order;
  final LatLng position;
  final String? code;
}

List<LatLng> _parseLinePoints(dynamic value) {
  final rawCoordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (rawCoordinates is! List) {
    return const <LatLng>[];
  }
  return rawCoordinates
      .map(_parseLatLng)
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
  final lng = double.tryParse(coordinates[0].toString());
  final lat = double.tryParse(coordinates[1].toString());
  if (lat == null || lng == null) {
    return null;
  }
  return LatLng(lat, lng);
}
