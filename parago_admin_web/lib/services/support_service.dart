import '../core/network/api_client.dart';
import '../models/support/support_message.dart';
import '../models/support/support_thread.dart';

abstract interface class SupportRepository {
  Future<List<SupportThreadModel>> getInboxThreads({
    String? status,
    String? category,
    String? userRole,
    String? assignedAdminId,
    bool includeClosed = false,
  });

  Future<Map<String, dynamic>> getThreadMessages(String threadId);

  Future<Map<String, dynamic>> sendMessage({
    required String threadId,
    required String body,
  });

  Future<Map<String, dynamic>> markRead(String threadId);

  Future<Map<String, dynamic>> assignThread({
    required String threadId,
    required String assignedAdminId,
  });

  Future<Map<String, dynamic>> resolveThread({
    required String threadId,
    String status = 'resolved',
  });

  Future<Map<String, dynamic>> closeThread(
    String threadId, {
    String? reason,
  });

  Future<Map<String, dynamic>> reopenThread(String threadId);
}

class SupportService implements SupportRepository {
  SupportService(this._client);

  final ApiClient _client;

  @override
  Future<List<SupportThreadModel>> getInboxThreads({
    String? status,
    String? category,
    String? userRole,
    String? assignedAdminId,
    bool includeClosed = false,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/support/admin/threads',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
        if (userRole != null && userRole.trim().isNotEmpty)
          'userRole': userRole.trim(),
        if (assignedAdminId != null && assignedAdminId.trim().isNotEmpty)
          'assignedAdminId': assignedAdminId.trim(),
        'includeClosed': includeClosed.toString(),
      },
      useCache: false,
    );
    final data = response['data'];
    if (data is! List) return const <SupportThreadModel>[];
    return data
        .whereType<Map>()
        .map(
            (item) => SupportThreadModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getThreadMessages(String threadId) async {
    final response = await _client.request(
      method: 'GET',
      path: '/support/threads/$threadId/messages',
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  @override
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

  @override
  Future<Map<String, dynamic>> markRead(String threadId) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/threads/$threadId/read',
      body: {},
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> assignThread({
    required String threadId,
    required String assignedAdminId,
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/admin/threads/$threadId/assign',
      body: {'assignedAdminId': assignedAdminId},
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> resolveThread({
    required String threadId,
    String status = 'resolved',
  }) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/support/admin/threads/$threadId/resolve',
      body: {'status': status},
      useCache: false,
    );
    return response['data'] as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> closeThread(String threadId,
      {String? reason}) async {
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

  @override
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
        .map((item) =>
            SupportMessageModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }
}
