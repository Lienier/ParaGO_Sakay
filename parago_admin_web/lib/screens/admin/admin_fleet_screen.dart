import 'package:parago_map_ui/road_jeep_marker.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../models/transport/fleet_vehicle.dart';
import '../../services/admin_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';

class AdminFleetScreen extends StatefulWidget {
  const AdminFleetScreen({super.key, required this.realtimeSocketService});
  final RealtimeSocketService realtimeSocketService;
  @override
  State<AdminFleetScreen> createState() => AdminFleetScreenState();
}

class AdminFleetScreenState extends State<AdminFleetScreen>
    with WidgetsBindingObserver {
  final _fleet = FleetVehicles();
  final _map = MapController();
  final _searchController = TextEditingController();
  final _pending = <String, Map<String, dynamic>>{};
  StreamSubscription<Map<String, dynamic>>? _locations;
  StreamSubscription<bool>? _connection;
  StreamSubscription<Map<String, dynamic>>? _operations;
  Timer? _poll, _clock, _paint, _reconcile;
  bool _loading = false,
      _loaded = false,
      _connected = false,
      _mapReady = false,
      _fitted = false;
  String? _error, _route, _selected;
  String _search = '';
  double _zoom = 11;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connected = widget.realtimeSocketService.isConnected;
    _locations =
        widget.realtimeSocketService.fleetLocationsStream.listen(_receive);
    _connection =
        widget.realtimeSocketService.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() => _connected = connected);
      if (connected) unawaited(refresh());
    });
    _operations = widget.realtimeSocketService.operationsChangedStream
        .listen((_) => _scheduleReconcile());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    _clock = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  void _scheduleReconcile() {
    _reconcile ??= Timer(const Duration(seconds: 2), () {
      _reconcile = null;
      unawaited(refresh());
    });
  }

  void _receive(Map<String, dynamic> payload) {
    final rows = payload['vehicles'];
    if (rows is! List) return;
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['jeepneyId']?.toString() ?? '';
      final vehicle = _fleet.byId(id);
      if (vehicle == null ||
          vehicle.routeId != row['routeId'] ||
          vehicle.data['driverId'] != row['driverId']) {
        _scheduleReconcile();
      }
      final prior = _pending[id];
      final at = DateTime.tryParse(row['lastSeenAt']?.toString() ?? '');
      final old = DateTime.tryParse(prior?['lastSeenAt']?.toString() ?? '');
      if (at != null && (old == null || !at.isBefore(old))) _pending[id] = row;
    }
    _paint ??= Timer(const Duration(milliseconds: 250), () {
      _paint = null;
      if (!mounted) return;
      setState(() {
        for (final row in _pending.values) {
          _fleet.update(row);
        }
        _pending.clear();
      });
      _initialFit();
    });
  }

  Future<void> refresh() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final data =
          await AdminService(context.read<SessionController>().apiClient)
              .fleet();
      if (!mounted) return;
      setState(() {
        _fleet
            .snapshot(data['vehicles'] is List ? data['vehicles'] as List : []);
        _loaded = true;
        _error = null;
        _lastRefresh = DateTime.now();
        if (_route != null && !_fleet.all.any((v) => v.routeId == _route)) {
          _route = null;
        }
        if (_selected != null && _fleet.byId(_selected!) == null) {
          _selected = null;
        }
      });
      _initialFit();
    } catch (_) {
      if (mounted) {
        setState(() => _error = _loaded
            ? 'Refresh failed. Showing previous locations.'
            : 'Unable to load fleet locations.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  List<FleetVehicle> get _visible =>
      _fleet.filtered(route: _route, search: _search);
  void _initialFit() {
    if (_fitted || !_mapReady || !_visible.any((v) => v.position != null)) {
      return;
    }
    _fitted = true;
    _fit();
  }

  void _fit() {
    final points = _visible.map((v) => v.position).whereType<LatLng>().toList();
    if (!_mapReady || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(45),
        maxZoom: 16));
  }

  Color _color(String status) => switch (status) {
        'Live' => const Color(0xFF087F75),
        'Old GPS' => const Color(0xFFB76B00),
        _ => const Color(0xFF607080)
      };
  String _age(FleetVehicle v) {
    final at = v.capturedAt;
    if (at == null || v.position == null) return 'No location received';
    final seconds = DateTime.now().difference(at).inSeconds;
    if (seconds < -15) return 'GPS clock is ahead';
    if (seconds < 60) return '${math.max(0, seconds)} seconds ago';
    if (seconds < 3600) return '${seconds ~/ 60} minutes ago';
    return at.toLocal().toString().split('.')[0];
  }

  List<Marker> _markers(List<FleetVehicle> vehicles) {
    final groups = <String, List<FleetVehicle>>{};
    final scale = 256 * math.pow(2, _zoom);
    for (final v in vehicles.where((v) => v.position != null)) {
      final p = v.position!;
      final sinLat = math.sin(p.latitude.clamp(-85, 85) * math.pi / 180);
      final x = (p.longitude + 180) / 360 * scale;
      final y =
          (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
      final key = _zoom >= 17 || v.id == _selected
          ? v.id
          : '${(x / 48).floor()}:${(y / 48).floor()}';
      groups.putIfAbsent(key, () => []).add(v);
    }
    return groups.values.map((group) {
      final single = group.length == 1;
      final v = group.first;
      final point = LatLng(
          group.map((v) => v.position!.latitude).reduce((a, b) => a + b) /
              group.length,
          group.map((v) => v.position!.longitude).reduce((a, b) => a + b) /
              group.length);
      if (single) {
        return Marker(
            point: v.position!,
            rotate: true,
            width: RoadJeepMarker.extent,
            height: RoadJeepMarker.extent,
            child: RoadJeepMarker(
                latitude: v.position!.latitude,
                headingDegrees: (v.data['headingDegrees'] as num?)?.toDouble(),
                label: 'Jeep ${v.plate}',
                selected: v.id == _selected,
                color: _color(v.gpsStatus(DateTime.now())),
                tooltip: '${v.plate}: ${v.gpsStatus(DateTime.now())}',
                onTap: () => setState(() => _selected = v.id)));
      }
      return Marker(
          point: point,
          width: 48,
          height: 48,
          child: Tooltip(
              message: single
                  ? '${v.plate} · ${v.gpsStatus(DateTime.now())}'
                  : '${group.length} jeeps — tap to zoom in',
              child: Semantics(
                  button: true,
                  label: single
                      ? 'Jeep ${v.plate}'
                      : '${group.length} grouped jeeps',
                  child: InkWell(
                      onTap: () {
                        if (single) {
                          setState(() => _selected = v.id);
                        } else {
                          _map.move(point, math.min(_zoom + 2, 18));
                        }
                      },
                      child: Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: single
                                  ? _color(v.gpsStatus(DateTime.now()))
                                  : const Color(0xFF225FAA),
                              border: Border.all(
                                  color: v.id == _selected
                                      ? Colors.amber
                                      : Colors.white,
                                  width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4)
                              ]),
                          alignment: Alignment.center,
                          child: single
                              ? const Icon(Icons.directions_bus,
                                  color: Colors.white, size: 23)
                              : Text('${group.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)))))));
    }).toList();
  }

  Widget _details(FleetVehicle v) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE5EB)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(v.plate,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold))),
          IconButton(
              tooltip: 'Close jeep details',
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.close))
        ]),
        Text('Driver: ${v.driverName.isEmpty ? 'Unassigned' : v.driverName}'),
        Text('Route: ${v.routeName.isEmpty ? 'Unassigned' : v.routeName}'),
        Text(
            'Vehicle: ${v.data['status'] ?? 'Unknown'} · ${v.data['tripId']?.toString().isNotEmpty == true ? 'Active trip' : 'No active trip'}'),
        Text('GPS: ${v.gpsStatus(DateTime.now())} · ${_age(v)}',
            style: TextStyle(color: _color(v.gpsStatus(DateTime.now())))),
        if (v.position != null)
          Text(
              '${v.position!.latitude.toStringAsFixed(5)}, ${v.position!.longitude.toStringAsFixed(5)}'),
        Text(
            'Onboard: ${v.data['occupancyCount'] ?? 0} · Capacity: ${v.data['capacity'] ?? 'Unknown'}'),
      ]));
  @override
  Widget build(BuildContext context) {
    final vehicles = _visible;
    final now = DateTime.now();
    final routes = <String, String>{};
    for (final v in _fleet.all) {
      if (v.routeId.isNotEmpty) {
        routes[v.routeId] = v.routeName.isEmpty ? v.routeId : v.routeName;
      }
    }
    final sortedRoutes = routes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final selected = _selected == null ? null : _fleet.byId(_selected!);
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Live fleet map',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const Text(
          'All registered jeeps. Positions update while driver phones share GPS.'),
      const SizedBox(height: 12),
      Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
                AppConfig.enableRealtime && _connected
                    ? 'Live connection'
                    : 'Live connection unavailable · refreshing every 20 seconds',
                style: TextStyle(
                    color: _connected ? _color('Live') : _color('Old GPS'))),
            TextButton.icon(
                onPressed: _loading ? null : refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh fleet')),
            if (_lastRefresh != null)
              Text(
                  'Fleet refreshed ${_lastRefresh!.toLocal().toString().split('.')[0]}',
                  style: const TextStyle(fontSize: 12)),
          ]),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(
            width: 280,
            child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                    labelText: 'Search plate or driver',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear fleet search',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            }),
                    border: const OutlineInputBorder()),
                onChanged: (s) => setState(() => _search = s))),
        SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
                key: ValueKey(_route),
                initialValue: _route == '' ? 'unassigned' : _route ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Route', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All routes')),
                  const DropdownMenuItem(
                      value: 'unassigned', child: Text('Unassigned')),
                  ...sortedRoutes.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis)))
                ],
                onChanged: (v) => setState(() => _route = v == ''
                    ? null
                    : v == 'unassigned'
                        ? ''
                        : v))),
        OutlinedButton.icon(
            onPressed: _fit,
            icon: const Icon(Icons.zoom_out_map),
            label: const Text('Fit visible jeeps')),
      ]),
      const SizedBox(height: 14),
      Semantics(
          container: true,
          label: '${vehicles.length} jeeps shown. ${[
            'Live',
            'Old GPS',
            'Offline',
            'No GPS'
          ].map((status) => '$status: ${vehicles.where((v) => v.gpsStatus(now) == status).length}').join('. ')}',
          excludeSemantics: true,
          child: Wrap(spacing: 16, runSpacing: 8, children: [
            Text('${vehicles.length} jeeps shown'),
            for (final status in ['Live', 'Old GPS', 'Offline', 'No GPS'])
              Text(
                  '$status: ${vehicles.where((v) => v.gpsStatus(now) == status).length}',
                  style: TextStyle(color: _color(status))),
          ])),
      const SizedBox(height: 12),
      SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 380 : 480,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                      initialCenter: const LatLng(14.83, 121.04),
                      initialZoom: 11,
                      onMapReady: () {
                        _mapReady = true;
                        _initialFit();
                      },
                      onPositionChanged: (camera, _) {
                        if ((_zoom - camera.zoom).abs() > 0.1 && mounted) {
                          setState(() => _zoom = camera.zoom);
                        }
                      }),
                  children: [
                    TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.parago.admin'),
                    MarkerLayer(markers: _markers(vehicles)),
                    const RichAttributionWidget(attributions: [
                      TextSourceAttribution('OpenStreetMap contributors')
                    ])
                  ]))),
      const SizedBox(height: 8),
      const Text(
          'Green: GPS within 30 seconds. Amber: 31–120 seconds. Grey: older or missing GPS. Offline locations are last known positions. Blue circles group nearby jeeps.'),
      if (selected != null) ...[const SizedBox(height: 12), _details(selected)],
      const SizedBox(height: 18),
      if (_loaded && vehicles.isEmpty)
        const Text('No jeeps match your filters.'),
      if (vehicles.isNotEmpty)
        const Text(
            'Select a jeep below to view its details or center it on the map.'),
      for (final v in vehicles)
        ListTile(
            dense: true,
            selected: _selected == v.id,
            leading:
                Icon(Icons.directions_bus, color: _color(v.gpsStatus(now))),
            title: Text(v.plate),
            subtitle: Text(
                '${v.routeName.isEmpty ? 'Unassigned route' : v.routeName} · ${v.driverName.isEmpty ? 'Unassigned driver' : v.driverName}\n${_age(v)}'),
            isThreeLine: true,
            trailing: Text(v.gpsStatus(now)),
            onTap: () {
              setState(() => _selected = v.id);
              if (_mapReady && v.position != null) _map.move(v.position!, 17);
            }),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in [_poll, _clock, _paint, _reconcile]) {
      timer?.cancel();
    }
    _locations?.cancel();
    _connection?.cancel();
    _operations?.cancel();
    _map.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
