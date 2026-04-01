class PassengerProfileModel {
  const PassengerProfileModel({
    required this.fullName,
    required this.email,
    this.phone,
    this.photoUrl,
    this.defaultRouteId,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  final String fullName;
  final String email;
  final String? phone;
  final String? photoUrl;
  final String? defaultRouteId;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  factory PassengerProfileModel.fromResponses({
    required Map<String, dynamic> user,
    required Map<String, dynamic> passenger,
  }) {
    final emergencyContact = passenger['emergencyContact'];
    return PassengerProfileModel(
      fullName: user['fullName']?.toString() ?? '',
      email: user['email']?.toString() ?? '',
      phone: passenger['phone']?.toString(),
      photoUrl: passenger['photoUrl']?.toString(),
      defaultRouteId: passenger['defaultRouteId']?.toString(),
      emergencyContactName:
          emergencyContact is Map ? emergencyContact['name']?.toString() : null,
      emergencyContactPhone: emergencyContact is Map
          ? emergencyContact['phone']?.toString()
          : null,
    );
  }
}
