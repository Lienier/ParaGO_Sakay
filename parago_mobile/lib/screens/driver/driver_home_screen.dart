import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
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
import '../../services/route_preview_cache.dart';
import '../../services/route_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import 'driver_live_map_screen.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/status_badge.dart';

part 'driver_home_screen_sections.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  static const _pickupStatuses = {'pending', 'acknowledged'};
  static const _activeAlertStatuses = {'sent', 'seen'};

  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  Map<String, List<LatLng>> _cachedRoutePreviewPoints = {};
  List<NotificationModel> _notifications = [];
  Map<String, List<PickupRequestModel>> _tripRequests = {};
  Map<String, List<StopAlertModel>> _tripAlerts = {};
  Map<String, List<RideSessionModel>> _tripRides = {};
  Map<String, int> _manualOnboardAdjustments = {};
  String? _assignedRouteId;
  String? _focusedTripId;
  int _tabIndex = 0;
  bool _isOnline = false;
  bool _hasInternet = true;
  bool _loading = false;
  String? _statusMessage;
  String _availabilityNote = 'Checking driver availability...';
  LatLng? _vehicleLocation;
  Timer? _vehicleLocationTimer;
  Timer? _liveRefreshTimer;
  Timer? _availabilityTimer;
  StreamSubscription<Map<String, dynamic>>? _realtimeNotificationSubscription;
  bool _locationPluginUnavailable = false;
  bool _locationLoopActive = true;
  bool _silentRefreshActive = false;
  bool _realtimePrimed = false;
  bool _availabilitySyncInFlight = false;
  bool? _lastPublishedOnline;
  AppLifecycleState? _appLifecycleState;
  int _loadGeneration = 0;
  Set<String> _knownNotificationIds = <String>{};
  Set<String> _knownActiveStopAlertIds = <String>{};
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  final MapController _driverMapController = MapController();
  LatLng? _lastDriverMapCenter;

  TripSession? get _focusedTrip {
    for (final trip in _trips) {
      if (trip.id == _focusedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted) {
        _startVehicleLocationHeartbeat();
        unawaited(
          _refreshAutomaticAvailability(
            probeNetwork: false,
            forcePush: true,
          ),
        );
      }
    });
    _startLiveRefreshLoop();
    _startAutomaticAvailabilityLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vehicleLocationTimer?.cancel();
    _liveRefreshTimer?.cancel();
    _availabilityTimer?.cancel();
    _realtimeNotificationSubscription?.cancel();
    _realtimeSocketService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAutomaticAvailability(forcePush: true));
      return;
    }

    if (state == AppLifecycleState.inactive) {
      unawaited(
        _refreshAutomaticAvailability(
          probeNetwork: false,
          forcePush: true,
        ),
      );
      return;
    }

    _realtimeSocketService.disconnect();
    unawaited(
      _refreshAutomaticAvailability(
        probeNetwork: false,
        forcePush: true,
      ),
    );
  }

  bool get _isAppForeground {
    switch (_appLifecycleState) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        return false;
      case AppLifecycleState.resumed:
      case null:
        return true;
    }
  }

  bool get _isAppDetached => _appLifecycleState == AppLifecycleState.detached;

  bool _shouldBeOnline(SessionController session, {bool? hasInternet}) {
    return session.isAuthenticated &&
        !_isAppDetached &&
        (hasInternet ?? _hasInternet);
  }

  bool _shouldKeepRealtimeConnected(
    SessionController session, {
    bool? hasInternet,
  }) {
    return session.isAuthenticated &&
        _isAppForeground &&
        !_isAppDetached &&
        (hasInternet ?? _hasInternet);
  }

  String _availabilityNoteFor(
    SessionController session, {
    required bool hasInternet,
    required bool isOnline,
  }) {
    if (!session.isAuthenticated) {
      return 'Driver stays offline until the account is signed in.';
    }
    if (_isAppDetached) {
      return 'Driver is offline because the app session has ended.';
    }
    if (!_isAppForeground) {
      return 'Driver stays online in the background, but live syncing can pause until the app returns to the foreground.';
    }
    if (!hasInternet) {
      return 'Driver is offline because the device cannot reach the ParaGO server.';
    }
    if (isOnline) {
      return 'Driver is online automatically while signed in, in-app, and connected.';
    }
    return 'Checking driver availability...';
  }

  void _applyAutomaticAvailabilityState(
    SessionController session, {
    bool? hasInternet,
  }) {
    if (!mounted) {
      return;
    }

    final nextHasInternet = hasInternet ?? _hasInternet;
    final nextOnline = _shouldBeOnline(session, hasInternet: nextHasInternet);
    final nextNote = _availabilityNoteFor(
      session,
      hasInternet: nextHasInternet,
      isOnline: nextOnline,
    );

    if (_hasInternet == nextHasInternet &&
        _isOnline == nextOnline &&
        _availabilityNote == nextNote) {
      return;
    }

    setState(() {
      _hasInternet = nextHasInternet;
      _isOnline = nextOnline;
      _availabilityNote = nextNote;
    });
  }

  bool _looksLikeConnectivityIssue(Object error) {
    final message = ActionFeedback.messageOf(error).toLowerCase();
    return message.contains('network') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('host lookup') ||
        message.contains('failed host lookup') ||
        message.contains('xmlhttprequest') ||
        message.contains('fetch');
  }

  Future<bool> _probeServerReachability(SessionController session) async {
    try {
      await DriverService(session.apiClient).pingServer();
      return true;
    } catch (error) {
      if (_looksLikeConnectivityIssue(error)) {
        return false;
      }
      return true;
    }
  }

  Future<void> _syncAutomaticAvailability(
    SessionController session, {
    bool forcePush = false,
  }) async {
    final targetOnline = _shouldBeOnline(session);
    if (_availabilitySyncInFlight) {
      return;
    }
    if (!forcePush && _lastPublishedOnline == targetOnline) {
      return;
    }

    _availabilitySyncInFlight = true;
    try {
      await DriverService(session.apiClient).setStatus(active: targetOnline);
      _lastPublishedOnline = targetOnline;
    } catch (error) {
      if (_looksLikeConnectivityIssue(error)) {
        _applyAutomaticAvailabilityState(session, hasInternet: false);
        _syncRealtimeSocket(session);
        return;
      }

      if (mounted) {
        setState(() => _statusMessage = ActionFeedback.messageOf(error));
      }
    } finally {
      _availabilitySyncInFlight = false;
    }
  }

  Future<void> _refreshAutomaticAvailability({
    bool probeNetwork = true,
    bool forcePush = false,
  }) async {
    if (!mounted) {
      return;
    }

    final session = context.read<SessionController>();
    final previousHasInternet = _hasInternet;
    if (!session.isAuthenticated) {
      _applyAutomaticAvailabilityState(session);
      _syncRealtimeSocket(session);
      return;
    }

    if (!_isAppForeground) {
      _applyAutomaticAvailabilityState(session, hasInternet: _hasInternet);
      _syncRealtimeSocket(session);
      return;
    }

    if (probeNetwork && _isAppForeground) {
      final hasInternet = await _probeServerReachability(session);
      if (!mounted) {
        return;
      }
      _applyAutomaticAvailabilityState(session, hasInternet: hasInternet);
    } else {
      _applyAutomaticAvailabilityState(session);
    }

    _syncRealtimeSocket(
      session,
      forceReconnect: forcePush || (!previousHasInternet && _hasInternet),
    );
    await _syncAutomaticAvailability(session, forcePush: forcePush);
  }

  void _startAutomaticAvailabilityLoop() {
    _availabilityTimer?.cancel();
    _availabilityTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) {
        return;
      }
      unawaited(_refreshAutomaticAvailability());
    });
  }

  Future<void> _logoutDriver() async {
    final session = context.read<SessionController>();
    _realtimeSocketService.disconnect();
    try {
      await DriverService(session.apiClient).setStatus(active: false);
      _lastPublishedOnline = false;
    } catch (_) {
      // Keep logout resilient even when the status endpoint cannot be reached.
    }
    await session.logout();
  }

  void _syncRealtimeSocket(
    SessionController session, {
    bool forceReconnect = false,
  }) {
    final token = session.token?.trim() ?? '';
    final shouldConnect = _shouldKeepRealtimeConnected(session);
    if (!shouldConnect || token.isEmpty) {
      _realtimeSocketService.disconnect();
      return;
    }
    if (!forceReconnect &&
        (_realtimeSocketService.isConnected ||
            _realtimeSocketService.hasActiveSocket)) {
      return;
    }

    _realtimeNotificationSubscription?.cancel();
    _realtimeNotificationSubscription =
        _realtimeSocketService.notificationCreatedStream.listen(
      _handleRealtimeSocketNotification,
    );
    _realtimeSocketService.connect(
      apiBaseUrl: session.apiClient.baseUrl,
      token: token,
    );
  }

  Future<void> _handleRealtimeSocketNotification(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }

    final notification = NotificationModel.fromJson(event);
    if (notification.id.isEmpty) {
      return;
    }

    final alreadyKnown = _knownNotificationIds.contains(notification.id) ||
        _notifications.any((item) => item.id == notification.id);
    final applied = _applyRealtimeDriverNotification(notification);
    _knownNotificationIds = {..._knownNotificationIds, notification.id};
    _realtimePrimed = true;

    if (!applied) {
      await _refreshFromSocketEvent();
      return;
    }

    if (!alreadyKnown) {
      _showDriverRealtimeSnackBar(notification);
    }
  }

  Future<void> _refreshFromSocketEvent() async {
    if (!mounted || _silentRefreshActive) {
      return;
    }
    _silentRefreshActive = true;
    try {
      await _load(silent: true);
    } finally {
      _silentRefreshActive = false;
    }
  }

  Future<void> _load({bool silent = false}) async {
    final loadGeneration = ++_loadGeneration;
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    final notificationService = NotificationService(session.apiClient);
    final routeService = RouteService(session.apiClient);
    final routePreviewCache = RoutePreviewCache();
    final driverService = DriverService(session.apiClient);
    final stopAlertService = StopAlertService(session.apiClient);
    final rideSessionService = RideSessionService(session.apiClient);

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final initialResults = await Future.wait<dynamic>([
        tripService.getMyTrips(useCache: false),
        notificationService.getMine(useCache: false),
        routeService.getRoutes(useCache: false),
        driverService.getProfile(),
      ]);

      final trips = initialResults[0] as List<TripSession>;
      final notifications = initialResults[1] as List<NotificationModel>;
      final routes = initialResults[2] as List<RouteSummaryModel>;
      final driverProfile = initialResults[3] as Map<String, dynamic>;
      final assignedRouteId = _readAssignedRouteId(driverProfile);
      final driverStatus = driverProfile['status']?.toString().toLowerCase();
      final nextFocus = _resolveNextFocusId(trips);
      final focusedTrips = nextFocus == null || nextFocus.isEmpty
          ? const <TripSession>[]
          : trips.where((trip) => trip.id == nextFocus).toList(growable: false);
      final initialRouteIds = <String>{
        if (assignedRouteId != null && assignedRouteId.isNotEmpty)
          assignedRouteId,
        for (final trip in focusedTrips) trip.routeId,
      };
      final cachedRoutePreviewPoints = await _loadRoutePreviewPoints(
        routes: routes,
        routeIds: initialRouteIds,
        routePreviewCache: routePreviewCache,
      );
      final focusedHydration = await _loadTripOperationalData(
        trips: focusedTrips,
        driverService: driverService,
        stopAlertService: stopAlertService,
        rideSessionService: rideSessionService,
      );

      if (!mounted || loadGeneration != _loadGeneration) return;
      setState(() {
        _trips = trips;
        _notifications = notifications;
        _routes = routes;
        _cachedRoutePreviewPoints = cachedRoutePreviewPoints;
        _assignedRouteId = assignedRouteId;
        if (driverStatus == 'active' || driverStatus == 'inactive') {
          _isOnline = driverStatus == 'active';
          _lastPublishedOnline = _isOnline;
        }
        _tripRequests = focusedHydration.requestsByTrip;
        _tripAlerts = focusedHydration.alertsByTrip;
        _tripRides = focusedHydration.ridesByTrip;
        _focusedTripId =
            (nextFocus == null || nextFocus.isEmpty) ? null : nextFocus;
        _manualOnboardAdjustments = {
          for (final trip in trips)
            trip.id: _manualOnboardAdjustments[trip.id] ?? 0,
        };
      });
      _applyAutomaticAvailabilityState(session, hasInternet: true);
      unawaited(_syncAutomaticAvailability(session));
      _handleRealtimeDriverUpdates(
        notifications: notifications,
        alertsByTrip: focusedHydration.alertsByTrip,
        silent: silent,
      );
      if (!silent) {
        unawaited(
          _hydrateRemainingDriverData(
            loadGeneration: loadGeneration,
            trips: trips,
            routes: routes,
            assignedRouteId: assignedRouteId,
            focusedTripId: nextFocus,
            routePreviewCache: routePreviewCache,
            driverService: driverService,
            stopAlertService: stopAlertService,
            rideSessionService: rideSessionService,
          ),
        );
      }
    } catch (error) {
      if (_looksLikeConnectivityIssue(error)) {
        _applyAutomaticAvailabilityState(session, hasInternet: false);
      }
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  String? _resolveNextFocusId(List<TripSession> trips) {
    if (trips.any((trip) => trip.id == _focusedTripId)) {
      return _focusedTripId;
    }
    for (final trip in trips) {
      if (trip.status == 'active') {
        return trip.id;
      }
    }
    return trips.isEmpty ? null : trips.first.id;
  }

  Future<Map<String, List<LatLng>>> _loadRoutePreviewPoints({
    required List<RouteSummaryModel> routes,
    required Set<String> routeIds,
    required RoutePreviewCache routePreviewCache,
  }) async {
    final relevantRoutes = routes
        .where((route) => routeIds.contains(route.id))
        .toList(growable: false);
    if (relevantRoutes.isEmpty) {
      return const <String, List<LatLng>>{};
    }

    final entries = await Future.wait(
      relevantRoutes.map((route) async {
        final cachedPoints = await routePreviewCache.loadPreview(
          routeId: route.id,
          routeCode: route.code,
        );
        return MapEntry(route.id, cachedPoints);
      }),
    );

    return {
      for (final entry in entries)
        if (entry.value.length >= 2) entry.key: entry.value,
    };
  }

  Future<_DriverTripHydration> _loadTripOperationalData({
    required List<TripSession> trips,
    required DriverService driverService,
    required StopAlertService stopAlertService,
    required RideSessionService rideSessionService,
  }) async {
    if (trips.isEmpty) {
      return const _DriverTripHydration();
    }

    final requestEntries = await Future.wait(
      trips.map((trip) async => MapEntry(
            trip.id,
            await driverService.getRequestsForTrip(
              trip.id,
              useCache: false,
            ),
          )),
    );
    final alertEntries = await Future.wait(
      trips.map((trip) async => MapEntry(
            trip.id,
            await stopAlertService.getTripStopAlerts(
              trip.id,
              useCache: false,
            ),
          )),
    );
    final rideEntries = await Future.wait(
      trips.map((trip) async => MapEntry(
            trip.id,
            await rideSessionService.getTripRides(
              trip.id,
              useCache: false,
            ),
          )),
    );

    return _DriverTripHydration(
      requestsByTrip: {
        for (final entry in requestEntries) entry.key: entry.value,
      },
      alertsByTrip: {
        for (final entry in alertEntries) entry.key: entry.value,
      },
      ridesByTrip: {
        for (final entry in rideEntries) entry.key: entry.value,
      },
    );
  }

  Future<void> _hydrateRemainingDriverData({
    required int loadGeneration,
    required List<TripSession> trips,
    required List<RouteSummaryModel> routes,
    required String? assignedRouteId,
    required String? focusedTripId,
    required RoutePreviewCache routePreviewCache,
    required DriverService driverService,
    required StopAlertService stopAlertService,
    required RideSessionService rideSessionService,
  }) async {
    final remainingTrips =
        trips.where((trip) => trip.id != focusedTripId).toList(growable: false);
    final hydratedRouteIds = <String>{
      if (assignedRouteId != null && assignedRouteId.isNotEmpty)
        assignedRouteId,
      if (focusedTripId != null && focusedTripId.isNotEmpty)
        ...trips
            .where((trip) => trip.id == focusedTripId)
            .map((trip) => trip.routeId),
    };
    final remainingRouteIds = routes
        .map((route) => route.id)
        .where((routeId) => !hydratedRouteIds.contains(routeId))
        .toSet();

    final previewFuture = _loadRoutePreviewPoints(
      routes: routes,
      routeIds: remainingRouteIds,
      routePreviewCache: routePreviewCache,
    );
    final tripFuture = _loadTripOperationalData(
      trips: remainingTrips,
      driverService: driverService,
      stopAlertService: stopAlertService,
      rideSessionService: rideSessionService,
    );

    final remainingPreviews = await previewFuture;
    final remainingHydration = await tripFuture;

    if (!mounted || loadGeneration != _loadGeneration) {
      return;
    }

    final backgroundActiveAlertIds = remainingHydration.alertsByTrip.values
        .expand((items) => items)
        .where((alert) => _activeAlertStatuses.contains(alert.status))
        .map((alert) => alert.id)
        .toSet();

    setState(() {
      _cachedRoutePreviewPoints = {
        ..._cachedRoutePreviewPoints,
        ...remainingPreviews,
      };
      _tripRequests = {
        ..._tripRequests,
        ...remainingHydration.requestsByTrip,
      };
      _tripAlerts = {
        ..._tripAlerts,
        ...remainingHydration.alertsByTrip,
      };
      _tripRides = {
        ..._tripRides,
        ...remainingHydration.ridesByTrip,
      };
      _knownActiveStopAlertIds = {
        ..._knownActiveStopAlertIds,
        ...backgroundActiveAlertIds,
      };
    });
  }

  void _startLiveRefreshLoop() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted ||
          _silentRefreshActive ||
          _realtimeSocketService.isConnected) {
        return;
      }
      _silentRefreshActive = true;
      try {
        await _load(silent: true);
      } finally {
        _silentRefreshActive = false;
      }
    });
  }

  void _handleRealtimeDriverUpdates({
    required List<NotificationModel> notifications,
    required Map<String, List<StopAlertModel>> alertsByTrip,
    required bool silent,
  }) {
    final notificationIds = notifications.map((item) => item.id).toSet();
    final activeAlertIds = alertsByTrip.values
        .expand((items) => items)
        .where((alert) => _activeAlertStatuses.contains(alert.status))
        .map((alert) => alert.id)
        .toSet();

    if (!_realtimePrimed) {
      _knownNotificationIds = notificationIds;
      _knownActiveStopAlertIds = activeAlertIds;
      _realtimePrimed = true;
      return;
    }

    final newNotifications = notifications
        .where((item) => !_knownNotificationIds.contains(item.id))
        .toList(growable: false);
    final newActiveAlerts = alertsByTrip.values
        .expand((items) => items)
        .where(
          (alert) =>
              _activeAlertStatuses.contains(alert.status) &&
              !_knownActiveStopAlertIds.contains(alert.id),
        )
        .toList(growable: false);

    _knownNotificationIds = notificationIds;
    _knownActiveStopAlertIds = activeAlertIds;

    if (!silent || !mounted) {
      return;
    }
    if (newActiveAlerts.isEmpty && newNotifications.isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (newActiveAlerts.isNotEmpty) {
      final firstAlert = newActiveAlerts.first;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            newActiveAlerts.length == 1
                ? 'New stop alert: ${firstAlert.stopRef}'
                : '${newActiveAlerts.length} new passenger stop alerts received.',
          ),
        ),
      );
      return;
    }

    final firstNotification = newNotifications.first;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          newNotifications.length == 1
              ? '${firstNotification.title}: ${firstNotification.body}'
              : '${newNotifications.length} new driver notifications received.',
        ),
      ),
    );
  }

  bool _applyRealtimeDriverNotification(NotificationModel notification) {
    var needsFallback = false;

    setState(() {
      _notifications = _upsertNotificationList(_notifications, notification);

      switch (notification.type) {
        case 'pickup_request_created':
          final request = _readDriverPickupRequest(notification.payload);
          if (request == null) {
            needsFallback = true;
            return;
          }
          _tripRequests = _upsertTripRequests(_tripRequests, request);
          break;
        case 'stop_alert_created':
          final alert = _readDriverStopAlert(notification.payload);
          if (alert == null) {
            needsFallback = true;
            return;
          }
          _tripAlerts = _upsertTripAlerts(_tripAlerts, alert);
          if (_activeAlertStatuses.contains(alert.status)) {
            _knownActiveStopAlertIds = {..._knownActiveStopAlertIds, alert.id};
          }
          break;
      }
    });

    return !needsFallback;
  }

  List<NotificationModel> _upsertNotificationList(
    List<NotificationModel> notifications,
    NotificationModel notification,
  ) {
    final next = List<NotificationModel>.from(notifications);
    final existingIndex = next.indexWhere((item) => item.id == notification.id);
    if (existingIndex >= 0) {
      next[existingIndex] = notification;
      return next;
    }
    next.insert(0, notification);
    return next;
  }

  Map<String, List<PickupRequestModel>> _upsertTripRequests(
    Map<String, List<PickupRequestModel>> source,
    PickupRequestModel request,
  ) {
    final next = <String, List<PickupRequestModel>>{
      for (final entry in source.entries) entry.key: List.of(entry.value),
    };
    final tripRequests = List<PickupRequestModel>.from(
      next[request.tripSessionId] ?? const <PickupRequestModel>[],
    );
    final existingIndex =
        tripRequests.indexWhere((item) => item.id == request.id);
    if (existingIndex >= 0) {
      tripRequests[existingIndex] = request;
    } else {
      tripRequests.insert(0, request);
    }
    tripRequests.sort(_comparePickupRequests);
    next[request.tripSessionId] = tripRequests;
    return next;
  }

  Map<String, List<StopAlertModel>> _upsertTripAlerts(
    Map<String, List<StopAlertModel>> source,
    StopAlertModel alert,
  ) {
    final next = <String, List<StopAlertModel>>{
      for (final entry in source.entries) entry.key: List.of(entry.value),
    };
    final tripAlerts = List<StopAlertModel>.from(
      next[alert.tripSessionId] ?? const <StopAlertModel>[],
    );
    final existingIndex = tripAlerts.indexWhere((item) => item.id == alert.id);
    if (existingIndex >= 0) {
      tripAlerts[existingIndex] = alert;
    } else {
      tripAlerts.insert(0, alert);
    }
    tripAlerts.sort(_compareStopAlerts);
    next[alert.tripSessionId] = tripAlerts;
    return next;
  }

  PickupRequestModel? _readDriverPickupRequest(Map<String, dynamic> payload) {
    final raw = payload['request'];
    if (raw is Map<String, dynamic>) {
      return PickupRequestModel.fromJson(raw);
    }
    if (raw is Map) {
      return PickupRequestModel.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  StopAlertModel? _readDriverStopAlert(Map<String, dynamic> payload) {
    final raw = payload['stopAlert'];
    if (raw is Map<String, dynamic>) {
      return StopAlertModel.fromJson(raw);
    }
    if (raw is Map) {
      return StopAlertModel.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  int _comparePickupRequests(PickupRequestModel a, PickupRequestModel b) {
    final statusComparison = a.status.compareTo(b.status);
    if (statusComparison != 0) {
      return statusComparison;
    }
    return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
  }

  int _compareStopAlerts(StopAlertModel a, StopAlertModel b) {
    return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
  }

  void _showDriverRealtimeSnackBar(NotificationModel notification) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (notification.type == 'stop_alert_created') {
      final alert = _readDriverStopAlert(notification.payload);
      final message = alert == null
          ? '${notification.title}: ${notification.body}'
          : 'New stop alert: ${alert.stopRef}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('${notification.title}: ${notification.body}')),
    );
  }

  Future<void> _runDriverAction({
    required String loadingMessage,
    required String successMessage,
    required Future<dynamic> Function() action,
    bool reloadAfter = true,
  }) async {
    await ActionFeedback.run<void>(
      context: context,
      loadingMessage: loadingMessage,
      successMessage: successMessage,
      action: () async {
        await action();
        if (reloadAfter) {
          await _load();
        }
      },
      onSuccess: (_) async {
        if (!mounted) return;
        setState(() => _statusMessage = successMessage);
      },
      onError: (error) async {
        if (!mounted) return;
        setState(() => _statusMessage = ActionFeedback.messageOf(error));
      },
    );
  }

  Future<void> _startTrip(String tripId) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Starting trip...',
      successMessage:
          'Trip started. The driver map is now ready for live pickup handling.',
      action: () => tripService.startTrip(tripId),
    );
  }

  Future<void> _endTrip(String tripId) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Ending trip...',
      successMessage: 'Trip ended. Ride sessions and alerts were closed.',
      action: () => tripService.endTrip(tripId),
    );
  }

  Future<void> _toggleAccept(String tripId, bool accept) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    await _runDriverAction(
      loadingMessage: accept
          ? 'Reopening pickup requests...'
          : 'Pausing pickup requests...',
      successMessage:
          accept ? 'Pickup requests reopened.' : 'Pickup requests paused.',
      action: () => tripService.setTripAvailability(tripId, accept),
    );
  }

  Future<void> _acknowledgeRequest(String requestId) async {
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Acknowledging pickup request...',
      successMessage: 'Pickup request acknowledged.',
      action: () => driverService.acknowledgeRequest(requestId),
    );
  }

  Future<void> _completeRequest(PickupRequestModel request) async {
    final confirmed = await _showPickupCompletionConfirmation(request);
    if (confirmed != true || !mounted) {
      return;
    }
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Confirming pickup...',
      successMessage: 'Pickup confirmed. The passenger booking was updated.',
      action: () => driverService.completeRequest(request.id),
    );
  }

  Future<bool> _showPickupCompletionConfirmation(
    PickupRequestModel request,
  ) async {
    final stopLabel = request.stopRef ?? 'this pickup point';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm pickup'),
        content: Text(
          'Confirm that the passenger has been picked up at $stopLabel. This will also update the passenger app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm pickup'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    final session = context.read<SessionController>();
    final alertService = StopAlertService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Acknowledging stop alert...',
      successMessage: 'Destination alert acknowledged.',
      action: () => alertService.acknowledgeStopAlert(alertId),
    );
  }

  Future<void> _completeUnloadAlert(StopAlertModel alert) async {
    final session = context.read<SessionController>();
    final rideService = RideSessionService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Closing ride session...',
      successMessage:
          'Passenger unloaded near ${alert.stopRef}. Ride session closed.',
      action: () => rideService.completeRideSession(alert.rideSessionId),
    );
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
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 450),
        () => _publishVehicleLocation(),
      ),
    );
  }

  Future<void> _publishVehicleLocation() async {
    if (!mounted) {
      return;
    }

    if (!_isAppForeground) {
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
        _setStatusMessage(
            'Enable device location service to share jeepney location.');
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final next = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      if (_vehicleLocation == null ||
          (next.latitude - _vehicleLocation!.latitude).abs() > 0.00008 ||
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
      await driverService.updateLocation(
          lat: next.latitude, lng: next.longitude);
      if (!_hasInternet) {
        _applyAutomaticAvailabilityState(session, hasInternet: true);
        unawaited(_syncAutomaticAvailability(session, forcePush: true));
      }
      if (_statusMessage != null &&
          _statusMessage!.toLowerCase().contains('location')) {
        _setStatusMessage(null);
      }
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

  void _setStatusMessage(String? message) {
    if (!mounted) return;
    if (_statusMessage == message) {
      return;
    }
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

  void _syncDriverMapCamera(LatLng target) {
    final previous = _lastDriverMapCenter;
    if (previous != null &&
        (previous.latitude - target.latitude).abs() < 0.00008 &&
        (previous.longitude - target.longitude).abs() < 0.00008) {
      return;
    }

    _lastDriverMapCenter = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final zoom = _driverMapController.camera.zoom == 0
          ? 14.2
          : _driverMapController.camera.zoom;
      _driverMapController.move(target, zoom);
    });
  }

  String? _readAssignedRouteId(Map<String, dynamic> profile) {
    final assignedRoute = profile['assignedRouteId'];
    if (assignedRoute is Map<String, dynamic>) {
      final id = assignedRoute['_id']?.toString().trim();
      return (id == null || id.isEmpty) ? null : id;
    }
    final id = assignedRoute?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
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
    final effectiveRoute = _effectiveRouteSummaryForTrip(trip);
    if (effectiveRoute != null) {
      return effectiveRoute.label;
    }
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
            onPressed: _logoutDriver,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bodyContent = _tabIndex != 0
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: _buildActiveTab(
                    focusedTrip: focusedTrip,
                    focusedRequests: focusedRequests,
                    focusedAlerts: focusedAlerts,
                    focusedRides: focusedRides,
                  ),
                )
              : SizedBox.expand(
                  child: _buildPersistentDriverSurface(
                    session: session,
                    focusedTrip: focusedTrip,
                    focusedRequests: focusedRequests,
                    focusedAlerts: focusedAlerts,
                    focusedRides: focusedRides,
                    mapHeight: constraints.maxHeight.toDouble(),
                  ),
                );

          return Stack(
            children: [
              Positioned.fill(child: bodyContent),
              if (_loading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(),
                ),
            ],
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
    required this.availabilityNote,
  });

  final String name;
  final String routeLabel;
  final bool isOnline;
  final String availabilityNote;

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
                    child: _DriverStatusChip(
                      icon: Icons.autorenew_rounded,
                      label: 'Automatic',
                      selectedBackground: const Color(0xFFE2EDE7),
                      selectedForeground: const Color(0xFF245245),
                    ),
                  ),
                  Expanded(
                    child: _DriverStatusChip(
                      icon: isOnline ? Icons.wifi_tethering : Icons.cloud_off,
                      label: isOnline ? 'Online' : 'Offline',
                      selectedBackground: isOnline
                          ? const Color(0xFFD8F3E6)
                          : const Color(0xFFE9E2D4),
                      selectedForeground: isOnline
                          ? const Color(0xFF13623E)
                          : const Color(0xFF7A4E16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              availabilityNote,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverStatusChip extends StatelessWidget {
  const _DriverStatusChip({
    required this.icon,
    required this.label,
    required this.selectedBackground,
    required this.selectedForeground,
  });

  final IconData icon;
  final String label;
  final Color selectedBackground;
  final Color selectedForeground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selectedBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: selectedForeground,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selectedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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

class _DriveMapPanel extends StatelessWidget {
  const _DriveMapPanel({
    required this.mapController,
    required this.trip,
    required this.cameraTarget,
    required this.driverName,
    required this.statusMessage,
    required this.availabilityNote,
    required this.isOnline,
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

  final MapController mapController;
  final TripSession? trip;
  final LatLng cameraTarget;
  final String driverName;
  final String? statusMessage;
  final String availabilityNote;
  final bool isOnline;
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

  void _openControlSheet(
      BuildContext context, bool hasTrip, bool isTripActive) {
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
                      availabilityNote: availabilityNote,
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
                              value:
                                  trip == null ? 'No active route' : routeLabel,
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
                  mapController: mapController,
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
                  onTap: () =>
                      _openControlSheet(context, hasTrip, isTripActive),
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

class _DriverTripHydration {
  const _DriverTripHydration({
    this.requestsByTrip = const <String, List<PickupRequestModel>>{},
    this.alertsByTrip = const <String, List<StopAlertModel>>{},
    this.ridesByTrip = const <String, List<RideSessionModel>>{},
  });

  final Map<String, List<PickupRequestModel>> requestsByTrip;
  final Map<String, List<StopAlertModel>> alertsByTrip;
  final Map<String, List<RideSessionModel>> ridesByTrip;
}
