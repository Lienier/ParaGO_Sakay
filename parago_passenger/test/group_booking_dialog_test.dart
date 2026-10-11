import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/services/passenger_service.dart';
import 'package:parago_passenger/widgets/group_booking_dialog.dart';
import 'package:parago_passenger/core/exceptions/api_exception.dart';
import 'package:parago_passenger/models/operations/pickup_request.dart';

class QuoteService extends PassengerService {
  QuoteService() : super(ApiClient(baseUrl: 'http://127.0.0.1'));
  @override
  Future<Map<String, dynamic>> quoteBooking(Map<String, dynamic> body) async =>
      {
        'quoteToken': 'reviewed',
        'regularTotal': 17,
        'members': [
          for (final m in body['members'] as List)
            {
              ...m as Map,
              'fareSnapshot': {'amount': 17}
            }
        ],
      };
}

class ChangedPriceService extends QuoteService {
  int submissions = 0;
  @override
  Future<PickupRequestModel> createQuotedBooking(
      Map<String, dynamic> body) async {
    submissions++;
    throw ApiException(409, 'Prices changed. Review the updated quote.');
  }
}

void main() {
  testWidgets(
      'long drop-off names remain readable with enlarged text at 320 pixels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const stop = 'Bestlink College of the Philippines, Quirino Highway';
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: GroupBookingDialog(
                    service: QuoteService(),
                    maxSeats: 2,
                    basePayload: const {
                  'routeId': 'route',
                  'stopRef': 'Norzagaray Municipal Hall Annex'
                },
                    destinations: const [
                  {'destinationStopRef': stop}
                ])))));
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(stop).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Book'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'price rejection keeps companion destinations and requires review again',
      (tester) async {
    final service = ChangedPriceService();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GroupBookingDialog(
                service: service,
                maxSeats: 2,
                basePayload: const {
          'routeId': 'route',
          'stopRef': 'Pickup'
        },
                destinations: const [
          {
            'destinationStopRef': 'College',
            'destinationLocation': {
              'type': 'Point',
              'coordinates': [121, 14]
            }
          },
          {
            'destinationStopRef': 'Mall',
            'destinationLocation': {
              'type': 'Point',
              'coordinates': [121, 14.1]
            }
          },
        ]))));
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('College').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mall').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(service.submissions, 1);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
    expect(find.text('College'), findsOneWidget);
    expect(find.text('Mall'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Book'), findsNothing);
    expect(
        find.text('Prices changed. Review the updated quote.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'quote review is required; destination edits invalidate review and seats limit companions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GroupBookingDialog(
                service: QuoteService(),
                maxSeats: 2,
                basePayload: const {
          'routeId': 'route',
          'stopRef': 'Shared pickup'
        },
                destinations: const [
          {
            'destinationStopRef': 'College',
            'destinationLocation': {
              'type': 'Point',
              'coordinates': [121, 14]
            }
          },
          {
            'destinationStopRef': 'Mall',
            'destinationLocation': {
              'type': 'Point',
              'coordinates': [121, 14.1]
            }
          },
        ]))));
    expect(find.text('Book'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('College').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Fare: ₱17.00'), findsOneWidget);
    expect(find.text('Total: ₱17.00'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Book'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
