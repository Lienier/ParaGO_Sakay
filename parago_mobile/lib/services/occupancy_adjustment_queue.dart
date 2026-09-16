import 'dart:math';
import 'dart:async';

/// Serializes taps. A failed adjustment stops the batch; later taps must not
/// silently execute after a failed earlier operation.
class OccupancyAdjustmentQueue {
  OccupancyAdjustmentQueue({this.debounce = Duration.zero});
  final Duration debounce;
  Timer? _timer;
  Timer? _maxTimer;
  Completer<void>? _ready;
  int? projectedManualCount;

  void _release() {
    _timer?.cancel();
    _maxTimer?.cancel();
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  Future<void> _waitForTaps() {
    if (debounce == Duration.zero) return Future.value();
    if (_ready == null) {
      _ready = Completer<void>();
      // Continuous tapping must not postpone persistence indefinitely.
      _maxTimer = Timer(const Duration(seconds: 1), _release);
    }
    _timer?.cancel();
    _timer = Timer(debounce, _release);
    return _ready!.future;
  }

  Future<void> _tail = Future.value();
  int _generation = 0;
  int pending = 0;
  final _random = Random.secure();

  Future<void> add(Future<void> Function(String operationId) apply,
      {int? delta, int? manualCount}) {
    if (delta != null && manualCount != null) {
      projectedManualCount = (projectedManualCount ?? manualCount) + delta;
    }
    final ready = _waitForTaps();
    final generation = _generation;
    final id = List.generate(
            24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    pending++;
    final result = _tail.then((_) async {
      await ready;
      if (generation != _generation) {
        throw StateError(
            'Pending count changes cancelled; check the count before retrying.');
      }
      try {
        await apply(id);
      } catch (_) {
        _generation++;
        projectedManualCount = null;
        rethrow;
      }
    }).whenComplete(() {
      pending--;
      if (pending == 0) projectedManualCount = null;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
