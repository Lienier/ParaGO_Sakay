import '../core/network/api_client.dart';
import '../models/support/support_message.dart';
import '../models/support/support_thread.dart';

class SupportService {
  SupportService(this._client);

  final ApiClient _client;

  Future<List<SupportThreadModel>> getMyThreads({bool includeClosed = false}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/support/threads',
      queryParameters: {'includeClosed': includeClosed.toString()},
      useCache: false,
    );
    final data = response['data'];
    if (data is! List) return const <SupportThreadModel>[];
    return data
        .whereType<Map>()
        .map((item) => SupportThreadModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<Map<String, dynamic>> createThread({
    String? subject,
    required String category,
    required String message,
    String? tripSessionId,
    String? pickupRequestId,
    String? rideSessionId,
    String? routeId,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/support/threads',
      body: {
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
        'category': category,
        'message': message,
        if (tripSessionId != null && tripSessionId.trim().isNotEmpty)
          'tripSessionId': tripSessionId.trim(),
        if (pickupRequestId != null && pickupRequestId.trim().isNotEmpty)
          'pickupRequestId': pickupRequestId.trim(),
        if (rideSessionId != null && rideSessionId.trim().isNotEmpty)
          'rideSessionId': rideSessionId.trim(),
        if (routeId != null && routeId.trim().isNotEmpty) 'routeId': routeId.trim(),
      },
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getThreadMessages(String threadId) async {
    final response = await _client.request(
      method: 'GET',
      path: '/support/threads/$threadId/messages',
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String threadId,
    required String body,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/support/threads/$threadId/messages',
      body: {'body': body},
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markRead(String threadId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/threads/$threadId/read',
      body: {},
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> closeThread(String threadId, {String? reason}) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/threads/$threadId/close',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reopenThread(String threadId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/threads/$threadId/reopen',
      body: {},
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  Future<List<SupportMessageModel>> fetchThreadMessages(String threadId) async {
    final data = await getThreadMessages(threadId);
    final messages = data['messages'];
    if (messages is! List) return const <SupportMessageModel>[];
    return messages
        .whereType<Map>()
        .map((item) => SupportMessageModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }
}
