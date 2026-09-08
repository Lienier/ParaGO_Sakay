import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/transport/route_summary.dart';
import '../../services/admin_service.dart';
import '../../services/route_preview_cache.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

enum _PinPlacementMode { start, end, guide }

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
  final RoutePreviewCache _routePreviewCache = RoutePreviewCache();

  List<RouteSummaryModel> _routes = [];
  LatLng? _startPoint;
  LatLng? _endPoint;
  List<LatLng> _guidePoints = [];
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
      final waypointPoints = route.waypointPoints;
      final hasDedicatedGuidePoints = waypointPoints.isNotEmpty &&
          !_pointsMatch(waypointPoints, previewPoints);
      _previewSnapshot = CachedRouteSnapshot(
        routeId: route.id,
        routeCode: route.code,
        points: previewPoints,
        startPoint: route.originPoint ?? previewPoints.first,
        endPoint: route.destinationPoint ?? previewPoints.last,
        bounds: route.mapBounds ?? RouteMapBounds.fromPoints(previewPoints),
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
        rawDurationSeconds: route.rawDurationSeconds ?? route.durationSeconds,
        trafficDelayInSeconds: route.trafficDelayInSeconds,
      );
      _startPoint = _previewSnapshot!.startPoint;
      _endPoint = _previewSnapshot!.endPoint;
      _guidePoints = hasDedicatedGuidePoints
          ? List<LatLng>.from(waypointPoints)
          : <LatLng>[];
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
      } else if (_placementMode == _PinPlacementMode.end) {
        _endPoint = point;
        _message =
            'End pin placed. Tap again to move it or build the live route.';
      } else {
        _guidePoints = [..._guidePoints, point];
        _message =
            'Branch guide point ${_guidePoints.length} added. The route will follow these points in order.';
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
        _message = 'Building a live TomTom route preview...';
      }
    });

    try {
      final session = context.read<SessionController>();
      final admin = AdminService(session.apiClient);
      final route = await admin.previewRoute(
        startPoint: (
          latitude: startPoint.latitude,
          longitude: startPoint.longitude,
        ),
        endPoint: (
          latitude: endPoint.latitude,
          longitude: endPoint.longitude,
        ),
        guidePoints: [
          for (final point in _guidePoints)
            (latitude: point.latitude, longitude: point.longitude),
        ],
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
          rawDurationSeconds: route.rawDurationSeconds ?? route.durationSeconds,
          trafficDelayInSeconds: route.trafficDelayInSeconds,
        );
        _message = autoTriggered
            ? 'Route refreshed from the selected pins and guide points.'
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
    final editingRoute = _editingRoute;

    setState(() {
      _savingRoute = true;
      _message = null;
    });

    try {
      final saved = await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Saving route geometry...',
        successMessage: editingRoute == null
            ? 'Route $_normalizedCode created with offline-ready geometry.'
            : 'Route $_normalizedCode updated with offline-ready geometry.',
        action: () async {
          final saved = editingRoute == null
              ? await routeService.createRoute(payload)
              : await routeService.updateRoute(editingRoute.id, payload);

          await _routePreviewCache.saveSnapshot(
            routeId: saved.id,
            routeCode: saved.code,
            points: _previewPoints,
            startPoint: _startPoint,
            endPoint: _endPoint,
            bounds: _previewBounds,
            distanceMeters: _previewSnapshot?.distanceMeters,
            durationSeconds: _previewSnapshot?.durationSeconds,
            rawDurationSeconds: _previewSnapshot?.rawDurationSeconds,
            trafficDelayInSeconds: _previewSnapshot?.trafficDelayInSeconds,
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
      _guidePoints = [];
      _previewSnapshot = null;
      _offlinePreview = false;
      _placementMode = _PinPlacementMode.start;
      _message = 'Pins cleared. Tap the map to place a new route.';
      _mapVersion += 1;
    });
  }

  Future<void> _clearGuidePoints() async {
    if (_guidePoints.isEmpty) {
      return;
    }
    setState(() {
      _guidePoints = [];
      _previewSnapshot = null;
      _offlinePreview = false;
      _message =
          'Branch guide points cleared. The live route will return to the direct road match.';
      _mapVersion += 1;
    });
    if (_startPoint != null && _endPoint != null) {
      await _buildLiveRoute(autoTriggered: true);
    }
  }

  Future<void> _removeGuidePoint(int index) async {
    if (index < 0 || index >= _guidePoints.length) {
      return;
    }
    setState(() {
      final updated = [..._guidePoints]..removeAt(index);
      _guidePoints = updated;
      _previewSnapshot = null;
      _offlinePreview = false;
      _message =
          'Branch guide point ${index + 1} removed. The live route is being refreshed.';
      _mapVersion += 1;
    });
    if (_startPoint != null && _endPoint != null) {
      await _buildLiveRoute(autoTriggered: true);
    }
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

  RouteSummaryModel? get _editingRoute => widget.initialRoute;

  RouteSummaryModel? get _resolvedExistingRoute {
    final editingRoute = _editingRoute;
    if (editingRoute != null) {
      return editingRoute;
    }
    return _existingRouteByCode(_normalizedCode);
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
    final points = <LatLng>[
      if (_startPoint != null) _startPoint!,
      ..._guidePoints,
      if (_endPoint != null) _endPoint!,
    ];
    final draftBounds = RouteMapBounds.fromPoints(points);
    if (draftBounds != null) {
      return draftBounds.center;
    }
    return _startPoint ?? _endPoint ?? _defaultCenter;
  }

  double get _mapZoom {
    final points = _previewPoints.isNotEmpty
        ? _previewPoints
        : <LatLng>[
            if (_startPoint != null) _startPoint!,
            ..._guidePoints,
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
        for (var index = 0; index < _guidePoints.length; index += 1)
          {
            'name': 'Guide point ${index + 1}',
            'location': {
              'type': 'Point',
              'coordinates': <double>[
                _guidePoints[index].longitude,
                _guidePoints[index].latitude,
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
        'source': 'tomtom',
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
        if (_previewSnapshot?.rawDurationSeconds != null)
          'rawDurationSeconds': _previewSnapshot!.rawDurationSeconds,
        if (_previewSnapshot?.trafficDelayInSeconds != null)
          'trafficDelayInSeconds': _previewSnapshot!.trafficDelayInSeconds,
      },
    };
  }

  String _formatCoordinate(LatLng? point) {
    if (point == null) return 'Not pinned yet';
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  bool _pointsMatch(List<LatLng> left, List<LatLng> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_samePoint(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _samePoint(LatLng left, LatLng right) {
    return (left.latitude - right.latitude).abs() < 0.000001 &&
        (left.longitude - right.longitude).abs() < 0.000001;
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
    if (MediaQuery.sizeOf(context).width < 720) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Use a tablet or desktop to edit route maps.')));
    }

    final theme = Theme.of(context);
    final existing = _resolvedExistingRoute;
    final isEditing = existing != null;

    final body = RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildRouteDetailsCard(theme, existing),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 1280;

              if (!sideBySide) {
                return Column(
                  children: [
                    _buildPinControlsCard(theme),
                    const SizedBox(height: 16),
                    _buildMapCard(theme, existing),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildPinControlsCard(theme),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _buildMapCard(theme, existing),
                  ),
                ],
              );
            },
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF102725).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
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
        title: Text(isEditing ? 'Update Route' : 'Build Route'),
      ),
      body: body,
    );
  }

  Widget _buildRouteDetailsCard(
    ThemeData theme,
    RouteSummaryModel? existing,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              existing == null ? 'Route details' : 'Update route details',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              existing == null
                  ? 'Pin the start and end points directly on OpenStreetMap, then save the exact same route geometry for online and offline use.'
                  : 'You are editing ${existing.label}. Adjust the pins, guide points, route details, or fare settings, then update the saved geometry.',
              style: theme.textTheme.bodyMedium,
            ),
            if (existing != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F6A5F).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Editing existing route: ${existing.label}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 780;
                final nameField = TextFormField(
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
                );
                final codeField = TextFormField(
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
                );

                if (!sideBySide) {
                  return Column(
                    children: [
                      nameField,
                      const SizedBox(height: 14),
                      codeField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: 12),
                    Expanded(child: codeField),
                  ],
                );
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
          ],
        ),
      ),
    );
  }

  Widget _buildPinControlsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final columns = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 760
                    ? 2
                    : 1;
            final baseWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

            double tileWidth(int span) {
              final safeSpan = span < columns ? span : columns;
              if (columns == 1) {
                return constraints.maxWidth;
              }
              return (baseWidth * safeSpan) + (spacing * (safeSpan - 1));
            }

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: tileWidth(columns),
                  child: _PinInfoTile(
                    title: 'Pin controls',
                    subtitle:
                        'Use start, end, and branch guide points to force the route down the exact road branch you want before saving.',
                  ),
                ),
                SizedBox(
                  width: tileWidth(1),
                  child: _PinActionTile(
                    title: 'Place Start Pin',
                    subtitle: 'Tap the map to place the start pin',
                    icon: Icons.flag_circle_outlined,
                    selected: _placementMode == _PinPlacementMode.start,
                    accent: const Color(0xFF0F6A5F),
                    onTap: () {
                      setState(() {
                        _placementMode = _PinPlacementMode.start;
                        _message =
                            'Tap the map to place or move the start pin.';
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth(1),
                  child: _PinActionTile(
                    title: 'Place End Pin',
                    subtitle: 'Tap the map to place the end pin',
                    icon: Icons.location_on_outlined,
                    selected: _placementMode == _PinPlacementMode.end,
                    accent: const Color(0xFF8A3B5D),
                    onTap: () {
                      setState(() {
                        _placementMode = _PinPlacementMode.end;
                        _message = 'Tap the map to place or move the end pin.';
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth(1),
                  child: _PinActionTile(
                    title: 'Add Branch Guide',
                    subtitle: 'Tap the map to add an ordered turn guide point',
                    icon: Icons.alt_route,
                    selected: _placementMode == _PinPlacementMode.guide,
                    accent: const Color(0xFF2157A5),
                    onTap: () {
                      setState(() {
                        _placementMode = _PinPlacementMode.guide;
                        _message =
                            'Tap the map to add branch guide points in the order the route should follow.';
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: tileWidth(1),
                  child: _PinActionTile(
                    title: 'Clear All',
                    subtitle: 'Clear pins, guide points, and preview route',
                    icon: Icons.restart_alt,
                    accent: const Color(0xFFE29B2D),
                    onTap: _clearPins,
                  ),
                ),
                SizedBox(
                  width: tileWidth(columns >= 4 ? 2 : 1),
                  child: _GuidePointsTile(
                    points: _guidePoints,
                    onClear: _guidePoints.isEmpty ? null : _clearGuidePoints,
                    onRemove: _removeGuidePoint,
                  ),
                ),
                SizedBox(
                  width: tileWidth(columns >= 4 ? 2 : 1),
                  child: _CoordinateRow(
                    label: 'Start',
                    value: _formatCoordinate(_startPoint),
                    icon: Icons.flag_circle_outlined,
                    accent: const Color(0xFF0F6A5F),
                    compact: true,
                  ),
                ),
                SizedBox(
                  width: tileWidth(columns >= 4 ? 2 : 1),
                  child: _CoordinateRow(
                    label: 'End',
                    value: _formatCoordinate(_endPoint),
                    icon: Icons.location_on_outlined,
                    accent: const Color(0xFF8A3B5D),
                    compact: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
                  : 'Tap the map to pin start/end. Add branch guide points anywhere the road splits so the live route follows the exact direction you want.',
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
                  borderRadius: BorderRadius.circular(8),
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
                  label: 'Branch guides',
                  value: _guidePoints.isEmpty
                      ? 'None'
                      : '${_guidePoints.length} selected',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            math.max(460.0, math.min(680.0, constraints.maxWidth * 0.48));

        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
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
                        if (_guidePoints.isNotEmpty)
                          CircleLayer(
                            circles: [
                              for (final point in _guidePoints)
                                CircleMarker(
                                  point: point,
                                  radius: 8,
                                  color: const Color(0xFF2157A5)
                                      .withValues(alpha: 0.20),
                                  borderStrokeWidth: 2,
                                  borderColor: const Color(0xFF2157A5),
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
                            for (var index = 0;
                                index < _guidePoints.length;
                                index += 1)
                              Marker(
                                point: _guidePoints[index],
                                width: 132,
                                height: 72,
                                child: _PinnedMarker(
                                  label: 'Guide ${index + 1}',
                                  accent: const Color(0xFF2157A5),
                                  icon: Icons.alt_route,
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
      },
    );
  }
}

class _PinInfoTile extends StatelessWidget {
  const _PinInfoTile({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PinActionTile extends StatelessWidget {
  const _PinActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(
                      Icons.check_circle,
                      color: accent,
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidePointsTile extends StatelessWidget {
  const _GuidePointsTile({
    required this.points,
    required this.onRemove,
    this.onClear,
  });

  final List<LatLng> points;
  final ValueChanged<int> onRemove;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Branch guides',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onClear != null)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            points.isEmpty
                ? 'No guide points yet. Add one when the road splits so the route follows the branch you want.'
                : 'Guide points are followed in order from start to end.',
            style: theme.textTheme.bodySmall,
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var index = 0; index < points.length; index += 1) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2157A5).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${points[index].latitude.toStringAsFixed(6)}, ${points[index].longitude.toStringAsFixed(6)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemove(index),
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Remove guide point',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              if (index < points.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
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
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 14,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
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
                SizedBox(height: compact ? 0 : 2),
                Text(
                  value,
                  maxLines: compact ? 1 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                ),
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
        borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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
