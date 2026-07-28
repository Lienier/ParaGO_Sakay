class AnnouncementModel {
  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.severity,
    required this.audiences,
    required this.status,
    required this.revision,
    required this.startsAt,
    this.expiresAt,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.creatorName,
    this.lastEditorName,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final String severity;
  final List<String> audiences;
  final String status;
  final int revision;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? creatorName;
  final String? lastEditorName;

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    String? auditName(dynamic value) {
      if (value is Map) return value['fullName']?.toString();
      return null;
    }

    DateTime? date(dynamic value) => DateTime.tryParse(value?.toString() ?? '');
    return AnnouncementModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general',
      severity: json['severity']?.toString() ?? 'info',
      audiences: (json['audiences'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      status: json['status']?.toString() ?? 'scheduled',
      revision: int.tryParse(json['revision']?.toString() ?? '') ?? 1,
      startsAt: date(json['startsAt']) ?? DateTime.now().toUtc(),
      expiresAt: date(json['expiresAt']),
      publishedAt: date(json['publishedAt']),
      createdAt: date(json['createdAt']),
      updatedAt: date(json['updatedAt']),
      creatorName: auditName(json['creator']),
      lastEditorName: auditName(json['lastEditor']),
    );
  }
}

class AnnouncementPage {
  const AnnouncementPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final List<AnnouncementModel> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  factory AnnouncementPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final pagination = json['pagination'];
    final pageData = pagination is Map
        ? pagination.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};

    int number(String key, int fallback) =>
        int.tryParse(pageData[key]?.toString() ?? '') ?? fallback;

    return AnnouncementPage(
      items: (rawItems is List ? rawItems : const [])
          .whereType<Map>()
          .map(
            (item) => AnnouncementModel.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
      page: number('page', 1),
      limit: number('limit', 25),
      total: number('total', 0),
      totalPages: number('totalPages', 0),
    );
  }
}
