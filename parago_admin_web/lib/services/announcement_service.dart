import '../core/network/api_client.dart';
import '../models/operations/announcement.dart';

abstract interface class AnnouncementRepository {
  Future<AnnouncementPage> getAdminAnnouncements({
    required int page,
    required int limit,
    String? status,
    String? category,
    String? severity,
    String? audience,
    DateTime? from,
    DateTime? to,
  });

  Future<AnnouncementModel> create(Map<String, dynamic> body);

  Future<AnnouncementModel> update(
    String id,
    Map<String, dynamic> body,
  );

  Future<AnnouncementModel> archive(
    String id, {
    required bool confirmActiveArchive,
  });
}

class AnnouncementService implements AnnouncementRepository {
  AnnouncementService(this._client);

  final ApiClient _client;

  @override
  Future<AnnouncementPage> getAdminAnnouncements({
    required int page,
    required int limit,
    String? status,
    String? category,
    String? severity,
    String? audience,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/announcements/admin',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        if (severity != null && severity.isNotEmpty) 'severity': severity,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
      useCache: false,
    );
    final data = response['data'];
    if (data is! Map) {
      return const AnnouncementPage(
        items: [],
        page: 1,
        limit: 25,
        total: 0,
        totalPages: 0,
      );
    }
    return AnnouncementPage.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<AnnouncementModel> create(Map<String, dynamic> body) async {
    final response = await _client.request(
      method: 'POST',
      path: '/announcements/admin',
      body: body,
      useCache: false,
    );
    return AnnouncementModel.fromJson(
      response['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<AnnouncementModel> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.request(
      method: 'PATCH',
      path: '/announcements/admin/$id',
      body: body,
      useCache: false,
    );
    return AnnouncementModel.fromJson(
      response['data'] as Map<String, dynamic>,
    );
  }

  @override
  Future<AnnouncementModel> archive(
    String id, {
    required bool confirmActiveArchive,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/announcements/admin/$id/archive',
      body: {
        if (confirmActiveArchive) 'confirmActiveArchive': true,
      },
      useCache: false,
    );
    return AnnouncementModel.fromJson(
      response['data'] as Map<String, dynamic>,
    );
  }
}
