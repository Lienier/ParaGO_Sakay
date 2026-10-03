import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';

class DriverLiveMapScreen extends StatefulWidget {
  const DriverLiveMapScreen({super.key});

  @override
  State<DriverLiveMapScreen> createState() => _DriverLiveMapScreenState();
}

class _DriverLiveMapScreenState extends State<DriverLiveMapScreen> {
  static const Duration _collapseDelay = Duration(seconds: 10);

  final MapController _mapController = MapController();
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.openrouteservice.org',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {
        'Content-Type': 'application/json',
      },
    ),
  );

  StreamSubscription<Position>? _positionSubscription;
  Timer? _collapseTimer;
  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = const <LatLng>[];
  String _statusMessage = 'Checking location services...';
  double? _etaMinutes;
  double? _distanceKm;
  bool _loadingLocation = true;
  bool _loadingRoute = false;
  bool _mapReady = false;
  bool _hasCenteredOnUser = false;
  bool _isChromeCollapsed = false;
  bool _consumeNextMapTap = false;

  @override
  void initState() {
    super.initState();
    _initializeLocationFlow();
    _scheduleChromeCollapse();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _positionSubscription?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  void _handleUserInteraction({bool expandChrome = true}) {
    if (expandChrome && _isChromeCollapsed && mounted) {
      setState(() {
        _isChromeCollapsed = false;
      });
    }
    _scheduleChromeCollapse();
  }

  void _handlePointerDown() {
    if (_isChromeCollapsed) {
      _consumeNextMapTap = true;
    }
    _handleUserInteraction();
  }

  void _scheduleChromeCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (!mounted || _isChromeCollapsed) return;
      setState(() {
        _isChromeCollapsed = true;
      });
    });
  }

  void _expandChrome() {
    if (!mounted) return;
    setState(() {
      _isChromeCollapsed = false;
    });
    _scheduleChromeCollapse();
  }

  Future<void> _initializeLocationFlow() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loadingLocation = false;
          _statusMessage =
              'Turn on device location services to use live mapping.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _loadingLocation = false;
          _statusMessage =
              'Location permission denied. Enable it in system settings.';
        });
        return;
      }

      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final current = LatLng(
        initialPosition.latitude,
        initialPosition.longitude,
      );

      setState(() {
        _currentLocation = current;
        _loadingLocation = false;
        _statusMessage =
            'Live GPS ready. Tap anywhere on the map to plan a route.';
      });

      _moveTo(current, zoom: 16);
      _subscribeToLocationUpdates();
    } catch (error) {
      setState(() {
        _loadingLocation = false;
        _statusMessage = 'Unable to get current location: $error';
      });
    }
  }

  void _subscribeToLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        final next = LatLng(position.latitude, position.longitude);
        if (!mounted) return;
        setState(() {
          _currentLocation = next;
        });
        if (!_hasCenteredOnUser) {
          _moveTo(next, zoom: 16);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Live location stream error: $error';
        });
      },
    );
  }

  void _moveTo(LatLng target, {double zoom = 16}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      _mapController.move(target, zoom);
      _hasCenteredOnUser = true;
    });
  }

  Future<void> _setDestination(LatLng point) async {
    _handleUserInteraction();
    setState(() {
      _destination = point;
      _routePoints = const <LatLng>[];
      _etaMinutes = null;
      _distanceKm = null;
      _statusMessage = 'Destination selected. Building route...';
    });
    await _fetchRoute();
  }

  void _handleMapTap(LatLng point) {
    if (_consumeNextMapTap) {
      _consumeNextMapTap = false;
      return;
    }
    if (_isChromeCollapsed) {
      _expandChrome();
      return;
    }
    unawaited(_setDestination(point));
  }

  Future<void> _fetchRoute() async {
    final origin = _currentLocation;
    final destination = _destination;
    if (origin == null || destination == null) {
      return;
    }
    if (AppConfig.openRouteServiceApiKey.isEmpty) {
      setState(() {
        _loadingRoute = false;
        _statusMessage =
            'OpenRouteService key missing. Pass ORS_API_KEY with --dart-define.';
      });
      return;
    }

    setState(() {
      _loadingRoute = true;
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v2/directions/driving-car',
        options: Options(
          headers: {
            'Authorization': AppConfig.openRouteServiceApiKey,
          },
        ),
        data: {
          'coordinates': [
            [origin.longitude, origin.latitude],
            [destination.longitude, destination.latitude],
          ],
          'instructions': false,
        },
      );

      final data = response.data ?? <String, dynamic>{};
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        throw Exception('No route returned by OpenRouteService.');
      }

      final route = routes.first as Map;
      final geometry = route['geometry'];
      final summary = route['summary'];

      final routePoints = switch (geometry) {
        String value => _decodePolyline(value),
        Map value => _decodeGeoJsonCoordinates(value['coordinates']),
        _ => const <LatLng>[],
      };

      if (routePoints.isEmpty) {
        throw Exception('Route geometry could not be decoded.');
      }

      setState(() {
        _routePoints = routePoints;
        _loadingRoute = false;
        _distanceKm = summary is Map
            ? _asDouble(summary['distance']) != null
                ? _asDouble(summary['distance'])! / 1000
                : null
            : null;
        _etaMinutes = summary is Map
            ? _asDouble(summary['duration']) != null
                ? _asDouble(summary['duration'])! / 60
                : null
            : null;
        _statusMessage = 'Route ready. Blue pin is your live location.';
      });

      _fitRoute(routePoints);
    } catch (error) {
      setState(() {
        _loadingRoute = false;
        _statusMessage = 'Failed to load route: $error';
      });
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (!_mapReady || points.isEmpty) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final zoom = _zoomForBounds(latSpan, lngSpan);
    _mapController.move(center, zoom);
  }

  double _zoomForBounds(double latSpan, double lngSpan) {
    final span = math.max(latSpan, lngSpan);
    if (span < 0.003) return 17.2;
    if (span < 0.008) return 16.4;
    if (span < 0.02) return 15.4;
    if (span < 0.05) return 14.2;
    if (span < 0.12) return 13.2;
    return 12;
  }

  List<LatLng> _decodeGeoJsonCoordinates(dynamic coordinates) {
    if (coordinates is! List) return const <LatLng>[];
    final points = <LatLng>[];
    for (final entry in coordinates) {
      if (entry is List && entry.length >= 2) {
        final lng = _asDouble(entry[0]);
        final lat = _asDouble(entry[1]);
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
    }
    return points;
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      result = 0;
      shift = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = _currentLocation;
    final destination = _destination;
    final routeMetricLabel = [
      if (_distanceKm != null) '${_distanceKm!.toStringAsFixed(2)} km',
      if (_etaMinutes != null) '${_etaMinutes!.toStringAsFixed(0)} min',
    ].join(' / ');
    final markers = <Marker>[
      if (currentLocation != null)
        Marker(
          point: currentLocation,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x401E88E5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      if (destination != null)
        Marker(
          point: destination,
          width: 44,
          height: 44,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFFD84315),
            size: 40,
          ),
        ),
    ];

    return Scaffold(
      appBar: _isChromeCollapsed
          ? null
          : AppBar(
              title: const Text('Driver live map'),
            ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _handlePointerDown(),
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _isChromeCollapsed
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Track your live jeepney position, tap a destination, and draw a route using OpenRouteService.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _InfoChip(
                                label: currentLocation == null
                                    ? 'Waiting for GPS'
                                    : 'GPS ${currentLocation.latitude.toStringAsFixed(5)}, ${currentLocation.longitude.toStringAsFixed(5)}',
                                color: const Color(0xFFDCEEFF),
                              ),
                              if (_distanceKm != null)
                                _InfoChip(
                                  label:
                                      'Distance ${_distanceKm!.toStringAsFixed(2)} km',
                                  color: const Color(0xFFE5F3DE),
                                ),
                              if (_etaMinutes != null)
                                _InfoChip(
                                  label:
                                      'ETA ${_etaMinutes!.toStringAsFixed(0)} min',
                                  color: const Color(0xFFFFE7C2),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _statusMessage,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          currentLocation ?? const LatLng(14.6091, 121.0223),
                      initialZoom: 14,
                      onMapReady: () {
                        _mapReady = true;
                        if (currentLocation != null && !_hasCenteredOnUser) {
                          _moveTo(currentLocation, zoom: 16);
                        }
                      },
                      onTap: (_, point) => _handleMapTap(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.parago_mobile',
                      ),
                      PolylineLayer(
                        polylines: [
                          if (_routePoints.isNotEmpty)
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 5,
                              color: const Color(0xFF0D8B6F),
                            ),
                        ],
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      offset: _isChromeCollapsed
                          ? Offset.zero
                          : const Offset(0, -1.1),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _isChromeCollapsed ? 1 : 0,
                        child: _CollapsedMapSummary(
                          gpsLabel: currentLocation == null
                              ? 'GPS waiting'
                              : 'GPS ${currentLocation.latitude.toStringAsFixed(5)}, ${currentLocation.longitude.toStringAsFixed(5)}',
                          destinationLabel: destination == null
                              ? 'No destination'
                              : 'Drop-off point set',
                          routeMetricLabel: routeMetricLabel.isEmpty
                              ? 'Route pending'
                              : routeMetricLabel,
                          statusMessage: _statusMessage,
                          onExpand: _expandChrome,
                        ),
                      ),
                    ),
                  ),
                  if (_loadingLocation || _loadingRoute)
                    const Positioned(
                      top: 16,
                      right: 16,
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Updating map...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!_isChromeCollapsed)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'refresh_location',
                            onPressed: () {
                              _handleUserInteraction();
                              _initializeLocationFlow();
                            },
                            child: const Icon(Icons.gps_fixed),
                          ),
                          const SizedBox(height: 12),
                          FloatingActionButton.extended(
                            heroTag: 'recenter_location',
                            onPressed: currentLocation == null
                                ? null
                                : () {
                                    _handleUserInteraction();
                                    _moveTo(currentLocation, zoom: 16);
                                  },
                            icon: const Icon(Icons.my_location),
                            label: const Text('Recenter'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedMapSummary extends StatelessWidget {
  const _CollapsedMapSummary({
    required this.gpsLabel,
    required this.destinationLabel,
    required this.routeMetricLabel,
    required this.statusMessage,
    required this.onExpand,
  });

  final String gpsLabel;
  final String destinationLabel;
  final String routeMetricLabel;
  final String statusMessage;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onExpand,
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Text(
                        destinationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _InfoChip(
                  label: gpsLabel,
                  color: const Color(0xFFDCEEFF),
                ),
                _InfoChip(
                  label: routeMetricLabel,
                  color: const Color(0xFFE5F3DE),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              statusMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
