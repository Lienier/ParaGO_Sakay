import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../core/network/api_client.dart';
import '../models/transport/route_summary.dart';

class LicenseImageUpload {
  const LicenseImageUpload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final List<int> bytes;
  final String filename;
  final String mimeType;

  MultipartFile toMultipartFile() => MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      );
}

class AdminService {
  void _validateReportRange(String fromIso, String toIso) {
    final from = DateTime.tryParse(fromIso);
    final to = DateTime.tryParse(toIso);
    if (from == null ||
        to == null ||
        from.isAfter(to) ||
        to.difference(from) > const Duration(days: 366)) {
      throw ArgumentError(
          'Report range must be ordered and no longer than 366 days');
    }
  }

  AdminService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> dashboard({bool useCache = true}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/dashboard',
      useCache: useCache,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> hybridDispatchBoard(
      {bool useCache = true}) async {
    final response = await _client.request(
        method: 'GET', path: '/admin/hybrid-dispatch', useCache: useCache);
    return response['data'] as Map<String, dynamic>;
  }

  static final Map<String, String> _terminalActionIds = {};
  Future<Map<String, dynamic>> _terminalRequest(
      String path, Map<String, dynamic> body) async {
    final key =
        '$path:${body['direction'] ?? body['skipped'] ?? body['terminalQueueStatus']}';
    final id = _terminalActionIds.putIfAbsent(
        key, () => 'queue-${DateTime.now().microsecondsSinceEpoch}');
    final response = await _client.request(
        method: 'PATCH',
        path: path,
        body: {...body, 'requestId': id},
        useCache: false);
    _terminalActionIds.remove(key);
    return response;
  }

  Future<Map<String, dynamic>> reorderTerminalQueueTrip({
    required String tripId,
    required String direction,
    required String reason,
  }) async {
    final response = await _terminalRequest(
        '/admin/terminal-queue/$tripId/reorder',
        {'direction': direction, 'reason': reason});
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setTerminalQueueSkipped({
    required String tripId,
    required bool skipped,
    required String reason,
  }) async {
    final response = await _terminalRequest(
        '/admin/terminal-queue/$tripId/skip',
        {'skipped': skipped, 'reason': reason});
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setTerminalQueueStatus({
    required String tripId,
    required String terminalQueueStatus,
    required String reason,
  }) async {
    final response = await _terminalRequest(
        '/admin/terminal-queue/$tripId/status',
        {'terminalQueueStatus': terminalQueueStatus, 'reason': reason});
    return response['data'] as Map<String, dynamic>;
  }

  Future<List<dynamic>> recentActivity({int limit = 40}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/recent-activity',
      queryParameters: {'limit': limit},
      useCache: true,
    );
    final data = response['data'];
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<List<dynamic>> getDrivers() async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/drivers',
    );
    final data = response['data'];
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<List<dynamic>> getJeepneys() async {
    final response = await _client.request(
      method: 'GET',
      path: '/jeepneys',
    );
    final data = response['data'];
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> createTerminalIntent({
    required String driverId,
    String? routeId,
    String? jeepneyId,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/drivers/$driverId/terminal-intent',
      body: {
        if (routeId != null) 'routeId': routeId,
        if (jeepneyId != null) 'jeepneyId': jeepneyId,
      },
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDriverAccount({
    required String email,
    required String password,
    required String fullName,
    String? licenseNumber,
    String? employeeNumber,
    String? phone,
    String? routeId,
    required String jeepneyPlateNumber,
    required int jeepneyCapacity,
    required LicenseImageUpload licenseFront,
    required LicenseImageUpload licenseBack,
    String status = 'active',
  }) async {
    final trimmedLicense = licenseNumber?.trim();
    final trimmedEmployee = employeeNumber?.trim();
    final trimmedPhone = phone?.trim();
    final trimmedRouteId = routeId?.trim();
    final trimmedJeepneyPlateNumber = jeepneyPlateNumber.trim().toUpperCase();
    final payload = <String, dynamic>{
      'email': email.trim(),
      'password': password.trim(),
      'fullName': fullName.trim(),
      if (trimmedLicense != null && trimmedLicense.isNotEmpty)
        'licenseNumber': trimmedLicense,
      if (trimmedEmployee != null && trimmedEmployee.isNotEmpty)
        'employeeNumber': trimmedEmployee,
      if (trimmedPhone != null && trimmedPhone.isNotEmpty)
        'phone': trimmedPhone,
      if (trimmedRouteId != null && trimmedRouteId.isNotEmpty)
        'assignedRouteId': trimmedRouteId,
      'jeepney': {
        'plateNumber': trimmedJeepneyPlateNumber,
        'capacity': jeepneyCapacity,
      },
      'status': status,
    };
    final response = await _client.request(
      method: 'POST',
      path: '/admin/drivers',
      body: FormData.fromMap({
        'payload': jsonEncode(payload),
        'licenseFront': licenseFront.toMultipartFile(),
        'licenseBack': licenseBack.toMultipartFile(),
      }),
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDriverLicenseDocuments(
    String driverId,
  ) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/drivers/$driverId/license-documents',
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> replaceDriverLicenseDocument({
    required String driverId,
    required String side,
    required LicenseImageUpload image,
  }) async {
    final response = await _client.request(
      method: 'PUT',
      path: '/admin/drivers/$driverId/license-documents/$side',
      body: FormData.fromMap({
        'licenseDocument': image.toMultipartFile(),
      }),
    );
    return response['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateDriver({
    required String driverId,
    String? licenseNumber,
    String? employeeNumber,
    String? phone,
    String? assignedRouteId,
    String? status,
    String? jeepneyPlateNumber,
    int? jeepneyCapacity,
  }) async {
    final trimmedPlateNumber = jeepneyPlateNumber?.trim().toUpperCase();
    final response = await _client.request(
      method: 'PATCH',
      path: '/admin/drivers/$driverId',
      body: {
        if (licenseNumber != null) 'licenseNumber': licenseNumber,
        if (employeeNumber != null) 'employeeNumber': employeeNumber,
        if (phone != null) 'phone': phone,
        if (assignedRouteId != null) 'assignedRouteId': assignedRouteId,
        if (status != null) 'status': status,
        if (trimmedPlateNumber != null || jeepneyCapacity != null)
          'jeepney': {
            if (trimmedPlateNumber != null) 'plateNumber': trimmedPlateNumber,
            if (jeepneyCapacity != null) 'capacity': jeepneyCapacity,
          },
      },
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> assignDriverJeepney({
    required String driverId,
    String? jeepneyId,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/admin/drivers/$driverId/assign-jeepney',
      body: {'jeepneyId': jeepneyId},
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportRequests({
    required String fromIso,
    required String toIso,
    String? routeId,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/requests',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
        if (routeId != null) 'routeId': routeId,
      },
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportBoarding({
    required String fromIso,
    required String toIso,
    String? routeId,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/boarding',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
        if (routeId != null) 'routeId': routeId,
      },
      useCache: true,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportAlerts({
    required String fromIso,
    required String toIso,
    String? routeId,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/alerts',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
        if (routeId != null) 'routeId': routeId,
      },
      useCache: true,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportTripActivity({
    required String fromIso,
    required String toIso,
    String? routeId,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/trip-activity',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
        if (routeId != null) 'routeId': routeId,
      },
      useCache: true,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportRouteDemand({
    required String fromIso,
    required String toIso,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/route-demand',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
      },
      useCache: true,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reportPassengerFlow({
    required String fromIso,
    required String toIso,
    String? routeId,
    bool useCache = true,
  }) async {
    _validateReportRange(fromIso, toIso);
    final response = await _client.request(
      method: 'GET',
      path: '/reports/passenger-flow',
      queryParameters: {
        'from': fromIso,
        'to': toIso,
        if (routeId != null) 'routeId': routeId,
      },
      useCache: useCache,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<RoutePreviewResult> previewRoute({
    required ({double latitude, double longitude}) startPoint,
    required ({double latitude, double longitude}) endPoint,
    List<({double latitude, double longitude})> guidePoints = const [],
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/route-preview',
      body: {
        'startPoint': {
          'latitude': startPoint.latitude,
          'longitude': startPoint.longitude,
        },
        'endPoint': {
          'latitude': endPoint.latitude,
          'longitude': endPoint.longitude,
        },
        'guidePoints': [
          for (final point in guidePoints)
            {
              'latitude': point.latitude,
              'longitude': point.longitude,
            },
        ],
      },
      useCache: false,
    );

    return RoutePreviewResult.fromJson(
        response['data'] as Map<String, dynamic>);
  }
}

class RoutePreviewResult {
  const RoutePreviewResult({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
    this.rawDurationSeconds,
    this.trafficDelayInSeconds,
    this.source,
  });

  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final double? rawDurationSeconds;
  final double? trafficDelayInSeconds;
  final String? source;

  RouteMapBounds? get bounds => RouteMapBounds.fromPoints(points);

  factory RoutePreviewResult.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    final coordinates = path is Map<String, dynamic>
        ? path['coordinates']
        : (path is Map ? path['coordinates'] : null);

    return RoutePreviewResult(
      points: _parsePreviewPoints(coordinates),
      distanceMeters: _toDouble(json['distanceMeters']),
      durationSeconds: _toDouble(json['durationSeconds']),
      rawDurationSeconds: _toDouble(json['rawDurationSeconds']),
      trafficDelayInSeconds: _toDouble(json['trafficDelayInSeconds']),
      source: json['source']?.toString(),
    );
  }
}

List<LatLng> _parsePreviewPoints(dynamic raw) {
  if (raw is! List) return const <LatLng>[];
  return raw
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

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
