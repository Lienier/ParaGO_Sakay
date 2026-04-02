import 'pickup_request.dart';

class RideSessionModel {
  const RideSessionModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.pickupRequestId,
    required this.status,
    this.destinationStopRef,
    this.destinationLatitude,
    this.destinationLongitude,
    this.fareSnapshot,
    this.canSendStopAlert,
    this.boardedAt,
    this.endedAt,
  });

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String pickupRequestId;
  final String status;
  final String? destinationStopRef;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final FareSnapshotModel? fareSnapshot;
  final bool? canSendStopAlert;
  final String? boardedAt;
  final String? endedAt;

  double? get estimatedFare => fareSnapshot?.amount;
  String? get fareBoardingStopRef => fareSnapshot?.boardingStopRef;
  String? get fareDestinationStopRef => fareSnapshot?.destinationStopRef;

  factory RideSessionModel.fromJson(Map<String, dynamic> json) {
    return RideSessionModel(
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      pickupRequestId: json['pickupRequestId']?.toString() ?? '',
      destinationStopRef: json['destinationStopRef']?.toString(),
      destinationLatitude: _readLatitude(json['destinationLocation']),
      destinationLongitude: _readLongitude(json['destinationLocation']),
      fareSnapshot: FareSnapshotModel.fromJson(json['fareSnapshot']),
      status: json['status']?.toString() ?? '',
      canSendStopAlert: json['canSendStopAlert'] as bool?,
      boardedAt: json['boardedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
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
