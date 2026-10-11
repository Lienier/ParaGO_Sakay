import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_map_ui/road_jeep_marker.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('road footprint grows with zoom and accounts for latitude', () {
    expect(roadJeepWidth(zoom: 19, latitude: 14.9),
        closeTo(roadJeepWidth(zoom: 18, latitude: 14.9) * 2, .001));
    expect(roadJeepWidth(zoom: 18, latitude: 60),
        greaterThan(roadJeepWidth(zoom: 18, latitude: 0)));
    expect(roadJeepWidth(zoom: 3, latitude: 14.9), 8);
    expect(roadJeepWidth(zoom: 22, latitude: 14.9), 48);
  });
  testWidgets('jeep stays centered through zoom, selection and map rotation',
      (tester) async {
    final controller = MapController();
    var taps = 0;
    const point = LatLng(14.9, 121.05);
    Widget map(bool selected) => MaterialApp(
            home: Scaffold(
                body: FlutterMap(
                    mapController: controller,
                    options:
                        const MapOptions(initialCenter: point, initialZoom: 18),
                    children: [
              MarkerLayer(markers: [
                Marker(
                    point: point,
                    rotate: true,
                    width: RoadJeepMarker.extent,
                    height: RoadJeepMarker.extent,
                    child: RoadJeepMarker(
                        latitude: point.latitude,
                        label: 'Jeep PW 123',
                        selected: selected,
                        headingDegrees: 90,
                        onTap: () => taps++))
              ])
            ])));
    await tester.pumpWidget(map(false));
    await tester.pump();
    Offset centre() => tester.getCenter(find.byType(RoadJeepMarker));
    final before = centre();
    final oldWidth = tester.getSize(find.byType(CustomPaint).last).width;
    controller.move(point, 19);
    await tester.pump();
    expect((centre() - before).distance, lessThan(.001));
    expect(tester.getSize(find.byType(CustomPaint).last).width,
        closeTo(oldWidth * 2, .001));
    controller.rotate(45);
    await tester.pump();
    expect((centre() - before).distance, lessThan(.001));
    await tester.pumpWidget(map(true));
    await tester.pump();
    expect((centre() - before).distance, lessThan(.001));
    await tester.tap(find.byType(RoadJeepMarker));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
