class PickupRequestModel {
  const PickupRequestModel({
    required this.id,
    required this.passengerId,
    required this.tripSessionId,
    required this.routeId,
    required this.status,
    required this.pickupType,
    this.flowVersion = 1,
    this.members = const [],
    this.partySize = 1,
    this.groupReadyAt,
    this.stopRef,
    this.terminalStopRef,
    this.sourceNote,
    this.pickupLatitude,
    this.pickupLongitude,
    this.terminalLatitude,
    this.terminalLongitude,
    this.destinationStopRef,
    this.destinationLatitude,
    this.destinationLongitude,
    this.fareSnapshot,
    this.expiresAt,
    this.createdAt,
    this.acknowledgedAt,
    this.transferOfferId,
  });

  final int flowVersion;
  final List<JourneyMemberModel> members;
  String get destinationsLabel => members.isEmpty
      ? (destinationStopRef ?? "Saved destination")
      : JourneyMemberModel.destinationSummary(members);
  final int partySize;
  final String? groupReadyAt;

  final String id;
  final String passengerId;
  final String tripSessionId;
  final String routeId;
  final String status;
  final String pickupType;
  final String? stopRef;
  final String? terminalStopRef;
  final String? sourceNote;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? terminalLatitude;
  final double? terminalLongitude;
  final String? destinationStopRef;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final FareSnapshotModel? fareSnapshot;
  final String? expiresAt;
  final String? createdAt;
  final String? acknowledgedAt;
  final String? transferOfferId;

  double? get estimatedFare => fareSnapshot?.amount;
  String? get fareBoardingStopRef => fareSnapshot?.boardingStopRef;
  String? get fareDestinationStopRef => fareSnapshot?.destinationStopRef;

  factory PickupRequestModel.fromJson(Map<String, dynamic> json) {
    return PickupRequestModel(
      flowVersion: (json['flowVersion'] as num?)?.toInt() ?? 1,
      members: (json['members'] as List? ?? [])
          .map((m) =>
              JourneyMemberModel.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      partySize: (json['partySize'] as num?)?.toInt() ?? 1,
      groupReadyAt: json['groupReadyAt']?.toString(),
      id: json['_id'].toString(),
      passengerId: json['passengerId']?.toString() ?? '',
      tripSessionId: json['tripSessionId']?.toString() ?? '',
      routeId: json['routeId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      pickupType: json['pickupType']?.toString() ?? 'roadside',
      stopRef: json['stopRef']?.toString(),
      terminalStopRef: json['terminalStopRef']?.toString(),
      sourceNote: json['sourceNote']?.toString(),
      pickupLatitude: _readLatitude(json['pickupLocation']),
      pickupLongitude: _readLongitude(json['pickupLocation']),
      terminalLatitude: _readLatitude(json['terminalLocation']),
      terminalLongitude: _readLongitude(json['terminalLocation']),
      destinationStopRef: json['destinationStopRef']?.toString(),
      destinationLatitude: _readLatitude(json['destinationLocation']),
      destinationLongitude: _readLongitude(json['destinationLocation']),
      fareSnapshot: FareSnapshotModel.fromJson(json['fareSnapshot']),
      expiresAt: json['expiresAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
      acknowledgedAt: json['acknowledgedAt']?.toString(),
      transferOfferId: json['transferOfferId']?.toString(),
    );
  }
}

class FareSnapshotModel {
  const FareSnapshotModel({
    required this.boardingStopRef,
    required this.boardingStopOrder,
    required this.boardingFare,
    required this.destinationStopRef,
    required this.destinationStopOrder,
    required this.destinationFare,
    required this.amount,
  });

  final String? boardingStopRef;
  final int? boardingStopOrder;
  final double boardingFare;
  final String? destinationStopRef;
  final int? destinationStopOrder;
  final double destinationFare;
  final double amount;

  static FareSnapshotModel? fromJson(dynamic value) {
    if (value is! Map && value is! Map<String, dynamic>) {
      return null;
    }
    final map = value is Map<String, dynamic>
        ? value
        : (value as Map).map((key, item) => MapEntry(key.toString(), item));
    return FareSnapshotModel(
      boardingStopRef: map['boardingStopRef']?.toString(),
      boardingStopOrder:
          int.tryParse(map['boardingStopOrder']?.toString() ?? ''),
      boardingFare: _readNumber(map['boardingFare']) ?? 0,
      destinationStopRef: map['destinationStopRef']?.toString(),
      destinationStopOrder:
          int.tryParse(map['destinationStopOrder']?.toString() ?? ''),
      destinationFare: _readNumber(map['destinationFare']) ?? 0,
      amount: _readNumber(map['amount']) ?? 0,
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

double? _readNumber(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

class JourneyMemberModel {
  const JourneyMemberModel(
      {required this.memberId,
      required this.organizer,
      required this.label,
      required this.destinationStopRef,
      required this.latitude,
      required this.longitude,
      required this.fare,
      required this.status,
      this.destinationStopOrder});
  final String memberId, label, destinationStopRef, status;
  final bool organizer;
  final double latitude, longitude, fare;
  final double? destinationStopOrder;
  factory JourneyMemberModel.fromJson(Map<String, dynamic> json) =>
      JourneyMemberModel(
          memberId: json['memberId'].toString(),
          organizer: json['organizer'] == true,
          label: json['label'].toString(),
          destinationStopRef: json['destinationStopRef'].toString(),
          latitude: _readLatitude(json['destinationLocation'])!,
          longitude: _readLongitude(json['destinationLocation'])!,
          fare: (json['fareSnapshot']['amount'] as num).toDouble(),
          status: json['status'].toString(),
          destinationStopOrder:
              (json['fareSnapshot']?['destinationStopOrder'] as num?)
                  ?.toDouble());
  static String destinationSummary(List<JourneyMemberModel> members) {
    final names = members.map((m) => m.destinationStopRef).toSet().toList();
    return '${names.take(2).join("\n")}${names.length > 2 ? "\n+${names.length - 2} more" : ""}';
  }
}
