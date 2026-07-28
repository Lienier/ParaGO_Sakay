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

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
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
      status: json['status']?.toString() ?? 'published',
      revision: int.tryParse(json['revision']?.toString() ?? '') ?? 1,
      startsAt: date(json['startsAt']) ?? DateTime.now().toUtc(),
      expiresAt: date(json['expiresAt']),
      publishedAt: date(json['publishedAt']),
    );
  }
}
