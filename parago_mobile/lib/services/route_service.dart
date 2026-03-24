import '../core/network/api_client.dart';
import '../models/transport/route_summary.dart';

class RouteService {
  RouteService(this._client);

  final ApiClient _client;

  Future<List<RouteSummaryModel>> getRoutes() async {
    final data = await _client.getList(path: '/routes');
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
}
