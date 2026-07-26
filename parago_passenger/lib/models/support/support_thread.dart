import 'package:latlong2/latlong.dart';

class SupportThreadModel {
  const SupportThreadModel({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.category,
    required this.status,
    this.subject,
    this.lastMessagePreview,
    this.lastMessageSenderRole,
    this.createdAt,
    this.lastMessageAt,
    this.updatedAt,
    this.tripSessionId,
    this.pickupRequestId,
    this.rideSessionId,
    this.routeId,
    this.unreadAdminCount = 0,
    this.unreadUserCount = 0,
    this.creatorName,
    this.creatorEmail,
    this.assignedAdminName,
    this.assignedAdminEmail,
  });

  final String id;
  final String userId;
  final String userRole;
  final String category;
  final String status;
  final String? subject;
  final String? lastMessagePreview;
  final String? lastMessageSenderRole;
  final String? createdAt;
  final String? lastMessageAt;
  final String? updatedAt;
  final String? tripSessionId;
  final String? pickupRequestId;
  final String? rideSessionId;
  final String? routeId;
  final int unreadAdminCount;
  final int unreadUserCount;
  final String? creatorName;
  final String? creatorEmail;
  final String? assignedAdminName;
  final String? assignedAdminEmail;

  factory SupportThreadModel.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['userId']);
    final assignedAdmin = _asMap(json['assignedAdminId']);
    final route = _asMap(json['routeId']);
    return SupportThreadModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      userId: _resolveId(json['userId']),
      userRole: json['userRole']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general_help',
      status: json['status']?.toString() ?? 'open',
      subject: json['subject']?.toString(),
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      lastMessageSenderRole: json['lastMessageSenderRole']?.toString(),
      createdAt: json['createdAt']?.toString(),
      lastMessageAt: json['lastMessageAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      tripSessionId: _resolveId(json['tripSessionId']),
      pickupRequestId: _resolveId(json['pickupRequestId']),
      rideSessionId: _resolveId(json['rideSessionId']),
      routeId: route != null ? _resolveId(route) : _resolveId(json['routeId']),
      unreadAdminCount: int.tryParse(json['unreadAdminCount']?.toString() ?? '') ?? 0,
      unreadUserCount: int.tryParse(json['unreadUserCount']?.toString() ?? '') ?? 0,
      creatorName: user?['fullName']?.toString(),
      creatorEmail: user?['email']?.toString(),
      assignedAdminName: assignedAdmin?['fullName']?.toString(),
      assignedAdminEmail: assignedAdmin?['email']?.toString(),
    );
  }

  String get title {
    final value = subject?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return category.replaceAll('_', ' ');
  }

  String get threadLabel {
    final creator = creatorName?.trim();
    if (creator != null && creator.isNotEmpty) {
      return creator;
    }
    return userRole.toLowerCase();
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
