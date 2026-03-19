class PickupRequestModel {
  const PickupRequestModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.routeId,
    required this.status,
    this.stopRef,
    this.sourceNote,
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
      expiresAt: json['expiresAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
      acknowledgedAt: json['acknowledgedAt']?.toString(),
    );
  }
}
