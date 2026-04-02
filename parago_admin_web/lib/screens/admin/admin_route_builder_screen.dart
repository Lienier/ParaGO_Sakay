import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/transport/route_summary.dart';
import '../../services/open_street_map_routing_service.dart';
import '../../services/route_preview_cache.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

enum _PinPlacementMode { start, end }

class AdminRouteBuilderScreen extends StatefulWidget {
  const AdminRouteBuilderScreen({
    super.key,
    this.embedded = false,
    this.onSaved,
    this.initialRoute,
  });

  final bool embedded;
  final VoidCallback? onSaved;
  final RouteSummaryModel? initialRoute;

  @override
  State<AdminRouteBuilderScreen> createState() =>
      _AdminRouteBuilderScreenState();
}

class _AdminRouteBuilderScreenState extends State<AdminRouteBuilderScreen> {
  static const _defaultCenter = LatLng(14.6091, 121.0223);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _fareBaseAmountCtrl = TextEditingController(text: '17');
  final _fareBaseDistanceCtrl = TextEditingController(text: '4');
  final _fareAdditionalPerKmCtrl = TextEditingController(text: '2');
  final OpenStreetMapRoutingService _routingService =
      OpenStreetMapRoutingService();
  final RoutePreviewCache _routePreviewCache = RoutePreviewCache();

  List<RouteSummaryModel> _routes = [];
  LatLng? _startPoint;
  LatLng? _endPoint;
  CachedRouteSnapshot? _previewSnapshot;
  _PinPlacementMode _placementMode = _PinPlacementMode.start;
  bool _offlinePreview = false;
  bool _loadingRoutes = false;
  bool _buildingRoute = false;
  bool _savingRoute = false;
  int _mapVersion = 0;
  int _buildRequestSerial = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _seedFromRoute(widget.initialRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descriptionCtrl.dispose();
    _fareBaseAmountCtrl.dispose();
    _fareBaseDistanceCtrl.dispose();
    _fareAdditionalPerKmCtrl.dispose();
    _routingService.dispose();
    super.dispose();
  }

  void _seedFromRoute(RouteSummaryModel? route) {
    if (route == null) {
      return;
    }
    _nameCtrl.text = route.name;
    _codeCtrl.text = route.code;
    _descriptionCtrl.text = route.description ?? '';
    _fareBaseAmountCtrl.text = _formatNumericInput(route.fareConfig.baseAmount);
    _fareBaseDistanceCtrl.text =
        _formatNumericInput(route.fareConfig.baseDistanceKm);
    _fareAdditionalPerKmCtrl.text =
        _formatNumericInput(route.fareConfig.additionalAmountPerKm);

    final previewPoints =
        route.pathPoints.length >= 2 ? route.pathPoints : route.mapPath;
    if (previewPoints.length >= 2) {
      _previewSnapshot = CachedRouteSnapshot(
        routeId: route.id,
        routeCode: route.code,
        points: previewPoints,
        startPoint: route.originPoint ?? previewPoints.first,
        endPoint: route.destinationPoint ?? previewPoints.last,
        bounds: route.mapBounds ?? RouteMapBounds.fromPoints(previewPoints),
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
      );
      _startPoint = _previewSnapshot!.startPoint;
      _endPoint = _previewSnapshot!.endPoint;
    }
  }

  Future<void> _loadRoutes() async {
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);

    setState(() {
      _loadingRoutes = true;
      _message = null;
    });

