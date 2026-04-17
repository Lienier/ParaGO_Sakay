import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_service.dart';

class LocationTrackingService {
  LocationTrackingService(
    this._driverService, {
    this.onPosition,
    this.onError,
  });

  final DriverService _driverService;
  final ValueChanged<Position>? onPosition;
  final ValueChanged<Object>? onError;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _fallbackTimer;
  Position? _lastPosition;
  Position? _lastSentPosition;
  DateTime? _lastUpdateSentAt;
  bool _isTracking = false;
  int _updatesSent = 0;
  int _updatesFailed = 0;

  static const Duration _updateInterval = Duration(seconds: 5);
  static const Duration _fallbackInterval = Duration(seconds: 10);
  static const double _minimumDistanceMeters = 8.0;
  static const double _maxAcceptedAccuracyMeters = 35.0;

  bool get isTracking => _isTracking;
  int get updatesSent => _updatesSent;
  int get updatesFailed => _updatesFailed;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastUpdateSentAt => _lastUpdateSentAt;

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
    _updatesSent = 0;
    _updatesFailed = 0;
    debugPrint('Starting real-time location tracking (5s interval)');

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _streamLocationSettings(),
    ).listen(
      _handlePositionUpdate,
      onError: (error) {
        debugPrint('Location stream error: $error');
        _updatesFailed++;
        onError?.call(error);
      },
      cancelOnError: false,
    );

    _fallbackTimer = Timer.periodic(_fallbackInterval, (_) async {
      if (!_isTracking) return;

      final now = DateTime.now();
      final lastUpdate = _lastUpdateSentAt;

      if (lastUpdate == null ||
          now.difference(lastUpdate) >= _fallbackInterval) {
        debugPrint('Fallback: forcing location update');
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: _singleFixLocationSettings(),
          );
          await _handlePositionUpdate(position);
        } catch (error) {
          debugPrint('Fallback location update failed: $error');
          _updatesFailed++;
          onError?.call(error);
        }
      }
    });
  }

  Future<void> _handlePositionUpdate(Position position) async {
    if (!_isTracking) return;

    final previousSample = _lastPosition;
    _lastPosition = position;

    if (_looksLikeNoisyFix(position, previousSample ?? _lastSentPosition)) {
      return;
    }

    onPosition?.call(position);

    final now = DateTime.now();
    final lastSent = _lastUpdateSentAt;

    if (lastSent != null && now.difference(lastSent) < _updateInterval) {
      return;
    }

    final lastPos = _lastSentPosition;
    if (lastPos != null && lastSent != null) {
      final distance = Geolocator.distanceBetween(
        lastPos.latitude,
        lastPos.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance < _minimumDistanceMeters &&
          now.difference(lastSent) < _fallbackInterval) {
        return;
      }
    }

    try {
      await _driverService.updateLocation(
        lat: position.latitude,
        lng: position.longitude,
      );

      _lastSentPosition = position;
      _lastUpdateSentAt = now;
      _updatesSent++;

      debugPrint(
        'Location sent: ${position.latitude.toStringAsFixed(6)}, '
        '${position.longitude.toStringAsFixed(6)} '
        '(accuracy: ${position.accuracy.toStringAsFixed(1)}m, '
        'total: $_updatesSent)',
      );
    } catch (error) {
      _updatesFailed++;
      debugPrint('Failed to send location update: $error');
    }
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    debugPrint(
        'Stopping location tracking (sent: $_updatesSent, failed: $_updatesFailed)');

    _isTracking = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  void dispose() {
    stopTracking();
  }

  LocationSettings _streamLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 4,
          intervalDuration: const Duration(seconds: 3),
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
          distanceFilter: 4,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: false,
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 4,
        );
    }
  }

  LocationSettings _singleFixLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 8),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          intervalDuration: const Duration(seconds: 3),
          timeLimit: const Duration(seconds: 8),
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
          timeLimit: Duration(seconds: 8),
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
