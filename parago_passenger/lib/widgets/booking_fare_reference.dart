import 'package:flutter/material.dart';

int discountedFareCentavos(double regular) => (regular * 100 * 0.8).round();

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
