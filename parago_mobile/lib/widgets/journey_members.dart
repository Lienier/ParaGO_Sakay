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
                '${member.status == 'completed' ? 'Unloaded' : member.status == 'onboard' ? 'Onboard' : 'Reserved'} • ₱${member.fare.toStringAsFixed(2)}'),
          ),
        Text(
            'Total: ₱${members.fold<double>(0, (sum, m) => sum + m.fare).toStringAsFixed(2)}'),
      ]);
}

class JourneyPickupPin extends StatelessWidget {
  const JourneyPickupPin(
      {super.key,
      required this.members,
      required this.pickup,
      this.assignedJeepneyLabel});
  final List<JourneyMemberModel> members;
  final String pickup;
  final String? assignedJeepneyLabel;
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
            child: Text(
                '${JourneyMemberModel.destinationSummary(members)}\n${members.length} passenger(s)${assignedJeepneyLabel == null ? '' : ' · $assignedJeepneyLabel'}',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11))),
        const Icon(Icons.person_pin_circle, color: Color(0xFF087F8C), size: 34),
      ]));
}

Future<List<String>?> chooseUnloadedMembers(
    BuildContext context, List<JourneyMemberModel> members) {
  final selected = <String>{};
  return showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (context, setState) => GlassAlertDialog(
                scrollable: true,
                title: const Text('Fix drop-off'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Who got off?'),
                  for (final member
                      in members.where((m) => m.status == 'onboard'))
                    CheckboxListTile(
                        title: Text(
                            '${member.label}: ${member.destinationStopRef}'),
                        value: selected.contains(member.memberId),
                        onChanged: (checked) => setState(() {
                              if (checked == true) {
                                selected.add(member.memberId);
                              } else {
                                selected.remove(member.memberId);
                              }
                            })),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, selected.toList()),
                      child: const Text('Save'))
                ],
              )));
}
