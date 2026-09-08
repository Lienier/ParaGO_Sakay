import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/widgets/legal_pages.dart';

void main() {
  testWidgets('Policies open and return without losing form input',
      (tester) async {
    final controller = TextEditingController(text: 'passenger@example.com');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Column(children: [
        TextField(controller: controller),
        const LegalLinks(),
      ])),
    ));
    for (final title in ['Terms & Conditions', 'Privacy Policy']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text('SakayGaray'), findsOneWidget);
      expect(find.text('Draft for review — not yet an effective policy.'),
          findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.text, 'passenger@example.com');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Privacy text scrolls on a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: const LegalPolicyPage(privacy: true),
    ));
    await tester.scrollUntilVisible(find.text('Policy status'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Policy status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
