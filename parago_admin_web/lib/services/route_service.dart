import '../core/network/api_client.dart';
import '../models/transport/route_summary.dart';

class RouteService {
  RouteService(this._client);

  final ApiClient _client;

  Future<List<RouteSummaryModel>> getRoutes({bool useCache = true}) async {
    final data = await _client.getList(path: '/routes', useCache: useCache);
    return data
        .map((entry) =>
            RouteSummaryModel.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<RouteSummaryModel> createRoute(Map<String, dynamic> body) async {
    final response = await _client.request(
      method: 'POST',
      path: '/routes',
      body: body,
    );
    return RouteSummaryModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<RouteSummaryModel> updateRoute(
    String routeId,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.request(
      method: 'PUT',
      path: '/routes/$routeId',
      body: body,
    );
    return RouteSummaryModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<RouteSummaryModel> deactivateRoute(String routeId) async {
    final response = await _client.request(
      method: 'DELETE',
      path: '/routes/$routeId',
    );
    return RouteSummaryModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<RouteSummaryModel> reactivateRoute(String routeId) {
    return updateRoute(routeId, {'status': 'active'});
  }
}
