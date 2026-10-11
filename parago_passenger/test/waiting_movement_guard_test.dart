import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:parago_passenger/services/waiting_movement_guard.dart';

void main() {
  final start = DateTime.utc(2026, 10, 11);
  const home = LatLng(14.898, 121.05);
  const far = LatLng(14.895, 121.05);
  void sample(WaitingMovementGuard guard, int second,
          {LatLng point = home,
          double accuracy = 5,
          double? speed = 0,
          bool near = false,
          String id = 'one',
          int? nowSecond}) =>
      guard.update(
          id: id,
          point: point,
          capturedAt: start.add(Duration(seconds: second)),
          now: start.add(Duration(seconds: nowSecond ?? second)),
          accuracyMetres: accuracy,
          speed: speed,
          nearAssignedJeep: near);

  test('walking near the waiting spot and one distant GPS jump do not prompt',
      () {
    final g = WaitingMovementGuard();
    sample(g, 0);
    sample(g, 5, point: far);
    sample(g, 10);
    sample(g, 15, point: const LatLng(14.8981, 121.05));
    expect(g.reason, isNull);
  });
  test('sustained movement away prompts, Waiting retains booking and snoozes',
      () {
    final g = WaitingMovementGuard();
    sample(g, 0);
    for (final s in [5, 10, 15]) {
      sample(g, s, point: far);
    }
    expect(g.reason, WaitingMovementReason.distance);
    g.confirmWaiting(point: far, now: start.add(const Duration(seconds: 15)));
    expect(g.bookingId, 'one');
    expect(g.reason, isNull);
    for (final s in [20, 25, 30]) {
      sample(g, s, point: home);
    }
    expect(g.reason, isNull);
    for (final s in [75, 80, 85]) {
      sample(g, s, point: home);
    }
    expect(g.reason, WaitingMovementReason.distance);
  });
  test('sustained fast movement prompts even within the distance limit', () {
    final g = WaitingMovementGuard();
    for (final s in [0, 5, 10]) {
      sample(g, s, speed: 6);
    }
    expect(g.reason, WaitingMovementReason.speed);
  });
  test('stale, inaccurate, duplicate readings and a long gap cannot accumulate',
      () {
    final g = WaitingMovementGuard();
    sample(g, 0);
    sample(g, 5, point: far);
    sample(g, 5, point: far);
    sample(g, 5, point: far);
    expect(g.reason, isNull);
    sample(g, 10, point: far, accuracy: 100);
    sample(g, 15, point: far, nowSecond: 40);
    sample(g, 40, point: far);
    sample(g, 65, point: far);
    sample(g, 70, point: far);
    expect(g.reason, isNull);
    sample(g, 75, point: far);
    expect(g.reason, WaitingMovementReason.distance);
  });
  test('travelling with the assigned jeep suppresses the reminder', () {
    final g = WaitingMovementGuard();
    for (final s in [0, 5, 10]) {
      sample(g, s, speed: 10, near: true);
    }
    expect(g.reason, isNull);
    for (final s in [15, 20, 25]) {
      sample(g, s, speed: 10);
    }
    expect(g.reason, WaitingMovementReason.speed);
    sample(g, 30, speed: 10, near: true);
    expect(g.reason, isNull);
  });
  test('movement detects fast travel when the browser supplies zero speed', () {
    final g = WaitingMovementGuard();
    sample(g, 0);
    for (final s in [5, 10, 15]) {
      sample(g, s, point: LatLng(14.898 - s * .00006, 121.05));
    }
    expect(g.reason, WaitingMovementReason.speed);
  });
  test('new bookings and ending a waiting state discard the old prompt', () {
    final g = WaitingMovementGuard();
    for (final s in [0, 5, 10]) {
      sample(g, s, speed: 10);
    }
    sample(g, 15, point: far, id: 'two');
    expect(g.reason, isNull);
    expect(g.bookingId, 'two');
    g.reset();
    expect(g.bookingId, isNull);
  });
}
