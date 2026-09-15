import 'dart:math';

/// Serializes taps. A failed adjustment stops the batch; later taps must not
/// silently execute after a failed earlier operation.
class OccupancyAdjustmentQueue {
  Future<void> _tail = Future.value();
  int _generation = 0;
  int pending = 0;
  final _random = Random.secure();

  Future<void> add(Future<void> Function(String operationId) apply) {
    final generation = _generation;
    final id = List.generate(
            24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    pending++;
    final result = _tail.then((_) async {
      if (generation != _generation) {
        throw StateError(
            'Pending count changes cancelled; check the count before retrying.');
      }
      try {
        await apply(id);
      } catch (_) {
        _generation++;
        rethrow;
      }
    }).whenComplete(() => pending--);
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
