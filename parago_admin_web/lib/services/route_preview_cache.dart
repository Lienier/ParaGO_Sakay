import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transport/route_summary.dart';

class RoutePreviewCache {
  static const _prefix = 'parago_route_preview_v2:';

  Future<void> savePreview({
    required String routeId,
    required String routeCode,
    required List<LatLng> points,
  }) {
    return saveSnapshot(
      routeId: routeId,
      routeCode: routeCode,
      points: points,
    );
  }

  Future<void> saveSnapshot({
    String? routeId,
    String? routeCode,
    required List<LatLng> points,
    LatLng? startPoint,
    LatLng? endPoint,
    RouteMapBounds? bounds,
    double? distanceMeters,
    double? durationSeconds,
  }) async {
    if (points.length < 2) return;

    final payload = jsonEncode({
      if (routeId != null && routeId.trim().isNotEmpty)
        'routeId': routeId.trim(),
      if (routeCode != null && routeCode.trim().isNotEmpty)
        'routeCode': routeCode.trim().toUpperCase(),
      'points': points
          .map((point) => <double>[point.longitude, point.latitude])
          .toList(growable: false),
      if (startPoint != null)
        'startPoint': <double>[startPoint.longitude, startPoint.latitude],
      if (endPoint != null)
        'endPoint': <double>[endPoint.longitude, endPoint.latitude],
      if (bounds != null) 'bounds': bounds.toJson(),
      if (distanceMeters != null) 'distanceMeters': distanceMeters,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    });

    final prefs = await SharedPreferences.getInstance();
    for (final key
        in _buildLookupKeys(routeId: routeId, routeCode: routeCode)) {
      await prefs.setString('$_prefix$key', payload);
    }
  }

  Future<CachedRouteSnapshot?> loadSnapshot({
    String? routeId,
    String? routeCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key
        in _buildLookupKeys(routeId: routeId, routeCode: routeCode)) {
      final raw = prefs.getString('$_prefix$key');
      final snapshot = _decodeSnapshot(raw);
      if (snapshot != null && snapshot.points.length >= 2) {
        return snapshot;
      }
    }

    return null;
  }

  Future<List<LatLng>> loadPreview({
    String? routeId,
    String? routeCode,
  }) async {
    final snapshot = await loadSnapshot(routeId: routeId, routeCode: routeCode);
    return snapshot?.points ?? const <LatLng>[];
  }

  List<String> _buildLookupKeys({
    String? routeId,
    String? routeCode,
  }) {
    return <String>[
      if (routeId != null && routeId.trim().isNotEmpty) routeId.trim(),
      if (routeCode != null && routeCode.trim().isNotEmpty)
        routeCode.trim().toUpperCase(),
    ];
  }

  CachedRouteSnapshot? _decodeSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);

    if (decoded is List) {
      final legacyPoints = _decodePoints(decoded);
      if (legacyPoints.length < 2) {
        return null;
      }
      return CachedRouteSnapshot(
        points: legacyPoints,
        startPoint: legacyPoints.first,
        endPoint: legacyPoints.last,
        bounds: RouteMapBounds.fromPoints(legacyPoints),
      );
    }

    if (decoded is! Map) return null;
    final points = _decodePoints(decoded['points']);
    if (points.length < 2) {
      return null;
    }

    return CachedRouteSnapshot(
      routeId: decoded['routeId']?.toString(),
      routeCode: decoded['routeCode']?.toString(),
      points: points,
      startPoint: _decodePoint(decoded['startPoint']) ?? points.first,
      endPoint: _decodePoint(decoded['endPoint']) ?? points.last,
      bounds: RouteMapBounds.fromJson(decoded['bounds']) ??
          RouteMapBounds.fromPoints(points),
      distanceMeters: _toDouble(decoded['distanceMeters']),
      durationSeconds: _toDouble(decoded['durationSeconds']),
    );
  }

  List<LatLng> _decodePoints(dynamic raw) {
    if (raw is! List) return const <LatLng>[];
    return raw.map(_decodePoint).whereType<LatLng>().toList(growable: false);
  }

  LatLng? _decodePoint(dynamic raw) {
    if (raw is! List || raw.length < 2) {
      return null;
    }

    final lng = _toDouble(raw[0]);
    final lat = _toDouble(raw[1]);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class CachedRouteSnapshot {
  const CachedRouteSnapshot({
    this.routeId,
    this.routeCode,
    required this.points,
    this.startPoint,
    this.endPoint,
    this.bounds,
    this.distanceMeters,
    this.durationSeconds,
  });

  final String? routeId;
  final String? routeCode;
  final List<LatLng> points;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final RouteMapBounds? bounds;
  final double? distanceMeters;
  final double? durationSeconds;
}
