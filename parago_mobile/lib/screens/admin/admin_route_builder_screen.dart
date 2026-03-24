import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../models/transport/route_summary.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

class AdminRouteBuilderScreen extends StatefulWidget {
  const AdminRouteBuilderScreen({super.key});

  @override
  State<AdminRouteBuilderScreen> createState() => _AdminRouteBuilderScreenState();
}

class _AdminRouteBuilderScreenState extends State<AdminRouteBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mapsUrlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _viaCtrl = TextEditingController();
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.openrouteservice.org',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  List<RouteSummaryModel> _routes = [];
  List<_RoutePreviewSegment> _previewSegments =
      const <_RoutePreviewSegment>[];
  String _direction = 'down';
  bool _loadingRoutes = false;
  bool _building = false;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  @override
  void dispose() {
    _mapsUrlCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descriptionCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _viaCtrl.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);
    setState(() => _loadingRoutes = true);
    try {
      final routes = await routeService.getRoutes();
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

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _importGoogleDirections() {
    final url = _mapsUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _message = 'Paste a Google Maps directions URL first.');
      return;
    }

    final startMatch = RegExp(r'/dir/(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)')
        .firstMatch(url);
    final pathCoordinates = RegExp(r'!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)')
        .allMatches(url)
        .map((match) => '${match.group(2)},${match.group(1)}')
        .toList(growable: false);

    if (startMatch == null || pathCoordinates.isEmpty) {
      setState(() {
        _message =
            'Could not extract route points from that Google Maps directions URL.';
      });
      return;
    }

    final start = '${startMatch.group(1)},${startMatch.group(2)}';
    final end = pathCoordinates.last;
    final vias = pathCoordinates.take(pathCoordinates.length - 1).join('\n');

    setState(() {
      _startCtrl.text = start;
      _endCtrl.text = end;
      _viaCtrl.text = vias;
      _message = 'Google Maps points imported. Generate a preview next.';
    });
  }

  Future<void> _buildPreview() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _dismissKeyboard();
    if (AppConfig.openRouteServiceApiKey.isEmpty) {
      setState(() {
        _message =
            'OpenRouteService key missing. Add ORS_API_KEY to parago_mobile/.env.';
      });
      return;
    }

    final start = _parseLatLng(_startCtrl.text, 'Start');
    final end = _parseLatLng(_endCtrl.text, 'End');
    final viaPoints = _parseViaLines(_viaCtrl.text);
    if (start == null || end == null) {
      return;
    }

    setState(() {
      _building = true;
      _message = null;
      _previewSegments = const <_RoutePreviewSegment>[];
    });

    try {
      final routePoints = <LatLng>[start, ...viaPoints, end];
      final segments = <_RoutePreviewSegment>[];

      for (var index = 0; index < routePoints.length - 1; index += 1) {
        final options = await _fetchPairOptions(
          start: routePoints[index],
          end: routePoints[index + 1],
        );
        segments.add(
          _RoutePreviewSegment(
            label: routePoints.length > 2 ? 'Section ${index + 1}' : 'Route',
            options: options,
          ),
        );
      }

      setState(() {
        _previewSegments = segments;
        _message = _hasAnyBranches
            ? 'Preview ready. Choose a branch for each section, then save.'
            : routePoints.length > 2
                ? 'Preview ready. These checkpoints only produced one road-snapped branch per section.'
                : 'Preview ready. Save route when it matches the road.';
      });
    } on DioException catch (error) {
      setState(() {
        _message = 'Failed to build route preview: ${_describeRouteBuildError(error)}';
      });
    } catch (error) {
      setState(() => _message = 'Failed to build route preview: $error');
    } finally {
      if (mounted) {
        setState(() => _building = false);
      }
    }
  }

  Future<List<_RoutePreviewOption>> _fetchPairOptions({
    required LatLng start,
    required LatLng end,
  }) async {
    try {
      final response = await _requestPreview(
        coordinates: [
          [start.longitude, start.latitude],
          [end.longitude, end.latitude],
        ],
        allowAlternatives: true,
      );
      return _decodePreviewOptions(response.data);
    } on DioException {
      final fallback = await _requestPreview(
        coordinates: [
          [start.longitude, start.latitude],
          [end.longitude, end.latitude],
        ],
        allowAlternatives: false,
      );
      final options = _decodePreviewOptions(fallback.data);
      if (options.isNotEmpty) {
        return options;
      }
      rethrow;
    }
  }

  Future<Response<Map<String, dynamic>>> _requestPreview({
    required List<List<double>> coordinates,
    required bool allowAlternatives,
  }) {
    return _dio.post<Map<String, dynamic>>(
      '/v2/directions/driving-car/geojson',
      options: Options(
        headers: {'Authorization': AppConfig.openRouteServiceApiKey},
      ),
      data: {
        'coordinates': coordinates,
        if (allowAlternatives)
          'alternative_routes': {
            'target_count': 3,
            'share_factor': 0.6,
            'weight_factor': 1.6,
          },
        'instructions': false,
      },
    );
  }

  List<_RoutePreviewOption> _decodePreviewOptions(Map<String, dynamic>? data) {
    final features = data?['features'];
    if (features is! List || features.isEmpty) {
      throw Exception('No route returned by OpenRouteService.');
    }

    final options = <_RoutePreviewOption>[];
    for (final feature in features) {
      if (feature is! Map) {
        continue;
      }
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      final points = _decodeGeoJsonCoordinates(
        geometry is Map ? geometry['coordinates'] : null,
      );
      if (points.isEmpty) {
        continue;
      }

      final summary = properties is Map ? properties['summary'] : null;
      final distanceKm = summary is Map && summary['distance'] is num
          ? (summary['distance'] as num).toDouble() / 1000
          : null;
      final durationMinutes = summary is Map && summary['duration'] is num
          ? (summary['duration'] as num).toDouble() / 60
          : null;
      options.add(
        _RoutePreviewOption(
          label: 'Route ${options.length + 1}',
          points: points,
          distanceKm: distanceKm,
          durationMinutes: durationMinutes,
        ),
      );
    }

    if (options.isEmpty) {
      throw Exception('Route geometry could not be decoded.');
    }
    return options;
  }

  String _describeRouteBuildError(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map) {
      final nestedError = data['error'];
      if (nestedError is Map && nestedError['message'] != null) {
        return nestedError['message'].toString();
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    if (response?.statusCode != null) {
      return 'OpenRouteService returned HTTP ${response!.statusCode}.';
    }
    return error.message ?? error.toString();
  }

  Future<void> _saveRoute() async {
    if (_selectedPreview.points.length < 2) {
      setState(() => _message = 'Generate a route preview before saving.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    _dismissKeyboard();
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);
    final payload = _buildRoutePayload();
    final existing = _existingRouteByCode(_codeCtrl.text.trim());

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final saved = existing == null
          ? await routeService.createRoute(payload)
          : await routeService.updateRoute(existing.id, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Route ${saved.code} created.'
                : 'Route ${saved.code} updated.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  RouteSummaryModel? _existingRouteByCode(String code) {
    for (final route in _routes) {
      if (route.code.toLowerCase() == code.toLowerCase()) {
        return route;
      }
    }
    return null;
  }

  Map<String, dynamic> _buildRoutePayload() {
    final coordinates = _selectedPreview.points
        .map((point) => [point.longitude, point.latitude])
        .toList(growable: false);
    final sampled = _sampleRoutePoints(coordinates);

    return {
      'name': _nameCtrl.text.trim(),
      'code': _codeCtrl.text.trim().toUpperCase(),
      'direction': _direction,
      'status': 'active',
      'description': _descriptionCtrl.text.trim(),
      'path': {
        'type': 'LineString',
        'coordinates': coordinates,
      },
      'waypoints': [
        for (var index = 0; index < sampled.length; index += 1)
          {
            'name': 'Waypoint ${index + 1}',
            'location': {
              'type': 'Point',
              'coordinates': sampled[index],
            },
          },
      ],
      'stops': const <Map<String, dynamic>>[],
    };
  }

  List<List<double>> _sampleRoutePoints(
    List<List<double>> coordinates, {
    int targetCount = 24,
  }) {
    if (coordinates.length <= targetCount) {
      return coordinates;
    }

    final step = math.max(1, coordinates.length ~/ targetCount);
    final sampled = <List<double>>[];
    for (var index = 0; index < coordinates.length; index += step) {
      sampled.add(coordinates[index]);
    }

    final last = coordinates.last;
    if (sampled.isEmpty ||
        sampled.last[0] != last[0] ||
        sampled.last[1] != last[1]) {
      sampled.add(last);
    }
    return sampled;
  }

  LatLng? _parseLatLng(String raw, String label) {
    final point = _tryParseLatLng(raw);
    if (point != null) {
      return point;
    }
    setState(() => _message = '$label must be formatted as "lat,lng".');
    return null;
  }

  LatLng? _tryParseLatLng(String raw) {
    final parts = raw
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 2) {
      return null;
    }

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  List<LatLng> _parseViaLines(String raw) {
    final points = <LatLng>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final point = _parseLatLng(trimmed, 'Via point');
      if (point != null) {
        points.add(point);
      }
    }
    return points;
  }

  List<LatLng> _decodeGeoJsonCoordinates(dynamic coordinates) {
    if (coordinates is! List) {
      return const <LatLng>[];
    }
    final points = <LatLng>[];
    for (final entry in coordinates) {
      if (entry is List && entry.length >= 2) {
        final lng = double.tryParse(entry[0].toString());
        final lat = double.tryParse(entry[1].toString());
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
    }
    return points;
  }

  _RoutePreviewOption get _selectedPreview {
    if (_previewSegments.isEmpty) {
      return _RoutePreviewOption.empty;
    }
    final points = <LatLng>[];
    var totalDistanceKm = 0.0;
    var totalDurationMinutes = 0.0;
    var hasDistance = false;
    var hasDuration = false;

    for (final segment in _previewSegments) {
      final selected = segment.selectedOption;
      if (selected.points.isEmpty) {
        continue;
      }
      if (points.isEmpty) {
        points.addAll(selected.points);
      } else {
        points.addAll(selected.points.skip(1));
      }
      if (selected.distanceKm != null) {
        totalDistanceKm += selected.distanceKm!;
        hasDistance = true;
      }
      if (selected.durationMinutes != null) {
        totalDurationMinutes += selected.durationMinutes!;
        hasDuration = true;
      }
    }

    return _RoutePreviewOption(
      label: _previewSegments.length > 1 ? 'Selected route' : 'Route',
      points: points,
      distanceKm: hasDistance ? totalDistanceKm : null,
      durationMinutes: hasDuration ? totalDurationMinutes : null,
    );
  }

  bool get _hasAnyBranches =>
      _previewSegments.any((segment) => segment.options.length > 1);

  double? get _distanceKm => _selectedPreview.distanceKm;

  double? get _durationMinutes => _selectedPreview.durationMinutes;

  Future<void> _openFullScreenPreview() async {
    if (_previewSegments.isEmpty) {
      return;
    }

    final selectedIndexes = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute<List<int>>(
        builder: (_) => _RoutePreviewMapScreen(
          previewSegments: _previewSegments,
          startPoint: _tryParseLatLng(_startCtrl.text),
          endPoint: _tryParseLatLng(_endCtrl.text),
        ),
      ),
    );

    if (selectedIndexes == null || !mounted) {
      return;
    }

    setState(() {
      _previewSegments = _applySelectedIndexes(
        _previewSegments,
        selectedIndexes,
      );
    });
  }

  Future<void> _openBranchSheet() async {
    if (_previewSegments.isEmpty) {
      return;
    }

    final selectedIndexes = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RouteBranchSheet(
        title: _hasAnyBranches ? 'Choose branches' : 'Selected sections',
        segments: _previewSegments,
      ),
    );

    if (selectedIndexes == null || !mounted) {
      return;
    }

    setState(() {
      _previewSegments = _applySelectedIndexes(
        _previewSegments,
        selectedIndexes,
      );
    });
  }

  List<_RoutePreviewSegment> _applySelectedIndexes(
    List<_RoutePreviewSegment> segments,
    List<int> selectedIndexes,
  ) {
    final updated = <_RoutePreviewSegment>[];
    for (var index = 0; index < segments.length; index += 1) {
      final selection = index < selectedIndexes.length ? selectedIndexes[index] : 0;
      updated.add(segments[index].copyWith(selectedIndex: selection));
    }
    return updated;
  }

  String? _requiredText(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPreview = _selectedPreview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Builder'),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic Jeepney Route',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Paste a Google Maps directions link or enter start, end, and optional via checkpoints. OpenRouteService will snap the line to roads, then you can save it directly as a permanent route.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mapsUrlCtrl,
                      minLines: 2,
                      maxLines: 3,
                      onTapOutside: (_) => _dismissKeyboard(),
                      decoration: const InputDecoration(
                        labelText: 'Google Maps directions URL',
                        hintText: 'Paste a Google Maps directions link here',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _building || _saving ? null : _importGoogleDirections,
                      icon: const Icon(Icons.link_outlined),
                      label: const Text('Import points from Google Maps'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Form(
              key: _formKey,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Route details',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameCtrl,
                        onTapOutside: (_) => _dismissKeyboard(),
                        validator: (value) => _requiredText(value, 'Route name'),
                        decoration: const InputDecoration(labelText: 'Route name'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _codeCtrl,
                        onTapOutside: (_) => _dismissKeyboard(),
                        validator: (value) => _requiredText(value, 'Route code'),
                        decoration: const InputDecoration(labelText: 'Route code'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _direction,
                        items: const [
                          DropdownMenuItem(value: 'up', child: Text('Up')),
                          DropdownMenuItem(value: 'down', child: Text('Down')),
                          DropdownMenuItem(
                            value: 'circular',
                            child: Text('Circular'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _direction = value ?? 'down'),
                        decoration: const InputDecoration(labelText: 'Direction'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionCtrl,
                        onTapOutside: (_) => _dismissKeyboard(),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Coordinates',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _startCtrl,
                        onTapOutside: (_) => _dismissKeyboard(),
                        validator: (value) =>
                            _requiredText(value, 'Start coordinate'),
                        decoration: const InputDecoration(
                          labelText: 'Start (lat,lng)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _endCtrl,
                        onTapOutside: (_) => _dismissKeyboard(),
                        validator: (value) =>
                            _requiredText(value, 'End coordinate'),
                        decoration: const InputDecoration(
                          labelText: 'End (lat,lng)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _viaCtrl,
                        minLines: 3,
                        maxLines: 6,
                        onTapOutside: (_) => _dismissKeyboard(),
                        decoration: const InputDecoration(
                          labelText: 'Via points',
                          hintText: 'One lat,lng pair per line',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _building || _saving ? null : _buildPreview,
                            icon: _building
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.alt_route),
                            label: const Text('Generate preview'),
                          ),
                          OutlinedButton.icon(
                            onPressed: selectedPreview.points.length < 2 || _saving
                                ? null
                                : _saveRoute,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _existingRouteByCode(_codeCtrl.text.trim()) == null
                                  ? 'Save route'
                                  : 'Update route',
                            ),
                          ),
                        ],
                      ),
                      if (_loadingRoutes) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preview', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (selectedPreview.distanceKm != null ||
                        selectedPreview.durationMinutes != null)
                      Text(
                        'Distance: ${_distanceKm?.toStringAsFixed(1) ?? '--'} km · ETA: ${_durationMinutes?.toStringAsFixed(0) ?? '--'} min',
                      ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasAnyBranches
                              ? 'Open the map full screen to compare each branch section.'
                              : 'Open the map full screen for a closer preview.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _previewSegments.isEmpty
                                  ? null
                                  : _openFullScreenPreview,
                              icon: const Icon(Icons.fullscreen),
                              label: const Text('Full screen'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _previewSegments.isEmpty ? null : _openBranchSheet,
                              icon: const Icon(Icons.tune),
                              label: const Text('Branches'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 260,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _RoutePreviewMap(
                          previewSegments: _previewSegments,
                          startPoint: _tryParseLatLng(_startCtrl.text),
                          endPoint: _tryParseLatLng(_endCtrl.text),
                        ),
                      ),
                    ),
                    if (_previewSegments.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _hasAnyBranches
                            ? 'Use Branches to drag up the section chooser.'
                            : 'Use Branches to review the selected sections.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _RoutePreviewMap extends StatelessWidget {
  const _RoutePreviewMap({
    required this.previewSegments,
    required this.startPoint,
    required this.endPoint,
  });

  final List<_RoutePreviewSegment> previewSegments;
  final LatLng? startPoint;
  final LatLng? endPoint;

  LatLng get _mapCenter {
    final selectedPoints = _selectedRoute.points;
    if (selectedPoints.isEmpty) {
      return const LatLng(14.8258, 121.0621);
    }
    return selectedPoints[selectedPoints.length ~/ 2];
  }

  _RoutePreviewOption get _selectedRoute {
    if (previewSegments.isEmpty) {
      return _RoutePreviewOption.empty;
    }
    final points = <LatLng>[];
    for (final segment in previewSegments) {
      final selected = segment.selectedOption;
      if (points.isEmpty) {
        points.addAll(selected.points);
      } else {
        points.addAll(selected.points.skip(1));
      }
    }
    return _RoutePreviewOption(
      label: 'Selected route',
      points: points,
      distanceKm: null,
      durationMinutes: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = _selectedRoute;

    return FlutterMap(
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: selectedRoute.points.length >= 2 ? 12.8 : 11,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.parago.mobile',
        ),
        if (previewSegments.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final segment in previewSegments)
                for (var index = 0; index < segment.options.length; index += 1)
                  Polyline(
                    points: segment.options[index].points,
                    strokeWidth: index == segment.selectedIndex ? 4 : 2.5,
                    color: index == segment.selectedIndex
                        ? const Color(0xFF2A9D8F)
                        : const Color(0x997FB7AE),
                  ),
              if (selectedRoute.points.length >= 2)
                Polyline(
                  points: selectedRoute.points,
                  strokeWidth: 5,
                  color: const Color(0xFF0F6A5F),
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            _routeMarker(startPoint, const Color(0xFF1F8FD5)),
            _routeMarker(endPoint, const Color(0xFFCC4B7A)),
          ].whereType<Marker>().toList(growable: false),
        ),
        RichAttributionWidget(
          attributions: const [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _RouteSegmentSelector extends StatelessWidget {
  const _RouteSegmentSelector({
    required this.segment,
    required this.onSelected,
  });

  final _RoutePreviewSegment segment;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          segment.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (segment.options.length == 1)
          Text(
            '${segment.selectedOption.summaryLabel} (only branch found)',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < segment.options.length; index += 1)
                ChoiceChip(
                  label: Text(segment.options[index].summaryLabel),
                  selected: index == segment.selectedIndex,
                  onSelected: (_) => onSelected(index),
                ),
            ],
          ),
      ],
    );
  }
}

class _RouteBranchSheet extends StatefulWidget {
  const _RouteBranchSheet({
    required this.title,
    required this.segments,
  });

  final String title;
  final List<_RoutePreviewSegment> segments;

  @override
  State<_RouteBranchSheet> createState() => _RouteBranchSheetState();
}

class _RouteBranchSheetState extends State<_RouteBranchSheet> {
  late List<_RoutePreviewSegment> _segments = [
    for (final segment in widget.segments) segment,
  ];

  void _selectSegmentOption(int segmentIndex, int optionIndex) {
    setState(() {
      _segments = [
        for (var index = 0; index < _segments.length; index += 1)
          if (index == segmentIndex)
            _segments[index].copyWith(selectedIndex: optionIndex)
          else
            _segments[index],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.48,
      minChildSize: 0.28,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return SizedBox(
          width: double.infinity,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(
                              [for (final segment in _segments) segment.selectedIndex],
                            ),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: _segments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _RouteSegmentSelector(
                          segment: _segments[index],
                          onSelected: (optionIndex) =>
                              _selectSegmentOption(index, optionIndex),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InlineRouteBranchSheet extends StatelessWidget {
  const _InlineRouteBranchSheet({
    required this.title,
    required this.segments,
    required this.onChanged,
  });

  final String title;
  final List<_RoutePreviewSegment> segments;
  final void Function(int segmentIndex, int optionIndex) onChanged;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.24,
      minChildSize: 0.20,
      maxChildSize: 0.72,
      builder: (context, scrollController) {
        return SizedBox(
          width: double.infinity,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            elevation: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Drag up to compare branch options for each section.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: segments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _RouteSegmentSelector(
                        segment: segments[index],
                        onSelected: (optionIndex) =>
                            onChanged(index, optionIndex),
                      );
                    },
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

class _RoutePreviewMapScreen extends StatefulWidget {
  const _RoutePreviewMapScreen({
    required this.previewSegments,
    required this.startPoint,
    required this.endPoint,
  });

  final List<_RoutePreviewSegment> previewSegments;
  final LatLng? startPoint;
  final LatLng? endPoint;

  @override
  State<_RoutePreviewMapScreen> createState() => _RoutePreviewMapScreenState();
}

class _RoutePreviewMapScreenState extends State<_RoutePreviewMapScreen> {
  late List<_RoutePreviewSegment> _segments = [
    for (final segment in widget.previewSegments) segment,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              [for (final segment in _segments) segment.selectedIndex],
            ),
            child: const Text('Use this'),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _RoutePreviewMap(
                previewSegments: _segments,
                startPoint: widget.startPoint,
                endPoint: widget.endPoint,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _InlineRouteBranchSheet(
                title: 'Choose branches',
                segments: _segments,
                onChanged: (segmentIndex, optionIndex) {
                  setState(() {
                    _segments = [
                      for (var index = 0; index < _segments.length; index += 1)
                        if (index == segmentIndex)
                          _segments[index].copyWith(selectedIndex: optionIndex)
                        else
                          _segments[index],
                    ];
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Marker? _routeMarker(LatLng? point, Color color) {
  if (point == null) return null;
  return Marker(
    point: point,
    width: 28,
    height: 28,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    ),
  );
}

class _RoutePreviewSegment {
  const _RoutePreviewSegment({
    required this.label,
    required this.options,
    this.selectedIndex = 0,
  });

  final String label;
  final List<_RoutePreviewOption> options;
  final int selectedIndex;

  _RoutePreviewOption get selectedOption {
    if (options.isEmpty) {
      return _RoutePreviewOption.empty;
    }
    return options[selectedIndex.clamp(0, options.length - 1)];
  }

  _RoutePreviewSegment copyWith({
    String? label,
    List<_RoutePreviewOption>? options,
    int? selectedIndex,
  }) {
    return _RoutePreviewSegment(
      label: label ?? this.label,
      options: options ?? this.options,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }
}

class _RoutePreviewOption {
  const _RoutePreviewOption({
    required this.label,
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });

  static const empty = _RoutePreviewOption(
    label: 'Route',
    points: <LatLng>[],
    distanceKm: null,
    durationMinutes: null,
  );

  final String label;
  final List<LatLng> points;
  final double? distanceKm;
  final double? durationMinutes;

  String get summaryLabel {
    final distance = distanceKm?.toStringAsFixed(1) ?? '--';
    final duration = durationMinutes?.toStringAsFixed(0) ?? '--';
    return '$label · $distance km · $duration min';
  }
}
