import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/services/occupancy_adjustment_queue.dart';
import 'package:parago_mobile/models/trip/trip_session.dart';

void main() {
  test('newer occupancy snapshot survives delayed reads and local copies', () {
    TripSession snapshot(String time, int count) => TripSession.fromJson({
          '_id': 'trip',
          'updatedAt': time,
          'manualOccupancyCount': count,
        });
    final old = snapshot('2026-09-15T10:00:00.000Z', 1);
    final current = snapshot('2026-09-15T10:00:01.000Z', 2);
    expect(current.isNewerThan(old), isTrue);
    expect(old.isNewerThan(current), isFalse);
    expect(
        current.copyWith(notes: 'location refresh').isNewerThan(old), isTrue);
  });
  test('rapid mixed taps run in order with distinct operation IDs', () async {
    final queue = OccupancyAdjustmentQueue();
    final gate = Completer<void>();
    final ids = <String>{};
    final applied = <int>[];
    final futures = [1, 1, -1, 1, -1]
        .map((delta) => queue.add((id) async {
              await gate.future;
              expect(ids.add(id), isTrue);
              applied.add(delta);
            }))
        .toList();
    expect(queue.pending, 5);
    gate.complete();
    await Future.wait(futures);
    expect(applied, [1, 1, -1, 1, -1]);
    expect(queue.pending, 0);
  });

  test('failure cancels later queued taps; subsequent batch can proceed',
      () async {
    final queue = OccupancyAdjustmentQueue();
    final first = queue.add((_) async => throw StateError('offline'));
    var applied = false;
    final next = queue.add((_) async {
      applied = true;
    });
    await Future.wait([
      expectLater(first, throwsStateError),
      expectLater(next, throwsStateError),
    ]);
    expect(applied, isFalse);
    expect(queue.pending, 0);
    await queue.add((_) async {
      applied = true;
    });
    expect(applied, isTrue);
  });
}
