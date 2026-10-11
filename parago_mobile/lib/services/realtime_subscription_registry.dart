class RealtimeSubscription {
  const RealtimeSubscription(this.eventName, this.identifier);

  final String eventName;
  final String identifier;
}

class RealtimeSubscriptionRegistry {
  final Set<String> _routeIds = <String>{};
  final Set<String> _authorizedRouteIds = <String>{};

  bool addRoute(String id) => id.trim().isNotEmpty && _routeIds.add(id.trim());
  bool removeRoute(String id) {
    _authorizedRouteIds.remove(id.trim());
    return _routeIds.remove(id.trim());
  }

  final Set<String> _tripIds = <String>{};
  final Set<String> _authorizedTripIds = <String>{};

  bool addTrip(String tripId) {
    final normalized = tripId.trim();
    return normalized.isNotEmpty && _tripIds.add(normalized);
  }

  bool removeTrip(String tripId) {
    final normalized = tripId.trim();
    if (normalized.isEmpty) return false;
    _authorizedTripIds.remove(normalized);
    return _tripIds.remove(normalized);
  }

  Iterable<RealtimeSubscription> get restorationEvents sync* {
    for (final id in _routeIds.where(_authorizedRouteIds.contains)) {
      yield RealtimeSubscription('subscribe.route', id);
    }
    for (final tripId in _tripIds.where(_authorizedTripIds.contains)) {
      yield RealtimeSubscription('subscribe.trip', tripId);
    }
  }

  Iterable<RealtimeSubscription> get pendingAuthorizationEvents sync* {
    for (final id
        in _routeIds.where((id) => !_authorizedRouteIds.contains(id))) {
      yield RealtimeSubscription('subscribe.route', id);
    }
    for (final tripId in _tripIds.where(
      (value) => !_authorizedTripIds.contains(value),
    )) {
      yield RealtimeSubscription('subscribe.trip', tripId);
    }
  }

  void markAuthorized(String eventName, String identifier) {
    final normalized = identifier.trim();
    if (eventName == 'subscribe.route' && _routeIds.contains(normalized)) {
      _authorizedRouteIds.add(normalized);
    }
    if (eventName == 'subscribe.trip' && _tripIds.contains(normalized)) {
      _authorizedTripIds.add(normalized);
    }
  }

  void reject(String eventName, String identifier) {
    if (eventName == 'subscribe.route') {
      removeRoute(identifier);
      return;
    }
    if (eventName != 'subscribe.trip') return;
    final normalized = identifier.trim();
    _tripIds.remove(normalized);
    _authorizedTripIds.remove(normalized);
  }

  void clear() {
    _routeIds.clear();
    _authorizedRouteIds.clear();
    _tripIds.clear();
    _authorizedTripIds.clear();
  }
}

Map<String, dynamic> normalizeRealtimePayload(dynamic payload) {
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map) {
    return payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}
