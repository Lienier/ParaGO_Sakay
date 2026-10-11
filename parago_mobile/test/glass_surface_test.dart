import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/theme/app_theme.dart';
import 'package:parago_mobile/widgets/glass_surface.dart';

void main() {
  testWidgets('long detail text stacks at narrow widths with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const route =
        'Norzagaray Municipal Hall Annex to Bestlink College of the Philippines';
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
                body: GlassSurface(
                    padding: EdgeInsets.all(20),
                    child: ReadableDetailRow(label: 'Route', value: route))))));
    final label = tester.getRect(find.text('Route'));
    final value = tester.getRect(find.text(route));
    expect(value.top, greaterThan(label.bottom));
    expect(value.right, lessThanOrEqualTo(300));
    expect(value.height, greaterThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('popup notices swipe both ways and expire after five seconds',
      (tester) async {
    late BuildContext scaffoldContext;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Builder(builder: (context) {
          scaffoldContext = context;
          return const Text('Map');
        }))));
    void send() => ScaffoldMessenger.of(scaffoldContext)
        .showSnackBar(GlassSnackBar(content: const Text('Ride ready')));
    send();
    await tester.pumpAndSettle();
    await tester.drag(find.text('Ride ready'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ride ready'), findsNothing);
    send();
    await tester.pumpAndSettle();
    await tester.drag(find.text('Ride ready'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ride ready'), findsNothing);
    send();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Ride ready'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Ride ready'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'swiping a timed banner cancels its timer and dismisses only once',
      (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SwipeNotice(
                duration: const Duration(seconds: 8),
                onDismiss: () => dismissed++,
                child: const GlassSurface(child: Text('Route ready'))))));
    await tester.drag(find.text('Route ready'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SwipeNotice(
                key: const ValueKey('next'),
                duration: const Duration(seconds: 8),
                onDismiss: () => dismissed++,
                child: const GlassSurface(child: Text('New notice'))))));
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('New notice'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('New notice'), findsNothing);
    expect(dismissed, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass confirmation fits a narrow screen and returns its result',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? result;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<bool>(
                          context: context,
                          builder: (context) => GlassAlertDialog(
                                  scrollable: true,
                                  title: const Text('Fix drop-off'),
                                  content: Text(
                                      List.filled(16, 'Passenger 2: Market')
                                          .join('\n')),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Save'))
                                  ]));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.getRect(find.text('Save')).bottom, lessThan(640));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass messages wrap long text and retain dismissal',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const message =
        'Your booking is ready. Keep your phone near your assigned jeep. Passenger 2: Market.';
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        GlassSnackBar(
                            content: const Text(message),
                            showCloseIcon: true,
                            duration: const Duration(seconds: 20))),
                    child: const Text('Send'))))));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text(message)).width, lessThan(320));
    expect(DefaultTextStyle.of(tester.element(find.text(message))).style.color,
        GlassSurface.ink);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass sheet supports scrolling and a returned selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? result;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showGlassBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (context) => SizedBox(
                              height: 400,
                              child: ListView(children: [
                                for (var i = 0; i < 12; i++)
                                  ListTile(
                                      title: Text('Stop $i'),
                                      onTap: () =>
                                          Navigator.pop(context, 'Stop $i'))
                              ])));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Stop 11'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Stop 11'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop 11'));
    await tester.pumpAndSettle();
    expect(result, 'Stop 11');
    expect(tester.takeException(), isNull);
  });
}
