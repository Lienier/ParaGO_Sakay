import '../user_role.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.requiresLegalAcceptance = false,
    this.legalPolicyVersion,
  });

  final String accessToken;
  final String refreshToken;
  final UserProfile user;
  final bool requiresLegalAcceptance;
  final String? legalPolicyVersion;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      user: UserProfile.fromJson((json['user'] as Map).cast<String, dynamic>()),
      requiresLegalAcceptance: json['requiresLegalAcceptance'] == true ||
          ((json['user'] as Map?)?['legalAccepted'] == false),
      legalPolicyVersion: json['legalPolicyVersion']?.toString(),
    );
  }
}

class UserProfile {
  const UserProfile({
    this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    this.passengerId,
    this.driverId,
    this.adminId,
    this.legalAccepted = true,
  });

  final String? userId;
  final String fullName;
  final String email;
  final UserRole role;
  final String? passengerId;
  final String? driverId;
  final String? adminId;
  final bool legalAccepted;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['_id']?.toString(),
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString()),
      passengerId: json['passengerId']?.toString(),
      driverId: json['driverId']?.toString(),
      adminId: json['adminId']?.toString(),
      legalAccepted: json['legalAccepted'] != false,
    );
  }
}
