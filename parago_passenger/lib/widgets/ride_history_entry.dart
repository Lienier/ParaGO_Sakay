import 'package:flutter/material.dart';
import '../models/operations/pickup_request.dart';
import '../models/operations/ride_session.dart';
import '../core/utils/parago_format.dart';
import 'glass_surface.dart';
import 'journey_members.dart';
import 'status_badge.dart';

String passengerCountLabel(int count) =>
    '$count ${count == 1 ? 'passenger' : 'passengers'}';

class RideHistoryEntry extends StatelessWidget {
  const RideHistoryEntry({super.key, required this.ride});
  final RideSessionModel ride;
  @override
  Widget build(BuildContext context) => GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(passengerCountLabel(ride.boardedCount),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                StatusBadge(status: ride.status)
              ]),
          const SizedBox(height: 8),
          Text(ride.members.isEmpty
              ? ride.destinationStopRef ?? 'Ride'
              : JourneyMemberModel.destinationSummary(ride.members)),
          Text('Boarded ${ParagoFormat.relative(ride.boardedAt)}'),
          if (ride.flowVersion == 2 && ride.members.isNotEmpty) ...[
            const SizedBox(height: 8),
            JourneyMembers(members: ride.members),
          ] else if (ride.estimatedFare != null) ...[
            const SizedBox(height: 8),
            Text(
                'Fare per passenger: ₱${ride.estimatedFare!.toStringAsFixed(2)}'),
            Text(
                'Total: ₱${(ride.regularTotal ?? ride.estimatedFare! * ride.boardedCount).toStringAsFixed(2)}'),
          ],
        ]),
      );
}
