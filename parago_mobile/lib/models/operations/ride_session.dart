class RideSessionModel {
  const RideSessionModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.pickupRequestId,
    required this.status,
    this.canSendStopAlert,
    this.boardedAt,
    this.endedAt,
  });

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String pickupRequestId;
  final String status;
  final bool? canSendStopAlert;
  final String? boardedAt;
  final String? endedAt;

  factory RideSessionModel.fromJson(Map<String, dynamic> json) {
    return RideSessionModel(
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      pickupRequestId: json['pickupRequestId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      canSendStopAlert: json['canSendStopAlert'] as bool?,
      boardedAt: json['boardedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
    );
  }
}
