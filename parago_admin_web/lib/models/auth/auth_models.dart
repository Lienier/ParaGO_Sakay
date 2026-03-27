import '../user_role.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      user: UserProfile.fromJson((json['user'] as Map).cast<String, dynamic>()),
    );
  }
}

class AdminLoginChallenge {
  const AdminLoginChallenge({
    required this.challengeId,
    required this.maskedPhone,
    required this.expiresAt,
    required this.expiresInSeconds,
  });

  final String challengeId;
  final String maskedPhone;
  final DateTime? expiresAt;
  final int expiresInSeconds;

  factory AdminLoginChallenge.fromJson(Map<String, dynamic> json) {
    final expiresAtRaw = json['expiresAt']?.toString();
    return AdminLoginChallenge(
      challengeId: json['challengeId']?.toString() ?? '',
      maskedPhone: json['maskedPhone']?.toString() ?? '',
      expiresAt: expiresAtRaw == null || expiresAtRaw.isEmpty
          ? null
          : DateTime.tryParse(expiresAtRaw),
      expiresInSeconds:
          int.tryParse(json['expiresInSeconds']?.toString() ?? '') ?? 0,
    );
  }
}

class UserProfile {
  const UserProfile({
    this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.passengerId,
    this.driverId,
    this.adminId,
  });

  final String? userId;
  final String fullName;
  final String email;
  final UserRole role;
  final String? phone;
  final String? passengerId;
  final String? driverId;
  final String? adminId;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['_id']?.toString(),
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString()),
      phone: json['phone']?.toString(),
      passengerId: json['passengerId']?.toString(),
      driverId: json['driverId']?.toString(),
      adminId: json['adminId']?.toString(),
    );
  }
}
