import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'adaptive_location_transmitter.dart';
import 'driver_service.dart';
import 'driver_position_source.dart';

class LocationTrackingService {
  LocationTrackingService(
    this._driverService, {
    this.onPosition,
    this.onError,
  }) {
    _transmitter = AdaptiveLocationTransmitter(
      sender: _driverService.updateLocation,
      onAccepted: (update, acknowledgement) {
        if (kDebugMode) {
          debugPrint(
            'Driver location accepted: stream=${update.streamId} '
            'sequence=${update.sequence} '
            'serverReceivedAt=${acknowledgement.serverReceivedAt.toIso8601String()}',
          );
        }
      },
      onFailed: (update, error) {
        if (kDebugMode) {
          debugPrint(
            'Driver location rejected/failed: stream=${update.streamId} '
            'sequence=${update.sequence} error=$error',
          );
        }
      },
    );
  }

  final DriverService _driverService;
  final ValueChanged<Position>? onPosition;
  final ValueChanged<Object>? onError;
  late final AdaptiveLocationTransmitter _transmitter;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _fallbackTimer;
  Position? _lastPosition;
  DateTime? _lastSampleAt;
  bool _isTracking = false;
  bool _fallbackRequestInFlight = false;

  static const Duration _fallbackInterval = Duration(seconds: 3);
  static const double _maxAcceptedAccuracyMeters = 20.0;

  bool get isTracking => _isTracking;
  int get updatesSent => _transmitter.updatesSent;
  int get updatesFailed => _transmitter.updatesFailed;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastUpdateSentAt => _transmitter.lastAttemptAt;

  Future<void> startTracking() async {
    if (_isTracking) {
      debugPrint('Location tracking already active');
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    _isTracking = true;
    _transmitter.start();
    debugPrint('Starting adaptive location tracking (1s sample, 2s/5s send)');

    _positionSubscription =
        driverPositionStream(_streamLocationSettings()).listen(
      _handlePositionUpdate,
      onError: (error) {
        debugPrint('Location stream error: $error');
        onError?.call(error);
      },
      cancelOnError: false,
    );

    _fallbackTimer = Timer.periodic(_fallbackInterval, (_) async {
      if (!_isTracking || _fallbackRequestInFlight) return;

      final now = DateTime.now();
      final lastSample = _lastSampleAt;

      if (lastSample == null ||
          now.difference(lastSample) >= _fallbackInterval) {
        _fallbackRequestInFlight = true;
        debugPrint('Fallback: forcing location update');
        try {
          final position =
              await driverCurrentPosition(_singleFixLocationSettings());
          await _handlePositionUpdate(position);
        } catch (error) {
          debugPrint('Fallback location update failed: $error');
          onError?.call(error);
        } finally {
          _fallbackRequestInFlight = false;
        }
      }
    });
  }

  Future<void> _handlePositionUpdate(Position position) async {
    if (!_isTracking) return;

    final previousSample = _lastPosition;
    _lastPosition = position;
    _lastSampleAt = DateTime.now();

    if (_looksLikeNoisyFix(position, previousSample)) {
      return;
    }

    onPosition?.call(position);

    final speed =
        position.speed.isFinite && position.speed >= 0 ? position.speed : null;
    final heading = position.heading.isFinite && position.heading >= 0
        ? position.heading % 360
        : 0.0;
    _transmitter.addSample(
      DriverLocationSample(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters:
            position.accuracy.isFinite ? position.accuracy.clamp(0, 500) : 500,
        speedMetersPerSecond: speed?.clamp(0, 100),
        headingDegrees: heading,
        capturedAt: position.timestamp,
      ),
    );
  }

  Future<void> sendLatestNow() => _transmitter.sendLatestNow();

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    debugPrint(
      'Stopping location tracking '
      '(sent: ${_transmitter.updatesSent}, '
      'failed: ${_transmitter.updatesFailed})',
    );

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _fallbackRequestInFlight = false;
    await _transmitter.stop();
    _isTracking = false;
  }

  void dispose() {
    _isTracking = false;
    _positionSubscription?.cancel();
    _fallbackTimer?.cancel();
    _fallbackRequestInFlight = false;
    _transmitter.dispose();
  }

  LocationSettings _streamLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'ParaGO driver tracking active',
            notificationText:
                'Sharing your live jeep location with passengers.',
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        );
    }
  }

  LocationSettings _singleFixLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 4),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          intervalDuration: const Duration(seconds: 1),
          timeLimit: const Duration(seconds: 4),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'ParaGO driver tracking active',
            notificationText:
                'Refreshing your live jeep location for passengers.',
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        );
    }
  }

  bool _looksLikeNoisyFix(Position position, Position? reference) {
    final accuracy = position.accuracy;
    if (reference == null ||
        !accuracy.isFinite ||
        accuracy <= _maxAcceptedAccuracyMeters) {
      return false;
    }

    final driftMeters = Geolocator.distanceBetween(
      reference.latitude,
      reference.longitude,
      position.latitude,
      position.longitude,
    );
    return driftMeters <= accuracy * 1.5;
  }
}
