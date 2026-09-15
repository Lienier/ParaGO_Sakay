import '../models/operations/pickup_request.dart';
import '../models/operations/ride_session.dart';

String? passengerBookingBlockedReason({
  required Iterable<RideSessionModel> rides,
  required Iterable<PickupRequestModel> requests,
  DateTime? now,
}) {
  if (rides.any((r) => r.status == 'onboard' || r.status == 'waiting')) {
    return 'You are currently in a ride';
  }
  final at = now ?? DateTime.now();
  if (requests.any((r) =>
      ['pending', 'acknowledged', 'transfer_offered'].contains(r.status) &&
      (DateTime.tryParse(r.expiresAt ?? '')?.isAfter(at) ?? true))) {
    return 'You already have a pickup request or transfer offer';
  }
  return null;
}
