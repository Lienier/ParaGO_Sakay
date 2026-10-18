import 'package:flutter/material.dart';

int discountedFareCentavos(double regular) => (regular * 100 * 0.8).round();

/// All fare text shares an explicit dark glass surface and readable ink,
/// including the route and expiry text outside BookingFareReference.
class BookingFareCard extends StatelessWidget {
  const BookingFareCard(
      {super.key,
      required this.regular,
      this.partySize = 1,
      required this.boardingStop,
      required this.destinationStop});
  final double regular;
  final int partySize;
  final String boardingStop, destinationStop;
  static const surface = Color(0xE6184F46);
  static const ink = Colors.white;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white30)),
        child: DefaultTextStyle.merge(
            style: const TextStyle(color: ink, height: 1.5),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BookingFareReference(regular: regular, partySize: partySize),
              const SizedBox(height: 8),
              const Text('Arrive before booking expiry.'),
              const SizedBox(height: 4),
              Text('$boardingStop to $destinationStop'),
            ])),
      );
}

class BookingFareReference extends StatelessWidget {
  const BookingFareReference(
      {super.key, required this.regular, this.partySize = 1});
  final double regular;
  final int partySize;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Regular fare per person: ₱${regular.toStringAsFixed(2)}'),
          Text(
              'Student / Senior / PWD (20%): ₱${(discountedFareCentavos(regular) / 100).toStringAsFixed(2)} per person'),
          Text(
              'Regular total ($partySize ${partySize == 1 ? "person" : "people"}): ₱${(regular * partySize).toStringAsFixed(2)}'),
          const Text(
              'Discount reference only. Eligibility is not verified in the app.'),
        ],
      );
}
