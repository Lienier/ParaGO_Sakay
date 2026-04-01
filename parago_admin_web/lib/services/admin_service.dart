import '../core/network/api_client.dart';
import '../models/trip/trip_session.dart';

class AdminService {
  AdminService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> dashboard() async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/dashboard',
      useCache: true,
    );
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

  Future<List<TripSession>> getTrips() async {
    final data = await _client.getList(path: '/trips', useCache: true);
    return data
        .map((entry) => TripSession.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<List<dynamic>> getJeepneys() async {
    final response = await _client.request(
      method: 'GET',
      path: '/jeepneys',
    );
    final data = response['data'];
    return data is List<dynamic> ? data : <dynamic>[];
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
    bool isVerified = false,
    String status = 'active',
  }) async {
    final trimmedLicense = licenseNumber?.trim();
    final trimmedEmployee = employeeNumber?.trim();
    final trimmedPhone = phone?.trim();
    final trimmedRouteId = routeId?.trim();
    final trimmedJeepneyPlateNumber = jeepneyPlateNumber.trim().toUpperCase();
    final response = await _client.request(
      method: 'POST',
      path: '/admin/drivers',
      body: {
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
        'isVerified': isVerified,
        'status': status,
      },
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateDriver({
    required String driverId,
    String? licenseNumber,
    String? employeeNumber,
    String? phone,
    bool? isVerified,
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
        if (isVerified != null) 'isVerified': isVerified,
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

  Future<TripSession> createTrip({
    required String driverId,
    required String jeepneyId,
    required String routeId,
    String status = 'scheduled',
    String? notes,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/trips',
      body: {
        'driverId': driverId,
        'jeepneyId': jeepneyId,
        'routeId': routeId,
        'status': status,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return TripSession.fromJson(response['data'] as Map<String, dynamic>);
  }
}
