class DriverLocationUpdate {
  const DriverLocationUpdate({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
    required this.headingDegrees,
    required this.streamId,
    required this.sequence,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? speedMetersPerSecond;
  final double headingDegrees;
  final String streamId;
  final int sequence;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'speedMetersPerSecond': speedMetersPerSecond,
        'headingDegrees': headingDegrees,
        'streamId': streamId,
        'sequence': sequence,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      };
}

class DriverLocationAcknowledgement {
  const DriverLocationAcknowledgement({
    required this.accepted,
    required this.streamId,
    required this.sequence,
    required this.serverReceivedAt,
  });

  final bool accepted;
  final String streamId;
  final int sequence;
  final DateTime serverReceivedAt;

  factory DriverLocationAcknowledgement.fromJson(Map<String, dynamic> json) {
    return DriverLocationAcknowledgement(
      accepted: json['accepted'] == true,
      streamId: json['streamId']?.toString() ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      serverReceivedAt:
          DateTime.tryParse(json['serverReceivedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
