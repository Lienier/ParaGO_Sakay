import 'glass_surface.dart';
import 'package:flutter/material.dart';
import '../models/operations/pickup_request.dart';

class JourneySummary extends StatelessWidget {
  const JourneySummary({super.key, required this.members});
  final List<JourneyMemberModel> members;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('Passengers'),
        subtitle: Text(
            '${members.where((m) => m.status == 'onboard').length} onboard · ${members.length} total'),
        tilePadding: EdgeInsets.zero,
        children: [JourneyMembers(members: members)],
      );
}

class JourneyMembers extends StatelessWidget {
  const JourneyMembers({super.key, required this.members});
  final List<JourneyMemberModel> members;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        for (final member in members)
          ListTile(
            dense: false,
            minVerticalPadding: 12,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            leading: Icon(member.status == 'completed'
                ? Icons.check_circle
                : Icons.person),
            title: Text('${member.label}: ${member.destinationStopRef}'),
            subtitle: Text(
                '${member.status == 'completed' ? 'Unloaded' : member.status == 'onboard' ? 'Onboard' : member.status == 'cancelled' ? 'Cancelled' : member.status == 'expired' ? 'Expired' : 'Reserved'} • ₱${member.fare.toStringAsFixed(2)}'),
          ),
        Text(
            'Total: ₱${members.fold<double>(0, (sum, m) => sum + m.fare).toStringAsFixed(2)}'),
      ]);
}

class JourneyPickupPin extends StatelessWidget {
  const JourneyPickupPin(
      {super.key, required this.members, required this.pickup});
  final List<JourneyMemberModel> members;
  final String pickup;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => showDialog<void>(
          context: context,
          builder: (_) => GlassAlertDialog(
                  scrollable: true,
                  title: Text(pickup),
                  content: JourneyMembers(members: members),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'))
                  ])),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: const Color(0xFF102725),
                borderRadius: BorderRadius.circular(8)),
            child: Text(JourneyMemberModel.destinationSummary(members),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11))),
        const Icon(Icons.person_pin_circle, color: Color(0xFF087F8C), size: 34),
      ]));
}

/// Status only: the backend uses driver GPS to identify the reached destination.
class AutomaticDropoffStatus extends StatelessWidget {
  const AutomaticDropoffStatus({super.key, required this.members});
  final List<JourneyMemberModel> members;
  @override
  Widget build(BuildContext context) {
    final remaining =
        members.where((member) => member.status == 'onboard').toList();
    final ordered = remaining
        .where((member) => member.destinationStopOrder != null)
        .toList()
      ..sort(
          (a, b) => a.destinationStopOrder!.compareTo(b.destinationStopOrder!));
    final next = ordered.isNotEmpty && ordered.length == remaining.length
        ? ordered.first
        : null;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Auto drop-off'),
          if (next != null) ...[
            const SizedBox(height: 6),
            Text('Next: ${next.destinationStopRef}', softWrap: true)
          ],
        ]));
  }
}
