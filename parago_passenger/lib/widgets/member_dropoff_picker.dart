import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/transport/route_summary.dart';
import 'glass_surface.dart';

/// A companion chooses only a destination. The group's pickup is read-only.
class MemberDropoffPicker extends StatefulWidget {
  const MemberDropoffPicker(
      {super.key,
      required this.label,
      required this.route,
      required this.pickup,
      required this.resolveDestination,
      this.initial});
  final String label;
  final RouteSummaryModel route;
  final LatLng pickup;
  final Map<String, dynamic>? initial;
  final Map<String, dynamic>? Function(LatLng) resolveDestination;
  @override
  State<MemberDropoffPicker> createState() => _MemberDropoffPickerState();
}

class _MemberDropoffPickerState extends State<MemberDropoffPicker> {
  final _map = MapController();
  Map<String, dynamic>? _selection;
  String? _error;
  @override
  void initState() {
    super.initState();
    _selection = widget.initial;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  LatLng? get _point {
    final c = _selection?['destinationLocation']?['coordinates'] as List?;
    return c == null
        ? null
        : LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  }

  void _choose(LatLng point) {
    final selected = widget.resolveDestination(point);
    setState(() {
      _error = selected == null
          ? 'Choose a point on the route, after pickup.'
          : null;
      if (selected != null) _selection = selected;
    });
  }

  @override
  Widget build(BuildContext context) => GlassAlertDialog(
        scrollable: true,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label),
          const Text('Drop-off', style: TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(
            width: 440,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tap your stop. Pickup is shared.'),
                  const SizedBox(height: 12),
                  SizedBox(
                      height:
                          MediaQuery.sizeOf(context).height < 700 ? 270 : 340,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(children: [
                            FlutterMap(
                                mapController: _map,
                                options: MapOptions(
                                    initialCenter: _point ?? widget.pickup,
                                    initialCameraFit: CameraFit.bounds(
                                        bounds: LatLngBounds.fromPoints([
                                          ...widget.route.mapPath,
                                          widget.pickup
                                        ]),
                                        padding: const EdgeInsets.fromLTRB(
                                            36, 30, 36, 30)),
                                    onTap: (_, point) => _choose(point)),
                                children: [
                                  TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.parago.passenger'),
                                  PolylineLayer(polylines: [
                                    Polyline(
                                        points: widget.route.mapPath,
                                        color: const Color(0xFF0F6A5F),
                                        strokeWidth: 6)
                                  ]),
                                  MarkerLayer(markers: [
                                    Marker(
                                        point: widget.pickup,
                                        width: 40,
                                        height: 40,
                                        child: const Tooltip(
                                            message: 'Shared pickup',
                                            child: Icon(Icons.person_pin_circle,
                                                color: Color(0xFF174F96),
                                                size: 38))),
                                    for (final stop in widget.route.stopPoints)
                                      Marker(
                                          point: stop.position,
                                          width: 24,
                                          height: 24,
                                          child: Tooltip(
                                              message: stop.name,
                                              child: const Icon(Icons.circle,
                                                  color: Color(0xFF0F6A5F),
                                                  size: 14))),
                                    if (_point != null)
                                      Marker(
                                          point: _point!,
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.topCenter,
                                          child: const IgnorePointer(
                                              child: Icon(Icons.location_pin,
                                                  color: Color(0xFFB93824),
                                                  size: 38))),
                                  ]),
                                ]),
                            Positioned(
                                right: 8,
                                bottom: 8,
                                child: Column(children: [
                                  IconButton.filled(
                                      tooltip: 'Zoom in',
                                      style: IconButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF103F39)),
                                      onPressed: () => _map.move(
                                          _map.camera.center,
                                          (_map.camera.zoom + 1).clamp(3, 19)),
                                      icon: const Icon(Icons.add)),
                                  IconButton.filled(
                                      tooltip: 'Zoom out',
                                      style: IconButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF103F39)),
                                      onPressed: () => _map.move(
                                          _map.camera.center,
                                          (_map.camera.zoom - 1).clamp(3, 19)),
                                      icon: const Icon(Icons.remove)),
                                ])),
                          ]))),
                  const SizedBox(height: 12),
                  Text(_selection?['destinationStopRef']?.toString() ??
                      'Choose a drop-off'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final stop in widget.route.stopPoints)
                      TextButton(
                          onPressed: () {
                            _choose(stop.position);
                            _map.move(stop.position, 16);
                          },
                          child: Text(stop.name)),
                  ]),
                  if (_error != null)
                    Text(_error!,
                        style: const TextStyle(color: Color(0xFFFFB4AB))),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _selection == null || _error != null
                  ? null
                  : () => Navigator.pop(context, _selection),
              child: const Text('Use drop-off'))
        ],
      );
}
