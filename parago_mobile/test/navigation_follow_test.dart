import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/core/utils/navigation_follow.dart';

void main() {
  test('free view persists through location updates until explicit recenter',
      () {
    final mode = NavigationFollow();
    final now = DateTime(2026, 9, 18);
    expect(mode.following, true);
    mode.freeView();
    final generation = mode.generation;
    for (var i = 0; i < 20; i++) {
      mode.updateHeading(
          target: 'jeep', sample: now, now: now, bearing: 90, speed: 5);
    }
    expect(mode.following, false);
    expect(mode.generation, generation);
    mode.recenter();
    expect(mode.following, true);
    expect(mode.generation, greaterThan(generation));
  });
  test(
      'heading crosses north by shortest angle and ignores stationary and stale samples',
      () {
    final mode = NavigationFollow();
    final now = DateTime(2026, 9, 18);
    mode.updateHeading(
        target: 'jeep', sample: now, now: now, bearing: 359, speed: 5);
    mode.updateHeading(
        target: 'jeep', sample: now, now: now, bearing: 1, speed: 5);
    expect(mode.heading, closeTo(359.5, 0.01));
    mode.updateHeading(
        target: 'jeep', sample: now, now: now, bearing: 180, speed: 0);
    expect(mode.heading, closeTo(359.5, 0.01));
    mode.updateHeading(
        target: 'jeep',
        sample: now.subtract(const Duration(minutes: 1)),
        now: now,
        bearing: 180,
        speed: 5);
    expect(mode.heading, closeTo(359.5, 0.01));
    mode.updateHeading(target: 'passenger', sample: now, now: now);
    expect(mode.heading, 0);
    expect(NavigationFollow.isFresh(null, now), false);
    expect(NavigationFollow.isFresh(now.add(const Duration(seconds: 1)), now),
        false);
    expect(
        NavigationFollow.isFresh(
            now.subtract(const Duration(seconds: 31)), now),
        false);
  });
}
