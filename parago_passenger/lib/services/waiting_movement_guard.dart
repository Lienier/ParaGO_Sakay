import 'package:latlong2/latlong.dart';

enum WaitingMovementReason { distance, speed }

/// A foreground reminder, never a boarding decision or automatic cancellation.
class WaitingMovementGuard {
  static const distanceMetres = 100.0;
  static const speedMetresPerSecond = 15 / 3.6;
  static const _distance = Distance();
  String? bookingId;
  LatLng? _anchor, _previous;
  DateTime? _previousAt, _outsideSince, _snoozedUntil;
  double _previousAccuracy = 0;
  int _observations = 0;
  WaitingMovementReason? reason;

  void rejectSample() {
    _outsideSince = null;
    _observations = 0;
  }

  void reset() {
    bookingId = null;
    _anchor = null;
    _previous = null;
    _previousAt = null;
    _outsideSince = null;
    _snoozedUntil = null;
    _observations = 0;
    reason = null;
  }

  void confirmWaiting({required LatLng point, required DateTime now}) {
    _anchor = point;
    reason = null;
    _outsideSince = null;
    _observations = 0;
    _snoozedUntil = now.add(const Duration(seconds: 60));
  }

  void update(
      {required String id,
      required LatLng point,
      required DateTime capturedAt,
      required DateTime now,
      required double accuracyMetres,
      double? speed,
      required bool nearAssignedJeep}) {
    if (id != bookingId) {
      reset();
      bookingId = id;
    }
    final age = now.difference(capturedAt);
    if (age.isNegative ||
        age > const Duration(seconds: 15) ||
        !accuracyMetres.isFinite ||
        accuracyMetres < 0 ||
        accuracyMetres > 30 ||
        !point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      rejectSample();
      return;
    }
    if (_previousAt != null && !capturedAt.isAfter(_previousAt!)) return;
    final gap =
        _previousAt == null ? null : capturedAt.difference(_previousAt!);
    if (gap != null && gap > const Duration(seconds: 15)) {
      _outsideSince = null;
      _observations = 0;
    }
    _anchor ??= point;
    // Subtract both accuracy radii from movement inferred between samples.
    final inferredSpeed = _previous == null ||
            gap == null ||
            gap.inMilliseconds <= 0 ||
            gap > const Duration(seconds: 15)
        ? 0.0
        : ((_distance.as(LengthUnit.Meter, _previous!, point) -
                    accuracyMetres -
                    _previousAccuracy)
                .clamp(0.0, double.infinity)) /
            (gap.inMilliseconds / 1000);
    // Web GPS reports zero for missing speed. Reliable displacement can still
    // establish a conservative lower bound without treating jitter as travel.
    final measuredSpeed =
        speed != null && speed.isFinite && speed >= inferredSpeed
            ? speed
            : inferredSpeed;
    _previous = point;
    _previousAt = capturedAt;
    _previousAccuracy = accuracyMetres;
    if (nearAssignedJeep) {
      _outsideSince = null;
      _observations = 0;
      reason = null;
      return;
    }
    if (_snoozedUntil != null && now.isBefore(_snoozedUntil!)) return;
    final far =
        _distance.as(LengthUnit.Meter, _anchor!, point) - accuracyMetres >
            distanceMetres;
    final fast = measuredSpeed > speedMetresPerSecond;
    if (!far && !fast) {
      _outsideSince = null;
      _observations = 0;
      return;
    }
    _outsideSince ??= capturedAt;
    _observations++;
    if (_observations >= 3 &&
        capturedAt.difference(_outsideSince!) >= const Duration(seconds: 10)) {
      reason ??=
          far ? WaitingMovementReason.distance : WaitingMovementReason.speed;
    }
  }
}
