import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../models/transport/route_summary.dart';

class OpenStreetMapRoutingService {
  OpenStreetMapRoutingService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://router.project-osrm.org',
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {
              'Accept': 'application/json',
            },
          ),
        );

  final Dio _dio;

  Future<OpenStreetMapRouteResult> buildDrivingRoute({
    required LatLng startPoint,
    required LatLng endPoint,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/route/v1/driving/'
      '${startPoint.longitude},${startPoint.latitude};'
      '${endPoint.longitude},${endPoint.latitude}',
      queryParameters: const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': false,
      },
    );

    final payload = response.data ?? <String, dynamic>{};
    final code = payload['code']?.toString();
    if (code != null && code.toLowerCase() != 'ok') {
      throw Exception(
          payload['message']?.toString() ?? 'OSM routing request failed.');
    }

    final routes = payload['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw Exception('No road-following route was returned.');
    }

    final route = routes.first as Map;
    final geometry = route['geometry'];
    final points = _decodeGeoJsonCoordinates(
      geometry is Map ? geometry['coordinates'] : null,
    );

    if (points.length < 2) {
      throw Exception('Route geometry could not be decoded.');
    }

    return OpenStreetMapRouteResult(
      points: points,
      distanceMeters: _toDouble(route['distance']),
      durationSeconds: _toDouble(route['duration']),
      bounds: RouteMapBounds.fromPoints(points),
    );
  }

  void dispose() {
    _dio.close(force: true);
  }

  List<LatLng> _decodeGeoJsonCoordinates(dynamic coordinates) {
    if (coordinates is! List) {
      return const <LatLng>[];
    }

    final points = <LatLng>[];
    for (final entry in coordinates) {
      if (entry is! List || entry.length < 2) continue;
      final lng = _toDouble(entry[0]);
      final lat = _toDouble(entry[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class OpenStreetMapRouteResult {
  const OpenStreetMapRouteResult({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
    this.bounds,
  });

  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final RouteMapBounds? bounds;
}
