class RealtimeSubscription {
  const RealtimeSubscription(this.eventName, this.identifier);

  final String eventName;
  final String identifier;
}

class RealtimeSubscriptionRegistry {
  final Set<String> _routeIds = <String>{};
  final Set<String> _tripIds = <String>{};
  final Set<String> _authorizedRouteIds = <String>{};
  final Set<String> _authorizedTripIds = <String>{};

  bool addRoute(String routeId) {
    final normalized = routeId.trim();
    if (normalized.isEmpty) return false;
    if (_routeIds.length == 1 && _routeIds.contains(normalized)) {
      return false;
    }
    _routeIds
      ..clear()
      ..add(normalized);
    _authorizedRouteIds.removeWhere((value) => value != normalized);
    return true;
  }

  bool addTrip(String tripId) => _add(_tripIds, tripId);
  bool removeRoute(String routeId) =>
      _remove(_routeIds, _authorizedRouteIds, routeId);
  bool removeTrip(String tripId) =>
      _remove(_tripIds, _authorizedTripIds, tripId);

  Iterable<RealtimeSubscription> get restorationEvents sync* {
    for (final routeId in _routeIds.where(_authorizedRouteIds.contains)) {
      yield RealtimeSubscription('subscribe.route', routeId);
    }
    for (final tripId in _tripIds.where(_authorizedTripIds.contains)) {
      yield RealtimeSubscription('subscribe.trip', tripId);
    }
  }

  Iterable<RealtimeSubscription> get pendingAuthorizationEvents sync* {
    for (final routeId in _routeIds.where(
      (value) => !_authorizedRouteIds.contains(value),
    )) {
      yield RealtimeSubscription('subscribe.route', routeId);
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
      _authorizedRouteIds
        ..clear()
        ..add(normalized);
    } else if (eventName == 'subscribe.trip' && _tripIds.contains(normalized)) {
      _authorizedTripIds.add(normalized);
    }
  }

  void reject(String eventName, String identifier) {
    if (eventName == 'subscribe.route') {
      _remove(_routeIds, _authorizedRouteIds, identifier);
    } else if (eventName == 'subscribe.trip') {
      _remove(_tripIds, _authorizedTripIds, identifier);
    }
  }

  void clear() {
    _routeIds.clear();
    _tripIds.clear();
    _authorizedRouteIds.clear();
    _authorizedTripIds.clear();
  }

  bool _add(Set<String> values, String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && values.add(normalized);
  }

  bool _remove(
    Set<String> values,
    Set<String> authorizedValues,
    String value,
  ) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    authorizedValues.remove(normalized);
    return values.remove(normalized);
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