    try {
      final routes = await routeService.getRoutes(useCache: false);
      if (!mounted) return;
      setState(() => _routes = routes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingRoutes = false);
      }
    }
  }

  Future<void> _handleMapTap(LatLng point) async {
    _dismissKeyboard();
    setState(() {
      if (_placementMode == _PinPlacementMode.start) {
        _startPoint = point;
        _message =
            'Start pin placed. Tap again to move it or switch to End pin.';
      } else {
        _endPoint = point;
        _message =
            'End pin placed. Tap again to move it or build the live route.';
      }
      _previewSnapshot = null;
      _offlinePreview = false;
      _mapVersion += 1;
    });

    if (_startPoint != null && _endPoint != null) {
      await _buildLiveRoute(autoTriggered: true);
    }
  }

  Future<void> _buildLiveRoute({bool autoTriggered = false}) async {
    final startPoint = _startPoint;
    final endPoint = _endPoint;
    if (startPoint == null || endPoint == null) {
      setState(() {
        _message = 'Pin both the start and end locations on the map first.';
      });
      if (!autoTriggered && mounted) {
        await ActionFeedback.showInfoDialog(
          context,
          title: 'Pins required',
          message: 'Pin both the start and end locations on the map first.',
        );
      }
      return;
    }

    final requestId = ++_buildRequestSerial;
    setState(() {
      _buildingRoute = true;
      if (!autoTriggered) {
        _message = 'Building a live OpenStreetMap route...';
      }
    });

    try {
      final route = await _routingService.buildDrivingRoute(
        startPoint: startPoint,
        endPoint: endPoint,
      );

      if (!mounted || requestId != _buildRequestSerial) return;

      setState(() {
        _previewSnapshot = CachedRouteSnapshot(
          routeCode: _normalizedCode,
          points: route.points,
          startPoint: startPoint,
          endPoint: endPoint,
          bounds: route.bounds ?? RouteMapBounds.fromPoints(route.points),
          distanceMeters: route.distanceMeters,
          durationSeconds: route.durationSeconds,
        );
        _message = autoTriggered
            ? 'Route refreshed from the new pins.'
            : 'Live route ready. Save it to keep the same geometry online and offline.';
        _mapVersion += 1;
      });
      if (!autoTriggered && mounted) {
        await ActionFeedback.showSuccessDialog(
          context,
          title: 'Route ready',
          message:
              'Live route ready. Save it to keep the same geometry online and offline.',
        );
      }
    } catch (error) {
      if (!mounted || requestId != _buildRequestSerial) return;
      setState(() {
        _message = 'Unable to build a road-following route: $error';
      });
      if (!autoTriggered) {
        await ActionFeedback.showErrorDialog(
          context,
          title: 'Route build failed',
          message: ActionFeedback.messageOf(error),
        );
      }
    } finally {
      if (mounted && requestId == _buildRequestSerial) {
        setState(() => _buildingRoute = false);
      }
    }
  }

  Future<void> _saveRoute() async {
    if (_previewPoints.length < 2) {
      setState(() {
        _message =
            'Build the route first so the exact road geometry can be saved.';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    _dismissKeyboard();
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);
    final payload = _buildRoutePayload();
    final existing = _resolvedExistingRoute;

    setState(() {
      _savingRoute = true;
      _message = null;
    });

    try {
      final saved = await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Saving route geometry...',
        successMessage: existing == null
            ? 'Route $_normalizedCode created with offline-ready geometry.'
            : 'Route $_normalizedCode updated with offline-ready geometry.',
        action: () async {
          final saved = existing == null
              ? await routeService.createRoute(payload)
              : await routeService.updateRoute(existing.id, payload);

          await _routePreviewCache.saveSnapshot(
            routeId: saved.id,
            routeCode: saved.code,
            points: _previewPoints,
            startPoint: _startPoint,
            endPoint: _endPoint,
            bounds: _previewBounds,
            distanceMeters: _previewSnapshot?.distanceMeters,
            durationSeconds: _previewSnapshot?.durationSeconds,
          );
          return saved;
        },
        onError: (error) async {
          if (!mounted) return;
          setState(() => _message = ActionFeedback.messageOf(error));
        },
      );
      if (saved != null && mounted) {
        widget.onSaved?.call();
        if (widget.embedded) {
          await _loadRoutes();
          setState(() {
            _message =
                'Route saved. You can keep editing here or switch to the route management workspace.';
          });
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _savingRoute = false);
      }
    }
  }

  void _clearPins() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _previewSnapshot = null;
      _offlinePreview = false;
      _placementMode = _PinPlacementMode.start;
      _message = 'Pins cleared. Tap the map to place a new route.';
      _mapVersion += 1;
    });
  }

  void _clearPreviewOnly() {
    setState(() {
      _previewSnapshot = null;
      _offlinePreview = false;
      _message = 'Route preview cleared. Move a pin or build again.';
      _mapVersion += 1;
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  RouteSummaryModel? _existingRouteByCode(String code) {
    if (code.isEmpty) {
      return null;
    }
    for (final route in _routes) {
      if (route.code.toLowerCase() == code.toLowerCase()) {
        return route;
      }
    }
    return null;
  }

  RouteSummaryModel? get _resolvedExistingRoute {
    final normalizedCode = _normalizedCode;
    final initialRoute = widget.initialRoute;
    if (initialRoute != null &&
        normalizedCode.isNotEmpty &&
        initialRoute.code.toLowerCase() == normalizedCode.toLowerCase()) {
      return initialRoute;
    }
    return _existingRouteByCode(normalizedCode);
  }

  String get _normalizedCode => _codeCtrl.text.trim().toUpperCase();

  List<LatLng> get _previewPoints =>
      _previewSnapshot?.points ?? const <LatLng>[];

  RouteMapBounds? get _previewBounds =>
      _previewSnapshot?.bounds ?? RouteMapBounds.fromPoints(_previewPoints);

  double _parseFareInput(TextEditingController controller, double fallback) {
    return double.tryParse(controller.text.trim()) ?? fallback;
  }

  String _formatNumericInput(double value) {
    return value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  String _fareRuleSummary() {
    final baseAmount = _parseFareInput(_fareBaseAmountCtrl, 17);
    final baseDistanceKm = _parseFareInput(_fareBaseDistanceCtrl, 4);
    final additionalAmount = _parseFareInput(_fareAdditionalPerKmCtrl, 2);
    return 'First ${_formatNumericInput(baseDistanceKm)} km = PHP ${_formatNumericInput(baseAmount)}, then PHP ${_formatNumericInput(additionalAmount)} per succeeding kilometer.';
  }

  LatLng get _mapCenter {
    final bounds = _previewBounds;
    if (bounds != null) {
      return bounds.center;
    }
    if (_startPoint != null && _endPoint != null) {
      return LatLng(
        (_startPoint!.latitude + _endPoint!.latitude) / 2,
        (_startPoint!.longitude + _endPoint!.longitude) / 2,
      );
    }
    return _startPoint ?? _endPoint ?? _defaultCenter;
  }

  double get _mapZoom {
    final points = _previewPoints.isNotEmpty
        ? _previewPoints
        : <LatLng>[
            if (_startPoint != null) _startPoint!,
            if (_endPoint != null) _endPoint!,
          ];
    if (points.isEmpty) return 13.2;
    if (points.length == 1) return 15.6;

    final bounds = RouteMapBounds.fromPoints(points);
    if (bounds == null) return 13.2;
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

  Map<String, dynamic> _buildRoutePayload() {
    final existing = _resolvedExistingRoute;
    final pathCoordinates = _previewPoints
        .map((point) => <double>[point.longitude, point.latitude])
        .toList(growable: false);
    final startPoint = _startPoint!;
    final endPoint = _endPoint!;

    return {
      'name': _nameCtrl.text.trim(),
      'code': _normalizedCode,
      'direction': existing?.direction ?? 'circular',
      'status': existing?.status ?? 'active',
      'description': _descriptionCtrl.text.trim(),
      'path': {
        'type': 'LineString',
        'coordinates': pathCoordinates,
      },
      'waypoints': [
        for (var index = 0; index < _previewPoints.length; index += 1)
          {
            'name': index == 0
                ? 'Start pin'
                : index == _previewPoints.length - 1
                    ? 'End pin'
                    : 'Geometry point ${index + 1}',
            'location': {
              'type': 'Point',
              'coordinates': <double>[
                _previewPoints[index].longitude,
                _previewPoints[index].latitude,
              ],
            },
          },
      ],
      'stops': [
        for (final stop in existing?.stopPoints ?? const <RouteStopPoint>[])
          {
            'name': stop.name,
            if (stop.code != null && stop.code!.trim().isNotEmpty)
              'code': stop.code,
            'order': stop.order,
            'fare': stop.fare,
            'location': {
              'type': 'Point',
              'coordinates': <double>[
                stop.position.longitude,
                stop.position.latitude,
              ],
            },
          },
      ],
      'fareConfig': {
        'baseAmount': _parseFareInput(_fareBaseAmountCtrl, 17),
        'baseDistanceKm': _parseFareInput(_fareBaseDistanceCtrl, 4),
        'additionalAmountPerKm': _parseFareInput(_fareAdditionalPerKmCtrl, 2),
      },
      'navigation': {
        'source': 'openstreetmap',
        'origin': {
          'type': 'Point',
          'coordinates': <double>[
            startPoint.longitude,
            startPoint.latitude,
          ],
        },
        'destination': {
          'type': 'Point',
          'coordinates': <double>[
            endPoint.longitude,
            endPoint.latitude,
          ],
        },
        if (_previewBounds != null) 'bounds': _previewBounds!.toJson(),
        if (_previewSnapshot?.distanceMeters != null)
          'distanceMeters': _previewSnapshot!.distanceMeters,
        if (_previewSnapshot?.durationSeconds != null)
          'durationSeconds': _previewSnapshot!.durationSeconds,
      },
    };
  }

  String _formatCoordinate(LatLng? point) {
    if (point == null) return 'Not pinned yet';
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  String _formatDistance(double? meters) {
    if (meters == null) return 'Waiting for route';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return 'Waiting for route';
    final minutes = seconds / 60;
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = (minutes % 60).round();
    return '${hours}h ${remainingMinutes}m';
  }

  String? _validateNonNegativeNumber(String? value, String label) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) {
      return '$label must be a valid number.';
    }
    if (parsed < 0) {
      return '$label must be 0 or higher.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = _resolvedExistingRoute;

    final body = RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (widget.embedded) ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _loadingRoutes ? null : _loadRoutes,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh routes'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Form(
            key: _formKey,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Route details', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Pin the start and end points directly on OpenStreetMap, then save the exact same route geometry for online and offline use.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Route name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Route name is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Route code',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Route code is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descriptionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Fare settings',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These values drive the passenger fare preview and backend fare computation for this route.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 780;
                        final fields = [
                          TextFormField(
                            controller: _fareBaseAmountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Base fare',
                              prefixText: 'PHP ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => _validateNonNegativeNumber(
                              value,
                              'Base fare',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            controller: _fareBaseDistanceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Base distance',
                              suffixText: 'km',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => _validateNonNegativeNumber(
                              value,
                              'Base distance',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            controller: _fareAdditionalPerKmCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Additional per km',
                              prefixText: 'PHP ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => _validateNonNegativeNumber(
                              value,
                              'Additional fare',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ];

                        if (stacked) {
                          return Column(
                            children: [
                              for (var index = 0;
                                  index < fields.length;
                                  index += 1) ...[
                                fields[index],
                                if (index < fields.length - 1)
                                  const SizedBox(height: 12),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            for (var index = 0;
                                index < fields.length;
                                index += 1) ...[
                              Expanded(child: fields[index]),
                              if (index < fields.length - 1)
                                const SizedBox(width: 12),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF102725).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _fareRuleSummary(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: existing == null
                            ? const Color(0xFF0F6A5F).withValues(alpha: 0.08)
                            : const Color(0xFFE29B2D).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        existing == null
                            ? 'Saving will create a new route.'
                            : 'Route code already exists. Saving will update ${existing.label}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
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
                  Text('Pin controls', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('Place Start Pin'),
                        selected: _placementMode == _PinPlacementMode.start,
                        onSelected: (_) {
                          setState(() {
                            _placementMode = _PinPlacementMode.start;
                            _message =
                                'Tap the map to place or move the start pin.';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Place End Pin'),
                        selected: _placementMode == _PinPlacementMode.end,
                        onSelected: (_) {
                          setState(() {
                            _placementMode = _PinPlacementMode.end;
                            _message =
                                'Tap the map to place or move the end pin.';
                          });
                        },
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearPreviewOnly,
                        icon: const Icon(Icons.layers_clear_outlined),
                        label: const Text('Clear Route Only'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearPins,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset All Pins'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _CoordinateRow(
                    label: 'Start',
                    value: _formatCoordinate(_startPoint),
                    icon: Icons.flag_circle_outlined,
                    accent: const Color(0xFF0F6A5F),
                  ),
                  const SizedBox(height: 10),
                  _CoordinateRow(
                    label: 'End',
                    value: _formatCoordinate(_endPoint),
                    icon: Icons.location_on_outlined,
                    accent: const Color(0xFF8A3B5D),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildMapCard(theme, existing),
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
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Build Route'),
      ),
      body: body,
    );
  }

  Widget _buildMapCard(ThemeData theme, RouteSummaryModel? existing) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'OpenStreetMap route canvas',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Online'),
                  selected: !_offlinePreview,
                  onSelected: (_) {
                    setState(() {
                      _offlinePreview = false;
                      _mapVersion += 1;
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Offline parity'),
                  selected: _offlinePreview,
                  onSelected: _previewPoints.length >= 2
                      ? (_) {
                          setState(() {
                            _offlinePreview = true;
                            _mapVersion += 1;
                          });
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _offlinePreview
                  ? 'Offline parity view hides the live base tiles and renders the exact saved route geometry on the same bounds.'
                  : 'Tap the map to pin start/end. When both pins exist, the route is refreshed against the road network.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_loadingRoutes || _buildingRoute || _savingRoute) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 14),
            ],
            if (_savingRoute) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F6A5F).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Saving route geometry and offline snapshot...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            _buildMapCanvas(theme),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetaPill(
                  label: 'Distance',
                  value: _formatDistance(_previewSnapshot?.distanceMeters),
                ),
                _MetaPill(
                  label: 'ETA',
                  value: _formatDuration(_previewSnapshot?.durationSeconds),
                ),
                _MetaPill(
                  label: 'Geometry',
                  value: _previewPoints.isEmpty
                      ? 'No route yet'
                      : '${_previewPoints.length} points',
                ),
                _MetaPill(
                  label: 'Offline ready',
                  value: _previewPoints.length >= 2 ? 'Yes' : 'No',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _buildingRoute ? null : () => _buildLiveRoute(),
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Refresh Live Route'),
                ),
                FilledButton.icon(
                  onPressed: _savingRoute ? null : _saveRoute,
                  icon: _savingRoute
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _savingRoute
                        ? 'Saving...'
                        : existing == null
                            ? 'Save Route'
                            : 'Update Route',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapCanvas(ThemeData theme) {
    return AspectRatio(
      aspectRatio: 1.05,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _offlinePreview
                        ? [
                            const Color(0xFFF2F0E8),
                            const Color(0xFFE5E2D6),
                          ]
                        : [
                            const Color(0xFFE6F0ED),
                            const Color(0xFFD3E2E0),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: FlutterMap(
                  key: ValueKey(
                    'route-builder-map:$_mapVersion:${_offlinePreview ? 'offline' : 'online'}',
                  ),
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: _mapZoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onTap: (_, point) => _handleMapTap(point),
                  ),
                  children: [
                    if (!_offlinePreview)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.parago.mobile',
                      ),
                    if (_previewPoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _previewPoints,
                            strokeWidth: 6,
                            color: const Color(0xFF0F6A5F),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_startPoint != null)
                          Marker(
                            point: _startPoint!,
                            width: 140,
                            height: 78,
                            child: const _PinnedMarker(
                              label: 'Start',
                              accent: Color(0xFF0F6A5F),
                              icon: Icons.trip_origin,
                            ),
                          ),
                        if (_endPoint != null)
                          Marker(
                            point: _endPoint!,
                            width: 140,
                            height: 78,
                            child: const _PinnedMarker(
                              label: 'End',
                              accent: Color(0xFF8A3B5D),
                              icon: Icons.place,
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
            Positioned(
              left: 14,
              top: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    _offlinePreview
                        ? 'Offline parity view'
                        : 'Live OpenStreetMap view',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateRow extends StatelessWidget {
  const _CoordinateRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
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

class _PinnedMarker extends StatelessWidget {
  const _PinnedMarker({
    required this.label,
    required this.accent,
    required this.icon,
  });

  final String label;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
