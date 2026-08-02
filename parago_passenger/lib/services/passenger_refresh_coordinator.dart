import 'dart:async';

enum PassengerRefreshDomain {
  trips,
  bookings,
  notifications,
  routes,
}

class PassengerRefreshResult<T> {
  const PassengerRefreshResult({
    required this.value,
    required this.isCurrent,
    required this.generation,
  });

  final T value;
  final bool isCurrent;
  final int generation;
}

class PassengerRefreshCoordinator {
  final Map<PassengerRefreshDomain, int> _generations = {};
  final Map<PassengerRefreshDomain, Future<Object?>> _pending = {};

  int generationOf(PassengerRefreshDomain domain) => _generations[domain] ?? 0;

  bool isPending(PassengerRefreshDomain domain) => _pending[domain] != null;

  void invalidate(PassengerRefreshDomain domain) {
    _generations[domain] = generationOf(domain) + 1;
    _pending.remove(domain);
  }

  void invalidateAll() {
    for (final domain in PassengerRefreshDomain.values) {
      invalidate(domain);
    }
  }

  Future<PassengerRefreshResult<T>> run<T>(
    PassengerRefreshDomain domain,
    Future<T> Function() loader, {
    bool replacePending = false,
  }) {
    final existing = _pending[domain];
    if (!replacePending && existing != null) {
      return existing.then((value) => value as PassengerRefreshResult<T>);
    }

    final generation = generationOf(domain) + 1;
    _generations[domain] = generation;
    late final Future<PassengerRefreshResult<T>> operation;
    operation = loader().then(
      (value) => PassengerRefreshResult<T>(
        value: value,
        isCurrent: generationOf(domain) == generation,
        generation: generation,
      ),
    );
    _pending[domain] = operation;
    void clearPending() {
      if (identical(_pending[domain], operation)) {
        _pending.remove(domain);
      }
    }

    unawaited(
      operation.then<void>(
        (_) => clearPending(),
        onError: (Object _, StackTrace __) => clearPending(),
      ),
    );
    return operation;
  }

  void dispose() {
    invalidateAll();
    _pending.clear();
  }
}

class PassengerRealtimeReconciliationGate {
  bool _awaitingSnapshot = true;
  Map<String, dynamic>? _latestBatch;
  final Map<String, Map<String, dynamic>> _latestLegacyByVehicle = {};

  bool get awaitingSnapshot => _awaitingSnapshot;

  void disconnected() {
    _awaitingSnapshot = true;
    clearBufferedEvents();
  }

  void socketReady() {
    _awaitingSnapshot = true;
  }

  void bufferBatch(Map<String, dynamic> payload) {
    if (!_awaitingSnapshot) return;
    _latestBatch = Map<String, dynamic>.from(payload);
  }

  void bufferLegacy(Map<String, dynamic> payload) {
    if (!_awaitingSnapshot) return;
    final key = (payload['tripId'] ?? payload['jeepneyId'] ?? '').toString();
    if (key.isEmpty) return;
    if (_latestLegacyByVehicle.length >= 100 &&
        !_latestLegacyByVehicle.containsKey(key)) {
      _latestLegacyByVehicle.remove(_latestLegacyByVehicle.keys.first);
    }
    _latestLegacyByVehicle[key] = Map<String, dynamic>.from(payload);
  }

  PassengerBufferedRealtimeEvents completeSnapshot() {
    _awaitingSnapshot = false;
    final buffered = PassengerBufferedRealtimeEvents(
      latestBatch: _latestBatch,
      legacyLocations: List<Map<String, dynamic>>.unmodifiable(
        _latestLegacyByVehicle.values,
      ),
    );
    clearBufferedEvents();
    return buffered;
  }

  void routeChanged() {
    clearBufferedEvents();
  }

  void clearBufferedEvents() {
    _latestBatch = null;
    _latestLegacyByVehicle.clear();
  }
}

class PassengerBufferedRealtimeEvents {
  const PassengerBufferedRealtimeEvents({
    required this.latestBatch,
    required this.legacyLocations,
  });

  final Map<String, dynamic>? latestBatch;
  final List<Map<String, dynamic>> legacyLocations;
}
