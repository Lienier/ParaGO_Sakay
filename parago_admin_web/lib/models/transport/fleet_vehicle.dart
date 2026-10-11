import 'package:latlong2/latlong.dart';

class FleetVehicle {
  FleetVehicle(Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get id => data['jeepneyId']?.toString() ?? '';
  String get plate => data['plateNumber']?.toString() ?? id;
  String get routeId => data['routeId']?.toString() ?? '';
  String get routeName => data['routeName']?.toString() ?? '';
  String get driverName => data['driverName']?.toString() ?? '';
  DateTime? get lastSeenAt =>
      DateTime.tryParse(data['lastSeenAt']?.toString() ?? '');
  DateTime? get capturedAt =>
      DateTime.tryParse(data['capturedAt']?.toString() ?? '') ?? lastSeenAt;
  LatLng? get position {
    final lat = data['latitude'], lng = data['longitude'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  String gpsStatus(DateTime now) {
    if (position == null || capturedAt == null) return 'No GPS';
    final age = now.difference(capturedAt!).inSeconds;
    if (age < -15 || age > 120) return 'Offline';
    if (age > 30) return 'Old GPS';
    return 'Live';
  }
}

class FleetVehicles {
  final Map<String, FleetVehicle> _items = {};
  List<FleetVehicle> get all =>
      _items.values.toList()..sort((a, b) => a.plate.compareTo(b.plate));
  FleetVehicle? byId(String id) => _items[id];
  bool _newer(Map<String, dynamic> proposed, FleetVehicle? previous) {
    if (previous == null) return true;
    final seen = DateTime.tryParse(proposed['lastSeenAt']?.toString() ?? '');
    if (seen == null) return previous.lastSeenAt == null;
    if (previous.lastSeenAt != null && seen.isBefore(previous.lastSeenAt!)) {
      return false;
    }
    if (proposed['streamId'] == previous.data['streamId'] &&
        proposed['sequence'] is num &&
        previous.data['sequence'] is num &&
        (proposed['sequence'] as num) < (previous.data['sequence'] as num)) {
      return false;
    }
    return true;
  }

  void snapshot(List<dynamic> rows) {
    final next = <String, FleetVehicle>{};
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['jeepneyId']?.toString() ?? '';
      if (id.isEmpty) continue;
      final previous = _items[id];
      if (!_newer(row, previous)) {
        for (final key in [
          'latitude',
          'longitude',
          'lastSeenAt',
          'capturedAt',
          'streamId',
          'sequence'
        ]) {
          row[key] = previous!.data[key];
        }
      }
      next[id] = FleetVehicle(row);
    }
    _items
      ..clear()
      ..addAll(next);
  }

  bool update(Map<String, dynamic> row) {
    final id = row['jeepneyId']?.toString() ?? '';
    if (id.isEmpty ||
        FleetVehicle(row).position == null ||
        !_newer(row, _items[id])) {
      return false;
    }
    // Unknown vehicles are reconciled through the authorized metadata snapshot.
    if (!_items.containsKey(id)) return false;
    _items[id] = FleetVehicle({..._items[id]!.data, ...row});
    return true;
  }

  List<FleetVehicle> filtered({String? route, String search = ''}) {
    final query = search.trim().toLowerCase();
    return all
        .where((v) =>
            (route == null || v.routeId == route) &&
            (query.isEmpty ||
                v.plate.toLowerCase().contains(query) ||
                v.driverName.toLowerCase().contains(query)))
        .toList();
  }
}
