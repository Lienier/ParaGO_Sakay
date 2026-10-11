import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/models/transport/fleet_vehicle.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9, 4);
  Map<String, dynamic> row(String id, {int age = 0, double? lat = 14.9, int sequence = 1}) => {
    'jeepneyId': id, 'plateNumber': 'ABC $id', 'driverName': 'Juan Santos', 'routeId': 'route-a',
    'latitude': lat, 'longitude': 121.05, 'streamId': 'stream', 'sequence': sequence,
    'lastSeenAt': now.subtract(Duration(seconds: age)).toIso8601String(),
    'capturedAt': now.subtract(Duration(seconds: age)).toIso8601String(),
  };
  test('freshness uses GPS observation time, ages without incoming updates, and missing GPS is never live', () {
    expect(FleetVehicle(row('1')).gpsStatus(now), 'Live');
    expect(FleetVehicle(row('1', age: 31)).gpsStatus(now), 'Old GPS');
    expect(FleetVehicle(row('1', age: 121)).gpsStatus(now), 'Offline');
    expect(FleetVehicle(row('1', lat: null)).gpsStatus(now), 'No GPS');
    expect(FleetVehicle({...row('1'), 'latitude': double.nan}).position, null);
    expect(FleetVehicle({...row('1'), 'capturedAt': now.add(const Duration(minutes: 1)).toIso8601String()}).gpsStatus(now), 'Offline');
    expect(FleetVehicle({...row('1'), 'capturedAt': now.subtract(const Duration(minutes: 5)).toIso8601String()}).gpsStatus(now), 'Offline');
  });
  test('slow snapshot and out-of-order packets cannot undo a newer location; metadata still reconciles', () {
    final fleet = FleetVehicles(); fleet.snapshot([row('1', age: 20)]);
    expect(fleet.update(row('1', lat: 14.92, sequence: 2)), true);
    fleet.snapshot([{...row('1', age: 15), 'driverName': 'Updated driver'}]);
    expect(fleet.byId('1')!.position!.latitude, 14.92);
    expect(fleet.byId('1')!.driverName, 'Updated driver');
    expect(fleet.update(row('1', lat: 14.93)), false);
    expect(fleet.update({...row('1'), 'latitude': 999}), false);
  });
  test('all 100 vehicles remain available; search/route filters and deletion reconcile', () {
    final fleet = FleetVehicles(); fleet.snapshot(List.generate(100, (i) => row('$i')));
    expect(fleet.all.length, 100); expect(fleet.filtered(route: 'route-a').length, 100);
    expect(fleet.filtered(search: 'ABC 99').single.id, '99');
    expect(fleet.filtered(search: 'juan').length, 100); expect(fleet.filtered(route: 'route-b'), isEmpty);
    fleet.snapshot([row('1')]); expect(fleet.all.length, 1);
  });
}
