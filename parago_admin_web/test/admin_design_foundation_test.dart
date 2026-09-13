import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/widgets/app_card.dart';
import 'package:parago_admin_web/core/utils/parago_format.dart';
void main() {
  test('Philippine date boundary and missing timestamps', () {
    expect(ParagoFormat.dateTime('2026-09-10T18:05:00Z'), contains('Sep 11, 2026'));
    expect(ParagoFormat.shortTime('2026-09-10T18:05:00Z'), '2:05 AM');
    expect(ParagoFormat.shortTime(null), 'Not available');
    expect(ParagoFormat.relative(null), 'Not available');
  });
  testWidgets('narrow header preserves long title and action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var pressed = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(24),
      child: AppPageHeader(title: 'Terminal operations and service announcements',
        trailing: FilledButton(onPressed: () => pressed = true, child: const Text('New announcement'))),
    ))));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('New announcement'));
    expect(pressed, isTrue);
  });
}

