import 'glass_surface.dart';
import 'package:flutter/material.dart';
import '../models/operations/ride_session.dart';

Future<int?> confirmPassengerCount(
  BuildContext context, {
  required String title,
  required String identity,
  required int maximum,
  required String actionLabel,
}) async {
  var count = maximum;
  return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
            builder: (context, update) => GlassAlertDialog(
              scrollable: true,
              title: Text(title),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(identity),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: count,
                  decoration: const InputDecoration(
                      labelText: 'Actual number of people'),
                  items: List.generate(
                      maximum,
                      (i) => DropdownMenuItem(
                          value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (value) => update(() => count = value ?? maximum),
                ),
                const Text(
                    'Confirm only after checking the people physically entering or leaving the jeep. Cancel if nobody has moved.'),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, count),
                    child: Text(actionLabel)),
              ],
            ),
          ));
}

Future<bool> confirmPassengerUnload(
    BuildContext context, RideSessionModel ride) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          scrollable: true,
          title: const Text('Mark passenger unloaded?'),
          content: Text('${ride.passengerLabel}\nBooking ${ride.bookingLabel}\n'
              'Destination: ${ride.destinationStopRef ?? "Saved destination"}\n\n'
              'Confirm only after this passenger has left the jeep. This closes their ride and releases one seat.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Mark unloaded')),
          ],
        ),
      ) ??
      false;
}
