import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/parago_format.dart';
import '../../models/operations/notification.dart';
import '../../models/operations/pickup_request.dart';
import '../../models/operations/ride_session.dart';
import '../../models/operations/stop_alert.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/trip_session.dart';
import '../../services/driver_service.dart';
import '../../services/notification_service.dart';
import '../../services/ride_session_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import 'driver_live_map_screen.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/status_badge.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const _pickupStatuses = {'pending', 'acknowledged'};
  static const _activeAlertStatuses = {'sent', 'seen'};

  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  List<NotificationModel> _notifications = [];
  Map<String, List<PickupRequestModel>> _tripRequests = {};
  Map<String, List<StopAlertModel>> _tripAlerts = {};
  Map<String, List<RideSessionModel>> _tripRides = {};
  Map<String, int> _manualOnboardAdjustments = {};
  String? _focusedTripId;
  int _tabIndex = 0;
  bool _isOnline = true;
  bool _loading = false;
  String? _statusMessage;
  LatLng? _vehicleLocation;
  Timer? _vehicleLocationTimer;
  bool _locationPluginUnavailable = false;
  bool _locationLoopActive = true;

  TripSession? get _focusedTrip {
    for (final trip in _trips) {
      if (trip.id == _focusedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _startVehicleLocationHeartbeat();
  }

  @override
  void dispose() {
    _vehicleLocationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    final notificationService = NotificationService(session.apiClient);
    final routeService = RouteService(session.apiClient);
    final driverService = DriverService(session.apiClient);
    final stopAlertService = StopAlertService(session.apiClient);
    final rideSessionService = RideSessionService(session.apiClient);

    setState(() => _loading = true);

    try {
      final initialResults = await Future.wait<dynamic>([
        tripService.getMyTrips(),
        notificationService.getMine(),
        routeService.getRoutes(),
        driverService.getProfile(),
      ]);

      final trips = initialResults[0] as List<TripSession>;
      final notifications = initialResults[1] as List<NotificationModel>;
      final routes = initialResults[2] as List<RouteSummaryModel>;
      final driverProfile = initialResults[3] as Map<String, dynamic>;
      final driverStatus = driverProfile['status']?.toString().toLowerCase();

      final requestEntries = await Future.wait(
        trips.map((trip) async =>
            MapEntry(trip.id, await driverService.getRequestsForTrip(trip.id))),
      );
      final alertEntries = await Future.wait(
        trips.map((trip) async => MapEntry(
              trip.id,
              await stopAlertService.getTripStopAlerts(trip.id),
            )),
      );
      final rideEntries = await Future.wait(
        trips.map((trip) async => MapEntry(
              trip.id,
              await rideSessionService.getTripRides(trip.id),
            )),
      );

      final nextFocus = trips.any((trip) => trip.id == _focusedTripId)
          ? _focusedTripId
          : trips
              .firstWhere(
                (trip) => trip.status == 'active',
                orElse: () => trips.isNotEmpty
                    ? trips.first
                    : const TripSession(
                        id: '',
                        jeepneyId: '',
                        driverId: '',
                        routeId: '',
                        status: '',
                      ),
              )
              .id;

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _notifications = notifications;
        _routes = routes;
        if (driverStatus == 'active' || driverStatus == 'inactive') {
          _isOnline = driverStatus == 'active';
        }
        _tripRequests = {
          for (final entry in requestEntries) entry.key: entry.value,
        };
        _tripAlerts = {
          for (final entry in alertEntries) entry.key: entry.value,
        };
        _tripRides = {
          for (final entry in rideEntries) entry.key: entry.value,
        };
        _focusedTripId =
            (nextFocus == null || nextFocus.isEmpty) ? null : nextFocus;
        _manualOnboardAdjustments = {
          for (final trip in trips)
            trip.id: _manualOnboardAdjustments[trip.id] ?? 0,
        };
      });
      _publishVehicleLocation();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startTrip(String tripId) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    try {
      await tripService.startTrip(tripId);
      setState(() {
        _statusMessage =
            'Trip started. The driver map is now ready for live pickup handling.';
      });
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<void> _endTrip(String tripId) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    try {
      await tripService.endTrip(tripId);
      setState(() {
        _statusMessage = 'Trip ended. Ride sessions and alerts were closed.';
      });
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<void> _toggleAccept(String tripId, bool accept) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    try {
      await tripService.setTripAvailability(tripId, accept);
      setState(() {
        _statusMessage =
            accept ? 'Pickup requests reopened.' : 'Pickup requests paused.';
      });
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<void> _acknowledgeRequest(String requestId) async {
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    try {
      await driverService.acknowledgeRequest(requestId);
      setState(() => _statusMessage = 'Pickup request acknowledged.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<void> _completeRequest(String requestId) async {
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    try {
      await driverService.completeRequest(requestId);
      setState(() => _statusMessage = 'Pickup request marked completed.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    final session = context.read<SessionController>();
    final alertService = StopAlertService(session.apiClient);
    try {
      await alertService.acknowledgeStopAlert(alertId);
      setState(() => _statusMessage = 'Destination alert acknowledged.');
      await _load();
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    }
  }

  void _setOnline(bool value) async {
    final previous = _isOnline;
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    if (!mounted) return;
    try {
      setState(() => _statusMessage = 'Saving availability...');
      await driverService.setStatus(active: value);
      if (!mounted) return;
      setState(() {
        _isOnline = value;
        _statusMessage = value
            ? 'Driver is online and can receive route ride alerts.'
            : 'Driver is offline and hidden from new route ride alerts.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isOnline = previous;
        _statusMessage = error.toString();
      });
    }
  }

  void _startVehicleLocationHeartbeat() {
    _vehicleLocationTimer?.cancel();
    _vehicleLocationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        if (!mounted) return;
        if (!_locationLoopActive) return;
        _publishVehicleLocation().catchError((error, _) {
          _setStatusMessage('Location loop stopped due to unexpected error.');
          _locationLoopActive = false;
          debugPrint('Location loop error: $error');
        });
      },
    );
    _publishVehicleLocation();
  }

  Future<void> _publishVehicleLocation() async {
    if (!mounted) {
      return;
    }

    if (_locationPluginUnavailable) {
      _setStatusMessage(
        'Location sync is not available in this build. Rebuild with mobile platform support.',
      );
      return;
    }

    if (!(kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      _setStatusMessage(
        'Location sync is currently available only on web, Android, and iOS builds.',
      );
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setStatusMessage('Enable device location service to share jeepney location.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setStatusMessage(
          'Location permission denied. Enable it in system settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      final next = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      if (_vehicleLocation == null ||
          (next.latitude - _vehicleLocation!.latitude).abs() >
              0.00008 ||
          (next.longitude - _vehicleLocation!.longitude).abs() > 0.00008) {
        setState(() {
          _vehicleLocation = next;
        });
      }

      if (!_isOnline) {
        _setStatusMessage(
          'You are offline. Location is shown locally but not shared to passengers yet.',
        );
        return;
      }

      final session = context.read<SessionController>();
      final driverService = DriverService(session.apiClient);
      await driverService.updateLocation(lat: next.latitude, lng: next.longitude);
      _setStatusMessage('Live jeepney location updated and shared.');
    } on MissingPluginException {
      _locationPluginUnavailable = true;
      _locationLoopActive = false;
      _setStatusMessage(
        'Location plugin is not wired in this build. Run flutter clean, then flutter pub get, then rebuild.',
      );
    } catch (error) {
      _setStatusMessage(
        'Location loop disabled due unexpected error. Open app logs for details.',
      );
      _locationLoopActive = false;
      debugPrint('Location publish error: $error');
    }
  }

  void _setStatusMessage(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
  }

  LatLng? _storedVehicleLocation(TripSession trip) {
    if (trip.jeepneyLatitude == null || trip.jeepneyLongitude == null) {
      return null;
    }
    return LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!);
  }

  LatLng? _vehicleLocationForTrip(TripSession trip) {
    return _vehicleLocation ?? _storedVehicleLocation(trip);
  }

  void _changePassengerCount(String tripId, int delta) {
    final trip = _trips
        .cast<TripSession?>()
        .firstWhere((item) => item?.id == tripId, orElse: () => _focusedTrip);
    if (trip == null) return;

    setState(() {
      final current = _manualOnboardAdjustments[tripId] ?? 0;
      final updated = current + delta;
      final rides = _tripRides[tripId] ?? const <RideSessionModel>[];
      final base = _baseOnboardCount(trip, rides);
      _manualOnboardAdjustments[tripId] = math.max(-base, updated);
      _statusMessage =
          'Passenger counter adjusted manually for the active drive screen.';
    });
  }

  String _routeLabel(TripSession trip) {
    if (trip.routeName != null && trip.routeName!.isNotEmpty) {
      return trip.routeLabel;
    }
    for (final route in _routes) {
      if (route.id == trip.routeId) return route.label;
    }
    return ParagoFormat.shortId(trip.routeId);
  }

  int _baseOnboardCount(TripSession? trip, List<RideSessionModel> rides) {
    if (trip?.occupancyCount != null) {
      return trip!.occupancyCount!;
    }
    return rides.where((ride) => ride.status == 'onboard').length;
  }

  int _displayedOnboardCount(TripSession? trip, List<RideSessionModel> rides) {
    if (trip == null) return 0;
    final base = _baseOnboardCount(trip, rides);
    final delta = _manualOnboardAdjustments[trip.id] ?? 0;
    return math.max(0, base + delta);
  }

  LatLng _baseMapCenter(TripSession trip) {
    const fallbackCenter = LatLng(14.6091, 121.0223);
    final source = '${trip.routeId}:${trip.id}:${trip.jeepneyId}';
    final hash = source.hashCode;
    final latOffset = ((hash % 180) - 90) / 6000.0;
    final lngOffset = (((hash ~/ 180) % 180) - 90) / 6000.0;
    return LatLng(
      fallbackCenter.latitude + latOffset,
      fallbackCenter.longitude + lngOffset,
    );
  }

  List<LatLng> _routePathForTrip(TripSession trip, {LatLng? center}) {
    final routeCenter = center ?? _baseMapCenter(trip);
    return [
      LatLng(routeCenter.latitude - 0.012, routeCenter.longitude - 0.016),
      LatLng(routeCenter.latitude - 0.007, routeCenter.longitude - 0.009),
      LatLng(routeCenter.latitude - 0.002, routeCenter.longitude - 0.004),
      LatLng(routeCenter.latitude + 0.003, routeCenter.longitude + 0.002),
      LatLng(routeCenter.latitude + 0.008, routeCenter.longitude + 0.011),
      LatLng(routeCenter.latitude + 0.013, routeCenter.longitude + 0.018),
    ];
  }

  List<_DriveMarkerData> _buildMarkers(
    TripSession trip,
    List<PickupRequestModel> requests,
    List<StopAlertModel> alerts,
    List<RideSessionModel> rides,
    LatLng? vehiclePosition,
    LatLng? routeCenter,
  ) {
    final routePath = _routePathForTrip(
      trip,
      center: routeCenter ?? vehiclePosition,
    );
    final jeepneyPosition = vehiclePosition ?? routePath[2];

    final markers = <_DriveMarkerData>[
      _DriveMarkerData(
        label: trip.jeepneyLabel,
        detail: 'Current jeepney location',
        position: jeepneyPosition,
        icon: Icons.directions_bus_filled,
        markerColor: const Color(0xFF2E8B57),
        kind: _DriveMarkerKind.vehicle,
      ),
    ];

    final activeRequests = requests
        .where((request) => _pickupStatuses.contains(request.status))
        .toList();
    for (var index = 0; index < activeRequests.length; index += 1) {
      final request = activeRequests[index];
      markers.add(
        _DriveMarkerData(
          label: request.stopRef ?? 'Pickup ${index + 1}',
          detail: request.status == 'acknowledged'
              ? 'Acknowledged pickup'
              : 'Waiting pickup',
          position: routePath[math.min(index, routePath.length - 1)],
          icon: Icons.person_pin_circle,
          markerColor: request.status == 'acknowledged'
              ? const Color(0xFF1F8FD5)
              : const Color(0xFFE2902D),
          kind: _DriveMarkerKind.pickup,
        ),
      );
    }

    final activeAlerts = alerts
        .where((alert) => _activeAlertStatuses.contains(alert.status))
        .toList();
    for (var index = 0; index < activeAlerts.length; index += 1) {
      final alert = activeAlerts[index];
      markers.add(
        _DriveMarkerData(
          label: alert.stopRef,
          detail: 'Unload request near destination',
          position: routePath[math.min(index + 2, routePath.length - 1)],
          icon: Icons.flag_circle,
          markerColor: const Color(0xFFCC4B7A),
          kind: _DriveMarkerKind.unload,
        ),
      );
    }

    if (rides.where((ride) => ride.status == 'onboard').isNotEmpty &&
        activeAlerts.isEmpty) {
      markers.add(
        _DriveMarkerData(
          label: 'Onboard group',
          detail: 'Verified passengers on this trip',
          position: routePath[math.min(routePath.length - 1, 3)],
          icon: Icons.groups_2,
          markerColor: const Color(0xFF356AC3),
          kind: _DriveMarkerKind.onboard,
        ),
      );
    }

    return markers;
  }

  String _tabTitle() {
    switch (_tabIndex) {
      case 1:
        return 'Driver Requests';
      case 2:
        return 'Driver Alerts';
      case 3:
        return 'Driver Analytics';
      default:
        return 'Driver Drive';
    }
  }

  Widget _buildActiveTab({
    required TripSession? focusedTrip,
    required List<PickupRequestModel> focusedRequests,
    required List<StopAlertModel> focusedAlerts,
    required List<RideSessionModel> focusedRides,
  }) {
    switch (_tabIndex) {
      case 1:
        return _buildRequestsTab(
          focusedTrip: focusedTrip,
          requests: focusedRequests,
        );
      case 2:
        return _buildAlertsTab(
          focusedTrip: focusedTrip,
          alerts: focusedAlerts,
        );
      case 3:
        return _buildAnalyticsTab(
          notifications: _notifications,
          focusedTrip: focusedTrip,
        );
      default:
        return _buildDriveTab(
          focusedTrip: focusedTrip,
          requests: focusedRequests,
          alerts: focusedAlerts,
          rides: focusedRides,
        );
    }
  }

  Widget _buildDriveTab({
    required TripSession? focusedTrip,
    required List<PickupRequestModel> requests,
    required List<StopAlertModel> alerts,
    required List<RideSessionModel> rides,
  }) {
    return const SizedBox.shrink();
  }

  Widget _buildPersistentDriverSurface({
    required SessionController session,
    required TripSession? focusedTrip,
    required List<PickupRequestModel> focusedRequests,
    required List<StopAlertModel> focusedAlerts,
    required List<RideSessionModel> focusedRides,
    required double mapHeight,
  }) {
    final displayedOnboard = _displayedOnboardCount(focusedTrip, focusedRides);
    final activeAlerts = focusedAlerts
        .where((alert) => _activeAlertStatuses.contains(alert.status))
        .toList();
    final liveVehicleLocation = _vehicleLocation;
    final tripVehicleLocation =
        focusedTrip == null ? null : _vehicleLocationForTrip(focusedTrip);
    final routePath = focusedTrip == null
        ? const <LatLng>[]
        : _routePathForTrip(
            focusedTrip,
            center: tripVehicleLocation,
          );
    final markers = <_DriveMarkerData>[];

    if (liveVehicleLocation != null) {
      markers.add(
        _DriveMarkerData(
          label: 'Current location',
          detail: 'Live device GPS',
          position: liveVehicleLocation,
          icon: Icons.my_location,
          markerColor: const Color(0xFF1F8FD5),
          kind: _DriveMarkerKind.vehicle,
        ),
      );
    }

    if (focusedTrip != null) {
      markers.addAll(
        _buildMarkers(
            focusedTrip,
            focusedRequests,
            focusedAlerts,
            focusedRides,
            tripVehicleLocation,
            tripVehicleLocation,
        ),
      );
    }

    final mapCenter = liveVehicleLocation ??
        tripVehicleLocation ??
        (routePath.isEmpty
            ? const LatLng(14.6091, 121.0223)
            : routePath[math.min(routePath.length - 1, 2)]);

    return _DriveMapPanel(
      cameraTarget: mapCenter,
      trip: focusedTrip,
      driverName: session.user?.fullName ?? 'Driver',
      statusMessage: _statusMessage,
      isOnline: _isOnline,
      onOnlineChanged: _setOnline,
      activePickupCount: focusedRequests
          .where((request) => _pickupStatuses.contains(request.status))
          .length,
      routeLabel:
          focusedTrip == null ? 'Metro overview' : _routeLabel(focusedTrip),
      displayedOnboard: displayedOnboard,
      manualAdjustment: focusedTrip == null
          ? 0
          : (_manualOnboardAdjustments[focusedTrip.id] ?? 0),
      routePath: routePath,
      markers: markers,
      activeDestinationAlerts: activeAlerts,
      onIncrement: focusedTrip == null
          ? null
          : () => _changePassengerCount(focusedTrip.id, 1),
      onDecrement: focusedTrip == null
          ? null
          : () => _changePassengerCount(focusedTrip.id, -1),
      onStartTrip:
          focusedTrip == null || _loading || focusedTrip.status == 'active'
              ? null
              : () => _startTrip(focusedTrip.id),
      onEndTrip:
          focusedTrip == null || _loading || focusedTrip.status != 'active'
              ? null
              : () => _endTrip(focusedTrip.id),
      onTogglePickup:
          focusedTrip == null || _loading || focusedTrip.status != 'active'
              ? null
              : () => _toggleAccept(
                    focusedTrip.id,
                    !(focusedTrip.acceptRequests ?? true),
                  ),
      onAcknowledgeAlert: activeAlerts.isEmpty
          ? null
          : () => _acknowledgeAlert(activeAlerts.first.id),
      height: mapHeight,
    );
  }

  Widget _buildRequestsTab({
    required TripSession? focusedTrip,
    required List<PickupRequestModel> requests,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _TabIntroCard(
          title: 'Pickup requests',
          description:
              'Keep acknowledgements and completions quick while the main drive tab stays focused on navigation.',
          accent: const Color(0xFFE29B2D),
        ),
        const SizedBox(height: 16),
        if (focusedTrip == null)
          const _DriverEmptyState(
            title: 'No trip selected',
            message: 'Select a trip to view and manage pickup requests.',
          )
        else if (requests.isEmpty)
          const _DriverEmptyState(
            title: 'Pickup queue clear',
            message: 'No active pickup requests are waiting on this trip.',
          )
        else
          for (final request in requests) ...[
            _DriverActionCard(
              title: request.stopRef ?? 'Unspecified pickup point',
              subtitle:
                  '${ParagoFormat.statusLabel(request.status)} - ${ParagoFormat.relative(request.createdAt)}',
              detail: request.sourceNote ??
                  'Passenger requested a roadside pickup.',
              status: request.status,
              primaryLabel: request.status == 'pending' ? 'Acknowledge' : null,
              onPrimary: request.status == 'pending'
                  ? () => _acknowledgeRequest(request.id)
                  : null,
              secondaryLabel:
                  request.status == 'acknowledged' ? 'Complete pickup' : null,
              onSecondary: request.status == 'acknowledged'
                  ? () => _completeRequest(request.id)
                  : null,
              icon: Icons.person_pin_circle_outlined,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildAlertsTab({
    required TripSession? focusedTrip,
    required List<StopAlertModel> alerts,
  }) {
    final recentNotifications = _notifications.take(5).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _TabIntroCard(
          title: 'Stop alerts',
          description:
              'Destination notifications and system notices live here so the drive surface can stay visually calm.',
          accent: const Color(0xFF8A3B5D),
        ),
        const SizedBox(height: 16),
        Text('Passenger destination alerts',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (focusedTrip == null)
          const _DriverEmptyState(
            title: 'No trip selected',
            message: 'Select a trip to review destination alerts.',
          )
        else if (alerts.isEmpty)
          const _DriverEmptyState(
            title: 'No active stop alerts',
            message:
                'Passengers have not triggered any digital para alerts on this trip.',
          )
        else
          for (final alert in alerts) ...[
            _DriverActionCard(
              title: alert.stopRef,
              subtitle:
                  '${ParagoFormat.statusLabel(alert.status)} - ${ParagoFormat.relative(alert.createdAt)}',
              detail: alert.note ??
                  'Passenger is nearing the selected unloading point.',
              status: alert.status,
              primaryLabel: _activeAlertStatuses.contains(alert.status)
                  ? 'Acknowledge'
                  : null,
              onPrimary: _activeAlertStatuses.contains(alert.status)
                  ? () => _acknowledgeAlert(alert.id)
                  : null,
              icon: Icons.flag_circle_outlined,
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 18),
        Text('Driver notifications',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (recentNotifications.isEmpty)
          const _DriverEmptyState(
            title: 'No notifications yet',
            message: 'System notices and event confirmations will appear here.',
          )
        else
          for (final notification in recentNotifications) ...[
            _NotificationCard(notification: notification),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildAnalyticsTab({
    required List<NotificationModel> notifications,
    required TripSession? focusedTrip,
  }) {
    final assignedTrips = _trips.length;
    final activeTrips = _trips.where((trip) => trip.status == 'active').length;
    final pendingPickups = _tripRequests.values
        .expand((entries) => entries)
        .where((request) => request.status == 'pending')
        .length;
    final totalAlerts = _tripAlerts.values
        .expand((entries) => entries)
        .where((alert) => _activeAlertStatuses.contains(alert.status))
        .length;
    final totalOnboard = _tripRides.values
        .expand((entries) => entries)
        .where((ride) => ride.status == 'onboard')
        .length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _TabIntroCard(
          title: 'Driver analytics',
          description:
              'This stays secondary in the nav so the live trip map remains the primary working surface.',
          accent: const Color(0xFF2157A5),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: compact ? 1 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: compact ? 1.7 : 1.04,
              children: [
                MetricCard(
                  label: 'Assigned trips',
                  value: assignedTrips.toString(),
                  icon: Icons.route_outlined,
                  accent: const Color(0xFF0F6A5F),
                  caption: 'Trip records under this driver account',
                ),
                MetricCard(
                  label: 'Trips active now',
                  value: activeTrips.toString(),
                  icon: Icons.play_circle_outline,
                  accent: const Color(0xFF2157A5),
                  caption: 'Trips currently marked as active',
                ),
                MetricCard(
                  label: 'Pending pickups',
                  value: pendingPickups.toString(),
                  icon: Icons.near_me_outlined,
                  accent: const Color(0xFFE29B2D),
                  caption: 'Requests still waiting in the queue',
                ),
                MetricCard(
                  label: 'Destination alerts',
                  value: totalAlerts.toString(),
                  icon: Icons.flag_circle_outlined,
                  accent: const Color(0xFF8A3B5D),
                  caption: 'Passengers nearing their unload points',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operational summary',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                _SummaryRow(
                  label: 'Onboard passengers now',
                  value: totalOnboard.toString(),
                ),
                _SummaryRow(
                  label: 'Focused trip',
                  value: focusedTrip == null
                      ? 'No trip selected'
                      : _routeLabel(focusedTrip),
                ),
                _SummaryRow(
                  label: 'Unread notifications',
                  value: notifications
                      .where((notification) => !notification.isRead)
                      .length
                      .toString(),
                ),
                _SummaryRow(
                  label: 'Requests open',
                  value: focusedTrip?.acceptRequests == false ? 'No' : 'Yes',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final focusedTrip = _focusedTrip;
    final focusedRequests = focusedTrip == null
        ? const <PickupRequestModel>[]
        : (_tripRequests[focusedTrip.id] ?? const <PickupRequestModel>[]);
    final focusedAlerts = focusedTrip == null
        ? const <StopAlertModel>[]
        : (_tripAlerts[focusedTrip.id] ?? const <StopAlertModel>[]);
    final focusedRides = focusedTrip == null
        ? const <RideSessionModel>[]
        : (_tripRides[focusedTrip.id] ?? const <RideSessionModel>[]);

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitle()),
        actions: [
          IconButton(
            tooltip: 'Live map',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DriverLiveMapScreen(),
                ),
              );
            },
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => session.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
      if (_tabIndex != 0) {
        return RefreshIndicator(
          onRefresh: _load,
          child: _buildActiveTab(
            focusedTrip: focusedTrip,
                focusedRequests: focusedRequests,
                focusedAlerts: focusedAlerts,
                focusedRides: focusedRides,
              ),
            );
          }

          final mapHeight = constraints.maxHeight.toDouble();

          return SizedBox.expand(
            child: _buildPersistentDriverSurface(
              session: session,
              focusedTrip: focusedTrip,
              focusedRequests: focusedRequests,
              focusedAlerts: focusedAlerts,
              focusedRides: focusedRides,
              mapHeight: mapHeight,
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Drive',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_add_check_circle_outlined),
            selectedIcon: Icon(Icons.playlist_add_check_circle),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}

class _DriverOverviewHeader extends StatelessWidget {
  const _DriverOverviewHeader({
    required this.name,
    required this.routeLabel,
    required this.isOnline,
    required this.onOnlineChanged,
  });

  final String name;
  final String routeLabel;
  final bool isOnline;
  final ValueChanged<bool> onOnlineChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        routeLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF2EFE7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _OnlineToggleChip(
                      label: 'Online',
                      selected: isOnline,
                      selectedBackground: const Color(0xFFD8F3E6),
                      selectedForeground: const Color(0xFF13623E),
                      onTap: () => onOnlineChanged(true),
                    ),
                  ),
                  Expanded(
                    child: _OnlineToggleChip(
                      label: 'Offline',
                      selected: !isOnline,
                      selectedBackground: const Color(0xFFE9E2D4),
                      selectedForeground: const Color(0xFF7A4E16),
                      onTap: () => onOnlineChanged(false),
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

class _OnlineToggleChip extends StatelessWidget {
  const _OnlineToggleChip({
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? selectedBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? selectedForeground
                  : Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverStatusBanner extends StatelessWidget {
  const _DriverStatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSelectorCard extends StatelessWidget {
  const _TripSelectorCard({
    required this.trips,
    required this.selectedTripId,
    required this.routeLabelFor,
    required this.onChanged,
  });

  final List<TripSession> trips;
  final String? selectedTripId;
  final String Function(TripSession) routeLabelFor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assigned trip',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (trips.isEmpty)
              Text(
                'No trips are currently assigned to this driver.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedTripId,
                items: trips
                    .map(
                      (trip) => DropdownMenuItem<String>(
                        value: trip.id,
                        child: Text(
                          routeLabelFor(trip),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DriveMapPanel extends StatelessWidget {
  const _DriveMapPanel({
    required this.trip,
    required this.cameraTarget,
    required this.driverName,
    required this.statusMessage,
    required this.isOnline,
    required this.onOnlineChanged,
    required this.activePickupCount,
    required this.routeLabel,
    required this.displayedOnboard,
    required this.manualAdjustment,
    required this.routePath,
    required this.markers,
    required this.activeDestinationAlerts,
    required this.onIncrement,
    required this.onDecrement,
    required this.onStartTrip,
    required this.onEndTrip,
    required this.onTogglePickup,
    required this.onAcknowledgeAlert,
    this.height,
  });

  final TripSession? trip;
  final LatLng cameraTarget;
  final String driverName;
  final String? statusMessage;
  final bool isOnline;
  final ValueChanged<bool> onOnlineChanged;
  final int activePickupCount;
  final String routeLabel;
  final int displayedOnboard;
  final int manualAdjustment;
  final List<LatLng> routePath;
  final List<_DriveMarkerData> markers;
  final List<StopAlertModel> activeDestinationAlerts;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onStartTrip;
  final VoidCallback? onEndTrip;
  final VoidCallback? onTogglePickup;
  final VoidCallback? onAcknowledgeAlert;
  final double? height;

  void _openControlSheet(BuildContext context, bool hasTrip, bool isTripActive) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.35,
        maxChildSize: 0.78,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF132F2E),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _DriverOverviewHeader(
                      name: driverName,
                      routeLabel: trip == null
                          ? 'Listening for route ride alerts'
                          : routeLabel,
                      isOnline: isOnline,
                      onOnlineChanged: onOnlineChanged,
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 12),
                      _DriverStatusBanner(message: statusMessage!),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Passengers onboard',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white70,
                            letterSpacing: 0.3,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          displayedOnboard.toString(),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            manualAdjustment == 0
                                ? 'manual 0'
                                : manualAdjustment > 0
                                    ? 'manual +$manualAdjustment'
                                    : 'manual $manualAdjustment',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$activePickupCount route ride alerts',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 18,
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          Expanded(
                            child: Text(
                              '${activeDestinationAlerts.length} unload alerts',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _CounterButton(
                          icon: Icons.remove,
                          onTap: hasTrip ? onDecrement : null,
                        ),
                        _CounterButton(
                          icon: Icons.add,
                          onTap: hasTrip ? onIncrement : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: onStartTrip,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start trip'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onEndTrip,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('End trip'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTogglePickup,
                          icon: Icon(
                            trip?.acceptRequests == false
                                ? Icons.playlist_add_check_circle_outlined
                                : Icons.pause_circle_outline,
                          ),
                          label: Text(
                            trip?.acceptRequests == false
                                ? 'Resume pickup'
                                : 'Pause pickup',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!hasTrip) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'No active trip selected yet. You can stay online and still share your jeepney location while on route.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ] else if (!isTripActive) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Start the trip when you are ready to receive ride alerts along your fixed route.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Focused trip snapshot',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              trip == null
                                  ? 'This driver screen handles route-based ride alerts, not direct passenger pickups.'
                                  : 'Passengers can alert along the route, and multiple riders can already be onboard.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 14),
                            _SummaryRow(
                              label: 'Route',
                              value: trip == null ? 'No active route' : routeLabel,
                            ),
                            _SummaryRow(
                              label: 'Trip status',
                              value: trip == null
                                  ? (isOnline ? 'Ready' : 'Offline')
                                  : ParagoFormat.statusLabel(trip!.status),
                            ),
                            _SummaryRow(
                              label: 'Route ride alerts',
                              value: activePickupCount.toString(),
                            ),
                            _SummaryRow(
                              label: 'Unload alerts',
                              value: activeDestinationAlerts.length.toString(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTripActive = trip?.status == 'active';
    final hasTrip = trip != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  key: ValueKey(
                    '${trip?.id ?? 'no-trip'}|${cameraTarget.latitude.toStringAsFixed(5)}|${cameraTarget.longitude.toStringAsFixed(5)}',
                  ),
                  options: MapOptions(
                    initialCenter: cameraTarget,
                    initialZoom: 14.2,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.parago.mobile',
                    ),
                    if (routePath.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePath,
                            strokeWidth: 6,
                            color: const Color(0xFF0F6A5F),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: markers
                          .map(
                            (entry) => Marker(
                              point: entry.position,
                              width: 150,
                              height: 92,
                              child: _DriveMapMarker(entry: entry),
                            ),
                          )
                          .toList(),
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.04),
                          Colors.white.withValues(alpha: 0.0),
                          const Color(0xFF102725).withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              StatusBadge(
                                status: isOnline
                                    ? hasTrip
                                        ? trip!.status
                                        : 'ready'
                                    : 'offline',
                              ),
                              StatusBadge(
                                status: trip?.acceptRequests == false
                                    ? 'paused'
                                    : 'on_road',
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.route, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                routeLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (activeDestinationAlerts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _DriverPopupAlert(
                        title: 'Passenger nearing destination',
                        message: activeDestinationAlerts.length == 1
                            ? '${activeDestinationAlerts.first.stopRef} is ready for unloading.'
                            : '${activeDestinationAlerts.first.stopRef} plus ${activeDestinationAlerts.length - 1} more unloading alerts are active.',
                        actionLabel: 'Acknowledge',
                        onAction: onAcknowledgeAlert,
                      ),
                    ],
                    if (statusMessage != null && statusMessage!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          statusMessage!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! < -120) {
                      _openControlSheet(context, hasTrip, isTripActive);
                    }
                  },
                  onTap: () => _openControlSheet(context, hasTrip, isTripActive),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF132F2E).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip == null
                                ? 'No trip selected - pull up for controls'
                                : 'Trip control panel - pull up',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverMiniPanel extends StatelessWidget {
  const _DriverMiniPanel({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(caption),
          ],
        ),
      ),
    );
  }
}

class _DriverActionCard extends StatelessWidget {
  const _DriverActionCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.status,
    required this.icon,
    this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String detail;
  final String status;
  final IconData icon;
  final String? primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 14),
            Text(detail),
            if (primaryLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (primaryLabel != null)
                    FilledButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel!),
                    ),
                  if (secondaryLabel != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final NotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                notification.isRead
                    ? Icons.drafts_outlined
                    : Icons.mark_email_unread,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusBadge(status: notification.isRead ? 'read' : 'new'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(notification.body),
                  const SizedBox(height: 8),
                  Text(
                    ParagoFormat.relative(notification.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
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

class _TabIntroCard extends StatelessWidget {
  const _TabIntroCard({
    required this.title,
    required this.description,
    required this.accent,
  });

  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.dashboard_customize_outlined, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverEmptyState extends StatelessWidget {
  const _DriverEmptyState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.route_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: isEnabled ? 0.1 : 0.04,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: isEnabled ? 0.26 : 0.12,
            ),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(
            alpha: isEnabled ? 1 : 0.35,
          ),
        ),
      ),
    );
  }
}

class _DriverPopupAlert extends StatelessWidget {
  const _DriverPopupAlert({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2EE).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFC8BA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_active, color: Color(0xFFB24E34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(message),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveMapMarker extends StatelessWidget {
  const _DriveMapMarker({required this.entry});

  final _DriveMarkerData entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: entry.detail,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF102725).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC8D3D3),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: entry.markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(entry.icon, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

enum _DriveMarkerKind {
  vehicle,
  pickup,
  unload,
  onboard,
}

class _DriveMarkerData {
  const _DriveMarkerData({
    required this.label,
    required this.detail,
    required this.position,
    required this.icon,
    required this.markerColor,
    required this.kind,
  });

  final String label;
  final String detail;
  final LatLng position;
  final IconData icon;
  final Color markerColor;
  final _DriveMarkerKind kind;
}
