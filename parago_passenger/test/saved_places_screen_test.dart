import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/screens/passenger/saved_places_screen.dart';

class PlacesApi extends ApiClient {
  final places = <Map<String, dynamic>>[];
  bool offline = false;
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    expect(useCache, false);
    if (pending != null) await pending!.future;
    if (offline) throw StateError('offline');
    if (method == 'POST') {
      writes++;
      places.add({'_id': 'place1', ...body as Map<String, dynamic>});
    }
    if (method == 'DELETE') {
      writes++;
      places.clear();
    }
    return {'data': List<Map<String, dynamic>>.from(places)};
  }
}

void main() {
  testWidgets(
      'save validates names, persists and removes only after confirmation',
      (tester) async {
    final api = PlacesApi();
    final account = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
        home: SavedPlacesScreen(
            client: api,
            sources: const [PlaceSource('Pinned pickup', LatLng(14.8, 121.1))],
            accountChanges: account,
            isCurrentAccount: () => account.value)));
    await tester.pumpAndSettle();
    expect(find.text('No saved places yet.'), findsOneWidget);
    await tester.tap(find.text('Add a place'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a place name'), findsOneWidget);
    expect(api.writes, 0);
    await tester.enterText(find.byType(TextFormField), 'Home');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(api.writes, 1);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No saved places yet.'), findsOneWidget);
    expect(api.writes, 2);
  });
  testWidgets('offline error can retry without presenting a false empty result',
      (tester) async {
    final api = PlacesApi()..offline = true;
    final account = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
        home: SavedPlacesScreen(
            client: api,
            sources: const [],
            accountChanges: account,
            isCurrentAccount: () => account.value)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not complete'), findsOneWidget);
    expect(find.text('No saved places yet.'), findsNothing);
    api.offline = false;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No saved places yet.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton))
            .onPressed,
        isNull);
  });
  testWidgets('delayed response cannot reveal places after sign out',
      (tester) async {
    final api = PlacesApi()..pending = Completer<void>();
    api.places.add(
        {'_id': 'secret', 'name': 'Private home', 'lat': 14.8, 'lng': 121.1});
    final account = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
        home: SavedPlacesScreen(
            client: api,
            sources: const [],
            accountChanges: account,
            isCurrentAccount: () => account.value)));
    account.value = false;
    api.pending!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Private home'), findsNothing);
    expect(find.textContaining('Your session changed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'saved place returns coordinates and purpose without sending a booking',
      (tester) async {
    final api = PlacesApi();
    final account = ValueNotifier(true);
    api.places.add({'_id': 'one', 'name': 'Work', 'lat': 14.8, 'lng': 121.1});
    SavedPlaceSelection? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  selected = await Navigator.push<SavedPlaceSelection>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SavedPlacesScreen(
                              client: api,
                              sources: const [],
                              accountChanges: account,
                              isCurrentAccount: () => account.value)));
                },
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use as unload'));
    await tester.pumpAndSettle();
    expect(selected!.forPickup, false);
    expect(selected!.point.latitude, 14.8);
    expect(api.writes, 0);
  });
  testWidgets('long names and actions fit a narrow phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PlacesApi();
    final account = ValueNotifier(true);
    api.places.add({
      '_id': 'one',
      'name': 'A long saved destination near the terminal and public school',
      'lat': 14.8,
      'lng': 121.1
    });
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: SavedPlacesScreen(
            client: api,
            sources: const [PlaceSource('Pinned unload', LatLng(14.8, 121.1))],
            accountChanges: account,
            isCurrentAccount: () => account.value)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Add a place'));
    await tester.tap(find.text('Add a place'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
