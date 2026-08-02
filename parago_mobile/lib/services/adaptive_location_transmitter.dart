import 'dart:async';
import 'dart:math';

import '../models/operations/driver_location_update.dart';

typedef DriverLocationSender = Future<DriverLocationAcknowledgement> Function(
  DriverLocationUpdate update,
);
typedef DriverLocationAccepted = void Function(
  DriverLocationUpdate update,
  DriverLocationAcknowledgement acknowledgement,
);
typedef DriverLocationFailed = void Function(
  DriverLocationUpdate update,
  Object error,
);

class DriverLocationSample {
  const DriverLocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedMetersPerSecond,
    required this.headingDegrees,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double speedMetersPerSecond;
  final double headingDegrees;
  final DateTime capturedAt;
}

class AdaptiveLocationTransmitter {
  AdaptiveLocationTransmitter({
    required DriverLocationSender sender,
    DateTime Function()? now,
    String Function()? streamIdFactory,
    this.onAccepted,
    this.onFailed,
    this.movingInterval = const Duration(seconds: 2),
    this.stationaryInterval = const Duration(seconds: 5),
    this.stationarySpeedMetersPerSecond = 0.5,
    this.meaningfulMovementMeters = 15,
    this.meaningfulHeadingDegrees = 25,
  })  : _sender = sender,
        _now = now ?? DateTime.now,
        _streamIdFactory = streamIdFactory ?? _newUuidV4;

  final DriverLocationSender _sender;
  final DateTime Function() _now;
  final String Function() _streamIdFactory;
  final DriverLocationAccepted? onAccepted;
  final DriverLocationFailed? onFailed;
  final Duration movingInterval;
  final Duration stationaryInterval;
  final double stationarySpeedMetersPerSecond;
  final double meaningfulMovementMeters;
  final double meaningfulHeadingDegrees;

  Timer? _sendTimer;
  Future<void>? _inFlightFuture;
  DriverLocationSample? _latestSample;
  DriverLocationSample? _pendingSample;
  DriverLocationSample? _lastAttemptedSample;
  DateTime? _lastAttemptAt;
  String? _streamId;
  int _sequence = 0;
  bool _active = false;
  bool _forcePending = false;
  int _updatesSent = 0;
  int _updatesFailed = 0;

  bool get isActive => _active;
  bool get isSending => _inFlightFuture != null;
  String? get streamId => _streamId;
  int get sequence => _sequence;
  int get updatesSent => _updatesSent;
  int get updatesFailed => _updatesFailed;
  DateTime? get lastAttemptAt => _lastAttemptAt;

  void start() {
    _sendTimer?.cancel();
    _streamId = _streamIdFactory();
    _sequence = 0;
    _latestSample = null;
    _pendingSample = null;
    _lastAttemptedSample = null;
    _lastAttemptAt = null;
    _forcePending = false;
    _updatesSent = 0;
    _updatesFailed = 0;
    _active = true;
  }

  void addSample(DriverLocationSample sample) {
    if (!_active) return;
    _latestSample = sample;
    _pendingSample = sample;

    if (_lastAttemptAt == null ||
        _isMeaningfullyDifferent(sample, _lastAttemptedSample)) {
      _forcePending = true;
    }
    _schedulePending();
  }

  Future<void> sendLatestNow() async {
    if (!_active || _latestSample == null) return;
    _pendingSample = _latestSample;
    _forcePending = true;
    _schedulePending();
    await (_inFlightFuture ?? Future<void>.value());
  }

  Future<void> stop({bool sendFinal = true}) async {
    if (!_active) return;
    _sendTimer?.cancel();
    _sendTimer = null;
    if (sendFinal && _latestSample != null) {
      await sendLatestNow();
      while (_inFlightFuture != null) {
        await _inFlightFuture;
      }
    }
    _active = false;
    _pendingSample = null;
    _forcePending = false;
  }

  void dispose() {
    _active = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    _pendingSample = null;
    _forcePending = false;
  }

  void _schedulePending() {
    if (!_active || _pendingSample == null || _inFlightFuture != null) return;

    final now = _now();
    final interval = _intervalFor(_pendingSample!);
    final dueAt = _forcePending || _lastAttemptAt == null
        ? now
        : _lastAttemptAt!.add(interval);
    final delay = dueAt.difference(now);
    if (delay <= Duration.zero) {
      _dispatchPending();
      return;
    }

    _sendTimer?.cancel();
    _sendTimer = Timer(delay, _dispatchPending);
  }

  void _dispatchPending() {
    if (!_active || _pendingSample == null || _inFlightFuture != null) return;
    _sendTimer?.cancel();
    _sendTimer = null;

    final sample = _pendingSample!;
    _pendingSample = null;
    _forcePending = false;
    final streamId = _streamId!;
    final sequence = ++_sequence;
    _lastAttemptAt = _now();
    _lastAttemptedSample = sample;

    final update = DriverLocationUpdate(
      latitude: sample.latitude,
      longitude: sample.longitude,
      accuracyMeters: sample.accuracyMeters,
      speedMetersPerSecond: sample.speedMetersPerSecond,
      headingDegrees: sample.headingDegrees,
      streamId: streamId,
      sequence: sequence,
      capturedAt: sample.capturedAt,
    );

    late final Future<void> operation;
    operation = _sender(update).then((acknowledgement) {
      if (!acknowledgement.accepted ||
          acknowledgement.streamId != streamId ||
          acknowledgement.sequence != sequence) {
        throw StateError('Location acknowledgement did not match the request');
      }
      _updatesSent++;
      onAccepted?.call(update, acknowledgement);
    }).catchError((Object error) {
      _updatesFailed++;
      onFailed?.call(update, error);
    }).whenComplete(() {
      if (identical(_inFlightFuture, operation)) {
        _inFlightFuture = null;
      }
      if (_active && _pendingSample != null) {
        _schedulePending();
      }
    });
    _inFlightFuture = operation;
  }

  Duration _intervalFor(DriverLocationSample sample) {
    return sample.speedMetersPerSecond <= stationarySpeedMetersPerSecond
        ? stationaryInterval
        : movingInterval;
  }

  bool _isMeaningfullyDifferent(
    DriverLocationSample sample,
    DriverLocationSample? previous,
  ) {
    if (previous == null) return true;
    final distance = _distanceMeters(
      previous.latitude,
      previous.longitude,
      sample.latitude,
      sample.longitude,
    );
    if (distance >= meaningfulMovementMeters) return true;

    final headingDifference =
        (sample.headingDegrees - previous.headingDegrees).abs() % 360;
    final shortestHeadingDifference =
        min(headingDifference, 360 - headingDifference);
    return sample.speedMetersPerSecond > stationarySpeedMetersPerSecond &&
        shortestHeadingDifference >= meaningfulHeadingDegrees;
  }

  static double _distanceMeters(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = (latitude2 - latitude1) * pi / 180;
    final longitudeDelta = (longitude2 - longitude1) * pi / 180;
    final firstLatitudeRadians = latitude1 * pi / 180;
    final secondLatitudeRadians = latitude2 * pi / 180;
    final a = pow(sin(latitudeDelta / 2), 2) +
        cos(firstLatitudeRadians) *
            cos(secondLatitudeRadians) *
            pow(sin(longitudeDelta / 2), 2);
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
