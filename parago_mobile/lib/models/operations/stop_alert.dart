class StopAlertModel {
  const StopAlertModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.routeId,
    required this.rideSessionId,
    required this.status,
    required this.stopRef,
    this.note,
    this.createdAt,
    this.acknowledgedAt,
  });

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String routeId;
  final String rideSessionId;
  final String status;
  final String stopRef;
  final String? note;
  final String? createdAt;
  final String? acknowledgedAt;

  factory StopAlertModel.fromJson(Map<String, dynamic> json) {
    return StopAlertModel(
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      routeId: json['routeId']?.toString() ?? '',
      rideSessionId: json['rideSessionId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      stopRef: json['stopRef']?.toString() ?? '',
      note: json['note']?.toString(),
      createdAt: json['createdAt']?.toString(),
      acknowledgedAt: json['acknowledgedAt']?.toString(),
    );
  }
}
