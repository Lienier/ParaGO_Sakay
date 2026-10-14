import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/widgets/driver_map_frame.dart';
import 'package:parago_mobile/widgets/map_follow_control.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('map stays above controls at width $width with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: DriverMapFrame(
                map:
                    const ColoredBox(key: ValueKey('map'), color: Colors.green),
                followControl: MapFollowControl(
                    status: 'Location unavailable', onRecenter: () {}),
                tripControl:
                    TextButton(onPressed: () {}, child: const Text('Trip')),
              )))));
      final map = tester.getRect(find.byKey(const ValueKey('map')));
      final follow = tester.getRect(find.byType(MapFollowControl));
      expect(follow.top, greaterThanOrEqualTo(map.bottom));
      expect(tester.getRect(find.text('Trip')).top,
          greaterThanOrEqualTo(map.bottom));
      expect(tester.takeException(), isNull);
    });
  }
}
