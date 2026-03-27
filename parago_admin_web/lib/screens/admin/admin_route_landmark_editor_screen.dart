import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

class AdminRouteLandmarkEditorScreen extends StatefulWidget {
  const AdminRouteLandmarkEditorScreen({
    super.key,
    required this.route,
  });

  final RouteSummaryModel route;

  @override
  State<AdminRouteLandmarkEditorScreen> createState() =>
      _AdminRouteLandmarkEditorScreenState();
}

class _AdminRouteLandmarkEditorScreenState
    extends State<AdminRouteLandmarkEditorScreen> {
  static const _defaultCenter = LatLng(14.6091, 121.0223);
  static const _snapToleranceMeters = 150.0;

  final Distance _distance = const Distance();

  late List<_EditableRouteLandmark> _landmarks;
  bool _saving = false;
  bool _moveMode = false;
  String? _selectedLandmarkId;
  String? _message;

  @override
  void initState() {
    super.initState();
    _landmarks = [
      for (var index = 0; index < widget.route.stopPoints.length; index += 1)
        _EditableRouteLandmark(
          id: 'existing-$index',
          name: widget.route.stopPoints[index].name,
          code: widget.route.stopPoints[index].code,
          fare: widget.route.stopPoints[index].fare,
          position: widget.route.stopPoints[index].position,
        ),
    ];
    if (_landmarks.isNotEmpty) {
      _selectedLandmarkId = _landmarks.first.id;
      _message =
          'Select a landmark to edit it, or turn on move mode to reposition it.';
    } else {
      _message = 'Tap the route to add the first landmark and fare.';
    }
  }

  _EditableRouteLandmark? get _selectedLandmark {
    for (final landmark in _landmarks) {
      if (landmark.id == _selectedLandmarkId) {
        return landmark;
      }
    }
    return null;
  }

  List<LatLng> get _routePoints {
    final path = widget.route.mapPath;
    if (path.isNotEmpty) {
      return path;
    }
    return widget.route.referencePoints;
  }

  LatLng get _mapCenter {
    final bounds = widget.route.mapBounds;
    if (bounds != null) {
      return bounds.center;
    }
    final routePoints = _routePoints;
    if (routePoints.isNotEmpty) {
      return routePoints[routePoints.length ~/ 2];
    }
    return widget.route.originPoint ??
        widget.route.destinationPoint ??
        _defaultCenter;
  }

  double get _mapZoom {
    final bounds = widget.route.mapBounds;
    if (bounds == null) {
      return 14.4;
    }
    final latSpan = (bounds.north - bounds.south).abs();
    final lngSpan = (bounds.east - bounds.west).abs();
    final span = math.max(latSpan, lngSpan);
    if (span < 0.003) return 17.2;
    if (span < 0.008) return 16.4;
    if (span < 0.02) return 15.4;
    if (span < 0.05) return 14.2;
    if (span < 0.12) return 13.2;
    return 12;
  }

  Future<void> _handleMapTap(LatLng point) async {
    final projection = _nearestRouteProjection(point);
    if (projection == null) {
      setState(() {
        _message =
            'This route needs saved geometry first before landmarks can be placed.';
      });
      return;
    }
    if (projection.distanceMeters > _snapToleranceMeters) {
      setState(() {
        _message =
            'Tap closer to the route. Landmarks must stay within ${_snapToleranceMeters.toInt()} meters of the route.';
      });
      return;
    }

    if (_moveMode) {
      final selected = _selectedLandmark;
      if (selected == null) {
        setState(() {
          _message = 'Select a landmark first, then tap its new route position.';
        });
        return;
      }
      setState(() {
        _landmarks = _sortedLandmarks(
          _landmarks
              .map(
                (landmark) => landmark.id == selected.id
                    ? landmark.copyWith(position: projection.point)
                    : landmark,
              )
              .toList(growable: false),
        );
        _message =
            '${selected.name} moved to a new route position. Save to apply it.';
      });
      return;
    }

    final draft = await _showLandmarkDialog(
      title: 'Add route landmark',
      actionLabel: 'Add',
    );
    if (draft == null || !mounted) {
      return;
    }

    final landmark = _EditableRouteLandmark(
      id: 'new-${DateTime.now().microsecondsSinceEpoch}',
      name: draft.name,
      code: draft.code,
      fare: draft.fare,
      position: projection.point,
    );
    setState(() {
      _landmarks = _sortedLandmarks([..._landmarks, landmark]);
      _selectedLandmarkId = landmark.id;
      _message = '${landmark.name} added. Save to publish the landmark fares.';
    });
  }

  Future<void> _editLandmark(_EditableRouteLandmark landmark) async {
    final draft = await _showLandmarkDialog(
      title: 'Edit route landmark',
      actionLabel: 'Update',
      initialName: landmark.name,
      initialCode: landmark.code,
      initialFare: landmark.fare,
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() {
        _landmarks = _sortedLandmarks(
          _landmarks
              .map(
                (entry) => entry.id == landmark.id
                    ? _EditableRouteLandmark(
                        id: entry.id,
                        name: draft.name,
                        code: draft.code,
                        fare: draft.fare,
                        position: entry.position,
                      )
                    : entry,
              )
              .toList(growable: false),
      );
      _selectedLandmarkId = landmark.id;
      _message = '${draft.name} updated. Save to sync it for this route.';
    });
  }

  Future<void> _deleteLandmark(_EditableRouteLandmark landmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove landmark'),
        content: Text('Remove ${landmark.name} from ${widget.route.label}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _landmarks = _sortedLandmarks(
        _landmarks
            .where((entry) => entry.id != landmark.id)
            .toList(growable: false),
      );
      if (_selectedLandmarkId == landmark.id) {
        _selectedLandmarkId = _landmarks.isEmpty ? null : _landmarks.first.id;
      }
      _message = '${landmark.name} removed. Save to update the route.';
    });
  }

  Future<void> _saveLandmarks() async {
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final saved = await ActionFeedback.run<RouteSummaryModel>(
        context: context,
        loadingMessage: 'Saving route landmarks...',
        successMessage:
            'Landmarks for ${widget.route.code} were updated successfully.',
        action: () => routeService.updateRoute(
          widget.route.id,
          {'stops': _buildStopsPayload()},
        ),
        onError: (error) async {
          if (!mounted) return;
          setState(() => _message = ActionFeedback.messageOf(error));
        },
      );
      if (saved != null && mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  List<Map<String, dynamic>> _buildStopsPayload() {
    final ordered = _sortedLandmarks(_landmarks);
    return [
      for (var index = 0; index < ordered.length; index += 1)
        {
          'name': ordered[index].name,
          if ((ordered[index].code ?? '').trim().isNotEmpty)
            'code': ordered[index].code!.trim(),
          'order': index + 1,
          'fare': ordered[index].fare,
          'location': {
            'type': 'Point',
            'coordinates': <double>[
              ordered[index].position.longitude,
              ordered[index].position.latitude,
            ],
          },
        },
    ];
  }

  List<_EditableRouteLandmark> _sortedLandmarks(
    List<_EditableRouteLandmark> landmarks,
  ) {
    final sorted = [...landmarks];
    sorted.sort((left, right) {
      final leftProgress = _nearestRouteProjection(left.position)?.progress ??
          left.position.latitude + left.position.longitude;
      final rightProgress = _nearestRouteProjection(right.position)?.progress ??
          right.position.latitude + right.position.longitude;
      return leftProgress.compareTo(rightProgress);
    });
    return sorted;
  }

  _RouteProjection? _nearestRouteProjection(LatLng point) {
    final orderedPoints = _routePoints;
    if (orderedPoints.isEmpty) {
      return null;
    }
    if (orderedPoints.length == 1) {
      return _RouteProjection(
        point: orderedPoints.first,
        distanceMeters: _distance.as(
          LengthUnit.Meter,
          point,
          orderedPoints.first,
        ),
        progress: 0,
      );
    }

    _RouteProjection? nearestProjection;
    for (var index = 0; index < orderedPoints.length - 1; index += 1) {
      final candidate = _projectOntoSegment(
        point: point,
        start: orderedPoints[index],
        end: orderedPoints[index + 1],
      );
      final projection = _RouteProjection(
        point: candidate.point,
        distanceMeters: candidate.distanceMeters,
        progress: index + candidate.fraction,
      );
      if (nearestProjection == null ||
          projection.distanceMeters < nearestProjection.distanceMeters) {
        nearestProjection = projection;
      }
    }
    return nearestProjection;
  }

  _ProjectedPoint _projectOntoSegment({
    required LatLng point,
    required LatLng start,
    required LatLng end,
  }) {
    final originLat = (point.latitude + start.latitude + end.latitude) / 3;
    final originLng = (point.longitude + start.longitude + end.longitude) / 3;
    final localPoint = _toLocalMeters(
      point,
      originLat: originLat,
      originLng: originLng,
    );
    final localStart = _toLocalMeters(
      start,
      originLat: originLat,
      originLng: originLng,
    );
    final localEnd = _toLocalMeters(
      end,
      originLat: originLat,
      originLng: originLng,
    );
    final dx = localEnd.dx - localStart.dx;
    final dy = localEnd.dy - localStart.dy;
    final segmentLengthSquared = dx * dx + dy * dy;
    if (segmentLengthSquared <= 0) {
      return _ProjectedPoint(
        point: start,
        distanceMeters: _distance.as(LengthUnit.Meter, point, start),
        fraction: 0,
      );
    }

    final rawFraction = ((localPoint.dx - localStart.dx) * dx +
            (localPoint.dy - localStart.dy) * dy) /
        segmentLengthSquared;
    final fraction = rawFraction.clamp(0.0, 1.0).toDouble();
    final projectedLocal = Offset(
      localStart.dx + dx * fraction,
      localStart.dy + dy * fraction,
    );
    final projectedPoint = _fromLocalMeters(
      projectedLocal,
      originLat: originLat,
      originLng: originLng,
    );
    return _ProjectedPoint(
      point: projectedPoint,
      distanceMeters: _distance.as(LengthUnit.Meter, point, projectedPoint),
      fraction: fraction,
    );
  }

  Offset _toLocalMeters(
    LatLng point, {
    required double originLat,
    required double originLng,
  }) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        metersPerDegreeLat * math.cos(originLat * math.pi / 180);
    return Offset(
      (point.longitude - originLng) * metersPerDegreeLng,
      (point.latitude - originLat) * metersPerDegreeLat,
    );
  }

  LatLng _fromLocalMeters(
    Offset point, {
    required double originLat,
    required double originLng,
  }) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        metersPerDegreeLat * math.cos(originLat * math.pi / 180);
    return LatLng(
      originLat + point.dy / metersPerDegreeLat,
      originLng + point.dx / (metersPerDegreeLng == 0 ? 1 : metersPerDegreeLng),
    );
  }

  Future<_LandmarkDraft?> _showLandmarkDialog({
    required String title,
    required String actionLabel,
    String initialName = '',
    String? initialCode,
    double initialFare = 0,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: initialName);
    final codeCtrl = TextEditingController(text: initialCode ?? '');
    final fareCtrl = TextEditingController(
      text: initialFare == initialFare.truncateToDouble()
          ? initialFare.toStringAsFixed(0)
          : initialFare.toStringAsFixed(2),
    );

    try {
      return await showDialog<_LandmarkDraft>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Landmark name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if ((value?.trim() ?? '').isEmpty) {
                        return 'Landmark name is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Short code (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: fareCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Fare',
                      prefixText: 'PHP ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = double.tryParse((value ?? '').trim());
                      if (amount == null || amount < 0) {
                        return 'Enter a valid non-negative fare.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.of(context).pop(
                  _LandmarkDraft(
                    name: nameCtrl.text.trim(),
                    code: codeCtrl.text.trim().isEmpty
                        ? null
                        : codeCtrl.text.trim(),
                    fare: double.parse(fareCtrl.text.trim()),
                  ),
                );
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      );
    } finally {
      nameCtrl.dispose();
      codeCtrl.dispose();
      fareCtrl.dispose();
    }
  }

  String _formatCoordinate(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedLandmark = _selectedLandmark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Route Landmarks'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.route.label, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Route landmarks act as the admin-managed primary drop-off points. Only admins can add, move, edit, and update their fares.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _RouteMetaChip(
                        label: 'Status',
                        value: ParagoFormat.statusLabel(widget.route.status),
                      ),
                      _RouteMetaChip(
                        label: 'Landmarks',
                        value: _landmarks.length.toString(),
                      ),
                      _RouteMetaChip(
                        label: 'Geometry',
                        value: _routePoints.length >= 2
                            ? '${_routePoints.length} path pts'
                            : 'Limited',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Placement tools', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Add landmark'),
                        selected: !_moveMode,
                        onSelected: (_) {
                          setState(() {
                            _moveMode = false;
                            _message =
                                'Tap the route to add a new landmark and fare.';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Move selected'),
                        selected: _moveMode,
                        onSelected: (_) {
                          setState(() {
                            _moveMode = true;
                            _message = selectedLandmark == null
                                ? 'Select a landmark first, then tap its new route position.'
                                : 'Tap the route to move ${selectedLandmark.name}.';
                          });
                        },
                      ),
                      OutlinedButton.icon(
                        onPressed: selectedLandmark == null
                            ? null
                            : () => _editLandmark(selectedLandmark),
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        label: const Text('Edit selected'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F6A5F).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      selectedLandmark == null
                          ? 'No landmark selected yet.'
                          : 'Selected: ${selectedLandmark.name} | ${_formatFare(selectedLandmark.fare)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Route map', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the route line to add a landmark. In move mode, select a landmark first and tap a new spot on the route to reposition it.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (_saving) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 14),
                  ],
                  AspectRatio(
                    aspectRatio: 1.08,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _mapCenter,
                          initialZoom: _mapZoom,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                          onTap: (_, point) => _handleMapTap(point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.parago.mobile',
                          ),
                          if (_routePoints.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _routePoints,
                                  strokeWidth: 6,
                                  color: const Color(0xFF0F6A5F),
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              for (var index = 0;
                                  index < _landmarks.length;
                                  index += 1)
                                Marker(
                                  point: _landmarks[index].position,
                                  width: 168,
                                  height: 86,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedLandmarkId =
                                            _landmarks[index].id;
                                        _message =
                                            '${_landmarks[index].name} selected.';
                                      });
                                    },
                                    child: _LandmarkMarker(
                                      order: index + 1,
                                      name: _landmarks[index].name,
                                      fareLabel:
                                          _formatFare(_landmarks[index].fare),
                                      selected:
                                          _landmarks[index].id ==
                                              _selectedLandmarkId,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution('OpenStreetMap contributors'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Landmarks', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (_landmarks.isEmpty)
                    const Text(
                      'No drop-off landmarks yet. Tap the route map to add one.',
                    )
                  else
                    Column(
                      children: [
                        for (var index = 0; index < _landmarks.length; index += 1)
                          _LandmarkListTile(
                            order: index + 1,
                            landmark: _landmarks[index],
                            selected: _landmarks[index].id == _selectedLandmarkId,
                            coordinateLabel:
                                _formatCoordinate(_landmarks[index].position),
                            onTap: () {
                              setState(() {
                                _selectedLandmarkId = _landmarks[index].id;
                                _message =
                                    '${_landmarks[index].name} selected.';
                              });
                            },
                            onEdit: () => _editLandmark(_landmarks[index]),
                            onDelete: () => _deleteLandmark(_landmarks[index]),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF102725).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _saveLandmarks,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Landmark Updates'),
          ),
        ],
      ),
    );
  }
}

