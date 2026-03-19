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
}
