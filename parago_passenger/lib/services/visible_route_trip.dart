import '../models/transport/route_summary.dart';
import '../models/trip/trip_session.dart';

bool tripMatchesSelectedRoute(TripSession trip, RouteSummaryModel? route) {
  if (route == null) return false;
  // Known route IDs are authoritative, including opposite directions sharing
  // a name. Name/code fallback is only for older payloads without an ID.
  if (trip.routeId.isNotEmpty) return trip.routeId == route.id;
  if ((trip.routeCode ?? '').trim().isNotEmpty) {
    return trip.routeCode!.trim().toLowerCase() ==
        route.code.trim().toLowerCase();
  }
  return (trip.routeName ?? '').trim().isNotEmpty &&
      trip.routeName!.trim().toLowerCase() == route.name.trim().toLowerCase();
}

TripSession? selectVisibleRouteTrip(
    {required RouteSummaryModel? route,
    required TripSession? preferred,
    required TripSession? onboard,
    required Iterable<TripSession> candidates,
    required bool Function(TripSession) isEligible}) {
  if (route == null) return preferred ?? onboard ?? candidates.firstOrNull;
  if (preferred != null &&
      tripMatchesSelectedRoute(preferred, route) &&
      (preferred.id == onboard?.id || isEligible(preferred))) {
    return preferred;
  }
  if (onboard != null && tripMatchesSelectedRoute(onboard, route)) {
    return onboard;
  }
  return candidates
      .where((t) => tripMatchesSelectedRoute(t, route) && isEligible(t))
      .firstOrNull;
}