class _RouteMetaChip extends StatelessWidget {
  const _RouteMetaChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _LandmarkMarker extends StatelessWidget {
  const _LandmarkMarker({
    required this.order,
    required this.name,
    required this.fareLabel,
    required this.selected,
  });

  final int order;
  final String name;
  final String fareLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent =
        selected ? const Color(0xFF8A3B5D) : const Color(0xFF0F6A5F);
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent, width: selected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$order. $name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                fareLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandmarkListTile extends StatelessWidget {
  const _LandmarkListTile({
    required this.order,
    required this.landmark,
    required this.selected,
    required this.coordinateLabel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final int order;
  final _EditableRouteLandmark landmark;
  final bool selected;
  final String coordinateLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected
            ? const Color(0xFF0F6A5F).withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  child: Text('$order'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        landmark.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatFare(landmark.fare)} | $coordinateLabel',
                      ),
                      if ((landmark.code ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Code: ${landmark.code}'),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit landmark',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove landmark',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditableRouteLandmark {
  const _EditableRouteLandmark({
    required this.id,
    required this.name,
    required this.code,
    required this.fare,
    required this.position,
  });

  final String id;
  final String name;
  final String? code;
  final double fare;
  final LatLng position;

  _EditableRouteLandmark copyWith({
    String? name,
    String? code,
    double? fare,
    LatLng? position,
  }) {
    return _EditableRouteLandmark(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      fare: fare ?? this.fare,
      position: position ?? this.position,
    );
  }
}

class _LandmarkDraft {
  const _LandmarkDraft({
    required this.name,
    required this.code,
    required this.fare,
  });

  final String name;
  final String? code;
  final double fare;
}

class _RouteProjection {
  const _RouteProjection({
    required this.point,
    required this.distanceMeters,
    required this.progress,
  });

  final LatLng point;
  final double distanceMeters;
  final double progress;
}

class _ProjectedPoint {
  const _ProjectedPoint({
    required this.point,
    required this.distanceMeters,
    required this.fraction,
  });

  final LatLng point;
  final double distanceMeters;
  final double fraction;
}

String _formatFare(double value) {
  final decimals = value == value.truncateToDouble() ? 0 : 2;
  return 'PHP ${value.toStringAsFixed(decimals)}';
}
