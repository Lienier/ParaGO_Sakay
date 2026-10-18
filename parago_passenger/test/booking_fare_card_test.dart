import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/widgets/booking_fare_reference.dart';
import 'package:parago_passenger/widgets/glass_surface.dart';

void main() {
  testWidgets(
      'all legacy fare, route and expiry text remains readable in glass',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Theme(
                data: GlassSurface.theme(context),
                child: const Scaffold(
                    body: BookingFareCard(
                        regular: 14,
                        boardingStop: 'Puregold',
                        destinationStop: 'College'))))));
    expect(find.textContaining('₱14.00'), findsNWidgets(2));
    expect(find.textContaining('₱11.20'), findsOneWidget);
    final text = find.descendant(
        of: find.byType(BookingFareCard), matching: find.byType(Text));
    for (final element in text.evaluate()) {
      expect(DefaultTextStyle.of(element).style.color, BookingFareCard.ink);
    }
    final background = Color.alphaBlend(BookingFareCard.surface, Colors.white);
    final contrast = (BookingFareCard.ink.computeLuminance() + .05) /
        (background.computeLuminance() + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'long fare references scroll without clipping at 320 pixels and double text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: BookingFareCard(
                        regular: 14,
                        partySize: 3,
                        boardingStop: 'H. Bernabe Street, Poblacion',
                        destinationStop:
                            'Bestlink College of the Philippines'))))));
    await tester.ensureVisible(find.textContaining('Bestlink College'));
    await tester.pumpAndSettle();
    expect(find.textContaining('₱42.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
