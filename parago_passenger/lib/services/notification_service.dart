import '../core/network/api_client.dart';
import '../models/operations/notification.dart';

class NotificationService {
  NotificationService(this._client);

  final ApiClient _client;

  Future<List<NotificationModel>> getMine({bool includeRead = false}) async {
    final data = await _client.getList(
      path: '/notifications/mine',
      queryParameters: {'includeRead': includeRead.toString()},
    );
    return data
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    await _client.request(
      method: 'PATCH',
      path: '/notifications/$notificationId/read',
      body: {},
    );
  }

  Future<void> markAllRead() async {
    await _client
        .request(method: 'PATCH', path: '/notifications/read-all', body: {});
  }
}
