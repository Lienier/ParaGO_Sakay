import 'package:flutter/material.dart';
import '../models/operations/ride_session.dart';

Future<bool> confirmPassengerUnload(
    BuildContext context, RideSessionModel ride) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
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
