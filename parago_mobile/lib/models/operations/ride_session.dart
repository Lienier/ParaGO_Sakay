import 'pickup_request.dart';

class RideSessionModel {
  const RideSessionModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.pickupRequestId,
    required this.status,
    required this.pickupType,
    this.partySize = 1,
    this.boardedCount = 1,
    this.remainingCount = 1,
    this.revision = 0,
    this.regularTotal,
    this.boardingMethod = 'manual',
    this.destinationStopRef,
    this.destinationLatitude,
    this.destinationLongitude,
    this.fareSnapshot,
    this.canSendStopAlert,
    this.offboardingMethod,
    this.boardedAt,
    this.endedAt,
    this.passengerDisplayName,
  });

  final int partySize;
  final int boardedCount;
  final int remainingCount;
  final int revision;
  final double? regularTotal;
  bool get isGroup => partySize > 1;
  int get onboardCount => status == 'onboard' ? remainingCount : 0;

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String pickupRequestId;
  final String status;
  final String pickupType;
  final String boardingMethod;
  final String? destinationStopRef;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final FareSnapshotModel? fareSnapshot;
  final bool? canSendStopAlert;
  final String? offboardingMethod;
  final String? boardedAt;
  final String? endedAt;
  final String? passengerDisplayName;

  String get passengerLabel => (passengerDisplayName ?? '').trim().isEmpty
      ? 'Passenger'
      : passengerDisplayName!.trim();
  String get bookingLabel {
    final value = pickupRequestId.isEmpty ? id : pickupRequestId;
    return value.length <= 8
        ? value.toUpperCase()
        : value.substring(value.length - 8).toUpperCase();
  }

  double? get estimatedFare => fareSnapshot?.amount;

  factory RideSessionModel.fromJson(Map<String, dynamic> json) {
    return RideSessionModel(
      partySize: (json['partySize'] as num?)?.toInt() ?? 1,
      boardedCount: (json['boardedCount'] as num?)?.toInt() ?? 1,
      remainingCount: json['status'] == 'completed'
          ? 0
          : (json['remainingCount'] as num?)?.toInt() ?? 1,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      regularTotal: (json['regularTotal'] as num?)?.toDouble(),
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      pickupRequestId: json['pickupRequestId']?.toString() ?? '',
      pickupType: json['pickupType']?.toString() ?? 'roadside',
      boardingMethod: json['boardingMethod']?.toString() ?? 'manual',
      destinationStopRef: json['destinationStopRef']?.toString(),
      destinationLatitude: _readLatitude(json['destinationLocation']),
      destinationLongitude: _readLongitude(json['destinationLocation']),
      fareSnapshot: FareSnapshotModel.fromJson(json['fareSnapshot']),
      status: json['status']?.toString() ?? '',
      canSendStopAlert: json['canSendStopAlert'] as bool?,
      offboardingMethod: json['offboardingMethod']?.toString(),
      boardedAt: json['boardedAt']?.toString(),
      endedAt: json['endedAt']?.toString(),
      passengerDisplayName: json['passengerDisplayName']?.toString(),
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
