class PassengerJeepEta {
  const PassengerJeepEta({
    required this.tripId,
    required this.jeepneyId,
    required this.plateNumber,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.rawDurationSeconds,
    required this.trafficDelayInSeconds,
    required this.source,
    required this.vehicleLocationLastSeenAt,
    required this.calculatedAt,
    required this.expiresAt,
  });

  final String tripId;
  final String jeepneyId;
  final String plateNumber;
  final double distanceMeters;
  final double durationSeconds;
  final double rawDurationSeconds;
  final double trafficDelayInSeconds;
  final String source;
  final DateTime? vehicleLocationLastSeenAt;
  final DateTime? calculatedAt;
  final DateTime? expiresAt;

  factory PassengerJeepEta.fromJson(Map<String, dynamic> json) {
    return PassengerJeepEta(
      tripId: json['tripId']?.toString() ?? '',
      jeepneyId: json['jeepneyId']?.toString() ?? '',
      plateNumber: json['plateNumber']?.toString() ?? '',
      distanceMeters: _toDouble(json['distanceMeters']) ?? 0,
      durationSeconds: _toDouble(json['durationSeconds']) ?? 0,
      rawDurationSeconds: _toDouble(json['rawDurationSeconds']) ?? 0,
      trafficDelayInSeconds: _toDouble(json['trafficDelayInSeconds']) ?? 0,
      source: json['source']?.toString() ?? '',
      vehicleLocationLastSeenAt: DateTime.tryParse(
          json['vehicleLocationLastSeenAt']?.toString() ?? ''),
      calculatedAt: DateTime.tryParse(json['calculatedAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
