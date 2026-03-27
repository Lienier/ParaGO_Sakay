class PickupRequestModel {
  const PickupRequestModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.routeId,
    required this.status,
    this.stopRef,
    this.sourceNote,
    this.pickupLatitude,
    this.pickupLongitude,
    this.expiresAt,
    this.createdAt,
    this.acknowledgedAt,
  });

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String routeId;
  final String status;
  final String? stopRef;
  final String? sourceNote;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String? expiresAt;
  final String? createdAt;
  final String? acknowledgedAt;

  factory PickupRequestModel.fromJson(Map<String, dynamic> json) {
    return PickupRequestModel(
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      routeId: json['routeId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      stopRef: json['stopRef']?.toString(),
      sourceNote: json['sourceNote']?.toString(),
      pickupLatitude: _readLatitude(json['pickupLocation']),
      pickupLongitude: _readLongitude(json['pickupLocation']),
      expiresAt: json['expiresAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
      acknowledgedAt: json['acknowledgedAt']?.toString(),
    );
  }
}

double? _readLatitude(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) {
    return null;
  }
  return double.tryParse(coordinates[1].toString());
}

double? _readLongitude(dynamic value) {
  final coordinates = value is Map<String, dynamic>
      ? value['coordinates']
      : (value is Map ? value['coordinates'] : null);
  if (coordinates is! List || coordinates.length < 2) {
    return null;
  }
  return double.tryParse(coordinates[0].toString());
}
