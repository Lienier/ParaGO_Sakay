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
    this.latitude,
    this.longitude,
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
  final double? latitude;
  final double? longitude;
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
      latitude: _readLatitude(json['location']),
      longitude: _readLongitude(json['location']),
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
