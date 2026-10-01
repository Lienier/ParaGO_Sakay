import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/services/occupancy_adjustment_queue.dart';
import 'package:parago_mobile/models/trip/trip_session.dart';

void main() {
  testWidgets('rapid taps display immediately and debounce ordered persistence',
      (tester) async {
    final queue =
        OccupancyAdjustmentQueue(debounce: const Duration(milliseconds: 300));
    final sent = <String>[];
    final gate = Completer<void>();
    Future<void> send(String id) async {
      sent.add(id);
      await gate.future;
    }

    final first = queue.add(send, delta: 1, manualCount: 2);
    expect(queue.projectedManualCount, 3);
    await tester.pump(const Duration(milliseconds: 200));
    final second = queue.add(send, delta: 1, manualCount: 2);
    expect(queue.projectedManualCount, 4);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent.length, 1);
    // A server echo must not be added again to the optimistic total.
    final third = queue.add(send, delta: -1, manualCount: 3);
    expect(queue.projectedManualCount, 3);
    gate.complete();
    await tester.pump(const Duration(milliseconds: 300));
    await Future.wait([first, second, third]);
    expect(sent.toSet().length, 3);
    expect(queue.pending, 0);
    expect(queue.projectedManualCount, isNull);
  });

  testWidgets('continuous tapping flushes within one second', (tester) async {
    final queue =
        OccupancyAdjustmentQueue(debounce: const Duration(milliseconds: 300));
    var sent = 0;
    final futures = <Future<void>>[];
    for (var i = 0; i < 5; i++) {
      futures.add(queue.add((_) async {
        sent++;
      }, delta: 1, manualCount: 0));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await Future.wait(futures);
    expect(sent, 5);
    expect(queue.projectedManualCount, isNull);
  });

  testWidgets('failed save clears optimistic count and cancels pending taps',
      (tester) async {
    final queue =
        OccupancyAdjustmentQueue(debounce: const Duration(milliseconds: 300));
    final first = queue.add((_) async => throw StateError('offline'),
        delta: 1, manualCount: 2);
    var sent = false;
    final second = queue.add((_) async {
      sent = true;
    }, delta: 1, manualCount: 2);
    final checks = Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError)
    ]);
    expect(queue.projectedManualCount, 4);
    await tester.pump(const Duration(milliseconds: 300));
    await checks;
    expect(sent, false);
    expect(queue.projectedManualCount, isNull);
  });

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

  test('group adjustments keep projected count and operation order', () async {
    final queue = OccupancyAdjustmentQueue();
    final applied = <int>[];
    await queue.add((_) async => applied.add(5), delta: 5, manualCount: 0);
    expect(queue.projectedManualCount, isNull);
    await queue.add((_) async => applied.add(-3), delta: -3, manualCount: 5);
    expect(applied, [5, -3]);
    expect(queue.projectedManualCount, isNull);
  });
}
