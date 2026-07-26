class SupportMessageModel {
  const SupportMessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    this.createdAt,
    this.senderName,
    this.senderEmail,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String senderRole;
  final String body;
  final String? createdAt;
  final String? senderName;
  final String? senderEmail;

  factory SupportMessageModel.fromJson(Map<String, dynamic> json) {
    final sender = _asMap(json['senderId']);
    return SupportMessageModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      threadId: (json['threadId'] ?? '').toString(),
      senderId: _resolveId(json['senderId']),
      senderRole: json['senderRole']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: json['createdAt']?.toString(),
      senderName: sender?['fullName']?.toString(),
      senderEmail: sender?['email']?.toString(),
    );
  }
}

String _resolveId(dynamic value) {
  if (value is Map) {
    return (value['_id'] ?? value['id'] ?? '').toString();
  }
  return value?.toString() ?? '';
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}
