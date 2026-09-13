import '../../core/utils/automation_location.dart';
import '../../widgets/legal_pages.dart';
import 'dart:async';
import '../../widgets/terminal_loading_clock.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/operations/notification.dart';
import '../../models/operations/announcement.dart';
import '../../models/operations/pickup_request.dart';
import '../../models/operations/ride_session.dart';
import '../../models/passenger/passenger_profile.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/passenger_jeep_eta.dart';
import '../../models/trip/trip_session.dart';
import '../../services/notification_service.dart';
import '../../services/announcement_service.dart';
import '../../services/passenger_service.dart';
import '../../services/passenger_route_vehicle_batch.dart';
import '../../services/passenger_refresh_coordinator.dart';
import '../../services/passenger_vehicle_reconciliation.dart';
import '../../services/passenger_profile_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/announcement_card.dart';
import '../../widgets/passenger_home_dashboard_widgets.dart';
import '../../widgets/status_badge.dart';
import '../support/passenger_support_screen.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen>
    with WidgetsBindingObserver {
  static const LatLng _defaultMapCenter = LatLng(14.6091, 121.0223);
  static const Distance _distance = Distance();
  static const double _pickupPinToleranceMeters = 300;
  static const double _unloadPinToleranceMeters = 5;
  static const double _pickupFromCurrentLocationMeters = 50;
  static const double _passengerGpsJitterMeters = 12;
  static const double _maxPassengerGpsAccuracyMeters = 35;
  static const double _tripMarkerJitterMeters = 1;
  static const double _tripMarkerSnapThresholdMeters = 90;
  static const double _tripMarkerSnapSpeedAllowanceMetersPerSecond = 35;
  static const double _autoUnloadDistanceMeters = 120;
  static const int _autoUnloadConsecutiveOutsideChecks = 3;
  static const Duration _tripMarkerAnimationTick = Duration(milliseconds: 33);
  static const Duration _tripMarkerAnimationDefaultDuration =
      Duration(milliseconds: 900);
  static const Duration _tripMarkerAnimationMinDuration =
      Duration(milliseconds: 550);
  static const Duration _tripMarkerAnimationMaxDuration =
      Duration(milliseconds: 1400);
  static const Duration _tripRealtimeStaleAfter = Duration(seconds: 8);
  static const Duration _liveRefreshInterval = Duration(seconds: 5);
  static const Duration _backgroundLocationRefreshInterval =
      Duration(seconds: 10);
  static const Duration _passengerLocationReportInterval = Duration(seconds: 5);
  static const double _passengerLocationReportDistanceMeters = 8;
  static const Duration _metadataRefreshInterval = Duration(seconds: 45);
  static const Duration _socketRefreshThrottle = Duration(seconds: 4);
  static const double _tripProjectionHandoffThreshold = 0.88;
  static const Duration _tripProjectionMaxDuration = Duration(seconds: 1);
  static const double _tripProjectionMaxDistanceMeters = 8;
  static const double _tripProjectionMinSpeedMetersPerSecond = 0.8;
  static const int _selectedRouteVisibleTripLimit = 3;
  static const double _selectedRoutePassedAnchorMeters = 100;
  static const Duration _passengerMapFollowPause = Duration(seconds: 8);
  static const Duration _passengerMapFollowThrottle =
      Duration(milliseconds: 150);
  static const Duration _passengerEtaRefreshInterval = Duration(seconds: 30);
  static const Duration _passengerEtaMovementRefreshFloor =
      Duration(seconds: 10);
  static const double _passengerEtaMovementRefreshMeters = 100;
  static const double _passengerMapFollowLerpFactor = 0.22;
  static const double _passengerMapFollowJitterMeters = 10;
  static const double _passengerMapFollowSnapMeters = 45;
  static const double _sheetCollapsedSize = 0.09;
  static const double _sheetPeekSize = 0.38;
  static const double _sheetExpandedSize = 0.90;

  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  List<PickupRequestModel> _requests = [];
  List<RideSessionModel> _rides = [];
  List<NotificationModel> _notifications = [];
  List<AnnouncementModel> _announcements = [];
  String? _selectedTripId;
  String? _selectedRouteId;
  LatLng? _currentPassengerLocation;
  DateTime? _currentPassengerLocationAt;
  LatLng? _draftPickupPoint;
  LatLng? _draftUnloadPoint;
  String? _draftPickupLabel;
  String? _draftUnloadLabel;
  _PassengerMapSelectionMode _mapSelectionMode =
      _PassengerMapSelectionMode.pickup;
  bool _loading = false;
  String? _statusMessage;
  String? _syncMessage;
  Timer? _liveRefreshTimer;
  Timer? _passengerEtaTimer;
  Timer? _tripMarkerAnimationTimer;
  StreamSubscription<Map<String, dynamic>>? _realtimeNotificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeOperationsSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeLocationSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeVehicleBatchSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeAnnouncementSubscription;
  StreamSubscription<RealtimeSocketLifecycleEvent>?
      _realtimeLifecycleSubscription;
  bool _silentRefreshActive = false;
  bool _realtimePrimed = false;
  bool _locatingPassenger = false;
  Future<LatLng?>? _passengerLocationRequest;
  bool _passengerLocationReportInFlight = false;
  DateTime? _lastPassengerLocationReportedAt;
  LatLng? _lastPassengerLocationReported;
  bool _passengerSheetCollapsed = false;
  bool _showingCachedPassengerSnapshot = false;
  _PassengerBookingMode _bookingMode = _PassengerBookingMode.roadside;
  int _outsideAutoUnloadWindowCount = 0;
  DateTime? _autoUnloadPromptedAt;
  int _pickupLabelLookupSerial = 0;
  int _unloadLabelLookupSerial = 0;
  String? _autoUnloadWindowRideId;
  DateTime? _lastPassengerSyncAt;
  DateTime? _lastSocketRefreshAt;
  DateTime? _lastAnnouncementRefreshAttemptAt;
  DateTime? _lastRouteMetadataRefreshAt;
  String? _lastMapPromptMessage;
  Set<String> _knownNotificationIds = <String>{};
  final Set<String> _destinationReminderRideIds = <String>{};
  final MapController _passengerMapController = MapController();
  bool _passengerMapReady = false;
  LatLng? _lastPassengerMapCenter;
  double? _lastPassengerMapZoom;
  DateTime? _lastPassengerMapFollowAt;
  DateTime? _passengerMapFollowPausedUntil;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  AnnouncementFeedController? _announcementFeedController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, _TripMarkerAnimation> _tripMarkerAnimations =
      <String, _TripMarkerAnimation>{};
  final Map<String, _TripVehicleMotionState> _tripVehicleStates =
      <String, _TripVehicleMotionState>{};
  final PassengerRouteVehicleBatchReconciler _routeVehicleBatchReconciler =
      PassengerRouteVehicleBatchReconciler();
  final PassengerRefreshCoordinator _refreshCoordinator =
      PassengerRefreshCoordinator();
  final PassengerRealtimeReconciliationGate _realtimeReconciliationGate =
      PassengerRealtimeReconciliationGate();
  Future<void>? _socketReconciliationOperation;
  bool _socketReconciliationQueued = false;
  int _dashboardLoadGeneration = 0;
  PassengerJeepEta? _selectedJeepEta;
  String? _passengerEtaTripId;
  String? _passengerEtaError;
  bool _passengerEtaLoading = false;
  bool _passengerEtaRequestInFlight = false;
  int _passengerEtaRequestSerial = 0;
  DateTime? _passengerEtaLastRequestedAt;
  LatLng? _passengerEtaLastOrigin;
  OverlayEntry? _mapPromptOverlayEntry;
  Timer? _mapPromptOverlayTimer;

  TripSession? get _selectedTrip {
    final selectedRoute = _selectedRoute;
    final selectedRouteId = _selectedRouteId;
    final onboardTrip = _onboardedTripForCamera();
    final selectedTripId = _selectedTripId;
    if (selectedTripId != null && selectedTripId.isNotEmpty) {
      final trip = _tripById(selectedTripId);
      if (trip != null) {
        final keepSelectedTrip = selectedRoute == null ||
            selectedRouteId == null ||
            selectedRouteId.isEmpty ||
            !_tripMatchesRoute(trip, selectedRoute) ||
            trip.id == onboardTrip?.id ||
            _isTripEligibleForSelectedRouteDisplay(
              trip,
              selectedRoute,
            );
        if (keepSelectedTrip) {
          return trip;
        }
      }
    }
    if (onboardTrip != null &&
        selectedRoute != null &&
        _tripMatchesRoute(onboardTrip, selectedRoute)) {
      return onboardTrip;
    }
    if (selectedRouteId != null && selectedRouteId.isNotEmpty) {
      final candidates = _selectedRouteDisplayTrips(selectedRouteId);
      if (candidates.isNotEmpty) {
        return candidates.first;
      }
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  RouteSummaryModel? get _selectedRoute {
    final selectedRouteId = _selectedRouteId;
    if (selectedRouteId != null && selectedRouteId.isNotEmpty) {
      for (final route in _routes) {
        if (route.id == selectedRouteId) {
          return route;
        }
      }
    }
    for (final route in _routes) {
      if (route.status == 'active') {
        return route;
      }
    }
    return _routes.isEmpty ? null : _routes.first;
  }

  RideSessionModel? get _activeRide {
    final selectedTripId = _selectedTripId;
    if (selectedTripId != null && selectedTripId.isNotEmpty) {
      for (final ride in _rides) {
        if (ride.tripSessionId == selectedTripId && ride.status == 'onboard') {
          return ride;
        }
      }
    }
    for (final ride in _rides) {
      if (ride.status == 'onboard') {
        return ride;
      }
    }
    return null;
  }

  RideSessionModel? get _displayRide {
    final selectedTripId = _selectedTripId;
    if (selectedTripId != null && selectedTripId.isNotEmpty) {
      for (final ride in _rides) {
        if (ride.tripSessionId == selectedTripId && ride.status == 'onboard') {
          return ride;
        }
      }
      for (final ride in _rides) {
        if (ride.tripSessionId == selectedTripId && ride.status == 'waiting') {
          return ride;
        }
      }
      for (final ride in _rides) {
        if (ride.tripSessionId == selectedTripId &&
            ride.status == 'completed') {
          return ride;
        }
      }
    }
    for (final ride in _rides) {
      if (ride.status == 'onboard') {
        return ride;
      }
    }
    for (final ride in _rides) {
      if (ride.status == 'waiting') {
        return ride;
      }
    }
    for (final ride in _rides) {
      if (ride.status == 'completed') {
        return ride;
      }
    }
    return null;
  }

  PickupRequestModel? get _selectedTripBooking {
    final selectedTripId = _selectedTripId;
    if (selectedTripId != null && selectedTripId.isNotEmpty) {
      for (final request in _requests) {
        if (request.tripSessionId == selectedTripId &&
            (request.status == 'pending' || request.status == 'acknowledged')) {
          return request;
        }
      }
    }

    final selectedRouteId = _selectedRouteId;
    if (selectedRouteId != null && selectedRouteId.isNotEmpty) {
      for (final request in _requests) {
        if (request.routeId == selectedRouteId &&
            (request.status == 'pending' || request.status == 'acknowledged')) {
          return request;
        }
      }
    }

    for (final request in _requests) {
      if (request.status == 'pending' || request.status == 'acknowledged') {
        return request;
      }
    }
    return null;
  }

  Future<void> _load({
    bool silent = false,
    bool preferFresh = false,
  }) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    final passengerService = PassengerService(session.apiClient);
    final notificationService = NotificationService(session.apiClient);
    final routeService = RouteService(session.apiClient);
    final requestStartedAt = DateTime.now();
    final loadGeneration = ++_dashboardLoadGeneration;
    final previousRouteId = _selectedRouteId;

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final shouldUseLiveCache = !preferFresh;
      _refreshAnnouncementsIfDue(useCache: shouldUseLiveCache);
      final results = await Future.wait<dynamic>([
        tripService.getActiveTrips(useCache: shouldUseLiveCache),
        passengerService.getMyPickupRequests(useCache: shouldUseLiveCache),
        passengerService.getMyRides(useCache: shouldUseLiveCache),
        notificationService.getMine(useCache: shouldUseLiveCache),
        routeService.getRoutes(useCache: true),
      ]);

      var trips = results[0] as List<TripSession>;
      final requests = results[1] as List<PickupRequestModel>;
      final rides = results[2] as List<RideSessionModel>;
      final notifications = results[3] as List<NotificationModel>;
      final routes = results[4] as List<RouteSummaryModel>;

      if (trips.isEmpty) {
        trips = await tripService.getActiveTrips(useCache: false);
      }
      final usedStaleCache = session.apiClient.recentTelemetry.any(
        (entry) =>
            entry.occurredAt.isAfter(requestStartedAt) && entry.usedStaleCache,
      );

      final selectableRoutes = routes
          .where((route) => route.status == 'active')
          .toList(growable: false);
      final nextRouteId = _selectRouteId(
        routes: selectableRoutes.isEmpty ? routes : selectableRoutes,
        trips: trips,
        requests: requests,
        rides: rides,
      );
      final nextTripId = _selectTripIdForRoute(
        trips: trips,
        requests: requests,
        rides: rides,
        routeId: nextRouteId,
        anchor: _draftPickupPoint,
      );

      if (!mounted || loadGeneration != _dashboardLoadGeneration) return;
      setState(() {
        if (_passengerEtaTripId != null && _passengerEtaTripId != nextTripId) {
          _clearPassengerEtaSelection();
        }
        _trips = trips;
        for (final request in requests) {
          _requests = _upsertPickupRequests(_requests, request);
        }
        for (final ride in rides) {
          _rides = _upsertRideSessions(_rides, ride);
        }
        _notifications = notifications;
        _routes = routes;
        _selectedTripId = nextTripId;
        _selectedRouteId = nextRouteId;
        _lastPassengerSyncAt = DateTime.now();
        _lastRouteMetadataRefreshAt = DateTime.now();
        _showingCachedPassengerSnapshot = usedStaleCache;
        _syncMessage = usedStaleCache
            ? 'Showing cached trip data while reconnecting.'
            : null;
      });
      _reconcileTripVehicleStates(trips);
      _pruneTripMarkerAnimations();
      _syncRealtimeRouteSubscription(
        previousRouteId: previousRouteId,
        nextRouteId: nextRouteId,
      );
      _syncPassengerSelectedTripCamera(force: true);
      _handleRealtimePassengerUpdates(
        notifications: notifications,
        silent: silent,
      );
      if (_shouldReportPassengerLocationForRideAutomation) {
        unawaited(_ensureCurrentPassengerLocation(
          silent: true,
          forceRefresh: true,
          triggerAutoUnload: false,
        ));
      }
      unawaited(_maybeAutoUnloadWhenSeparated());
      unawaited(_maybeAutoHandleDestinationApproach());
    } catch (error) {
      setState(() {
        if (_trips.isEmpty && _routes.isEmpty) {
          _statusMessage = error.toString();
        } else {
          _syncMessage =
              'Network unavailable. Keeping the latest synced passenger snapshot on screen.';
          _showingCachedPassengerSnapshot = true;
        }
      });
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _startLiveRefreshLoop() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(_liveRefreshInterval, (_) async {
      if (!mounted || _silentRefreshActive) {
        return;
      }
      _silentRefreshActive = true;
      try {
        _ensureRealtimeSocketConnection();
        final locationTimestamp = _currentPassengerLocationAt;
        final shouldRefreshPassengerLocation = locationTimestamp == null ||
            DateTime.now().difference(locationTimestamp) >=
                (_shouldReportPassengerLocationForRideAutomation
                    ? _passengerLocationReportInterval
                    : _backgroundLocationRefreshInterval);
        if (shouldRefreshPassengerLocation) {
          await _ensureCurrentPassengerLocation(
            silent: true,
            forceRefresh: true,
          );
        }
        if (!_hasFreshRealtimeVehicleState()) {
          await _refreshTripsOnly(
            useCache: _realtimeSocketService.isConnected,
          );
        }
        if (_shouldRefreshPassengerMetadata()) {
          await _refreshPassengerMetadata(silent: true);
        }
        _refreshAnnouncementsIfDue();
      } finally {
        _silentRefreshActive = false;
      }
    });
  }

  Future<void> _refreshPassengerMetadata({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      _refreshAnnouncementsIfDue(useCache: true);
      final refreshes = <Future<void>>[
        _refreshBookings(useCache: false),
        _refreshNotifications(useCache: true, silent: silent),
      ];
      final routeRefreshAt = _lastRouteMetadataRefreshAt;
      if (routeRefreshAt == null ||
          DateTime.now().difference(routeRefreshAt) >=
              const Duration(minutes: 5)) {
        refreshes.add(_refreshRoutes(useCache: true));
      }
      await Future.wait(refreshes);
      if (mounted) {
        _lastPassengerSyncAt = DateTime.now();
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _refreshTripsOnly({
    required bool useCache,
    bool replacePending = false,
  }) async {
    final session = context.read<SessionController>();
    try {
      final result = await _refreshCoordinator.run<List<TripSession>>(
        PassengerRefreshDomain.trips,
        () => TripService(session.apiClient).getActiveTrips(useCache: useCache),
        replacePending: replacePending,
      );
      if (!mounted || !result.isCurrent) return false;
      final previousRouteId = _selectedRouteId;
      final nextTripId = _selectTripIdForRoute(
        trips: result.value,
        requests: _requests,
        rides: _rides,
        routeId: _selectedRouteId,
        anchor: _draftPickupPoint,
      );
      setState(() {
        if (_passengerEtaTripId != null && _passengerEtaTripId != nextTripId) {
          _clearPassengerEtaSelection();
        }
        _trips = result.value;
        _selectedTripId = nextTripId;
      });
      _reconcileTripVehicleStates(result.value);
      _pruneTripMarkerAnimations();
      _syncRealtimeRouteSubscription(
        previousRouteId: previousRouteId,
        nextRouteId: _selectedRouteId,
      );
      return true;
    } catch (_) {
      // Trip polling is best-effort; retain the last authoritative snapshot.
      return false;
    }
  }

  Future<void> _refreshBookings({
    required bool useCache,
    bool replacePending = false,
  }) async {
    final session = context.read<SessionController>();
    final service = PassengerService(session.apiClient);
    try {
      final result = await _refreshCoordinator.run<_PassengerBookingSnapshot>(
        PassengerRefreshDomain.bookings,
        () async {
          final values = await Future.wait<dynamic>([
            service.getMyPickupRequests(useCache: useCache),
            service.getMyRides(useCache: useCache),
          ]);
          return _PassengerBookingSnapshot(
            requests: values[0] as List<PickupRequestModel>,
            rides: values[1] as List<RideSessionModel>,
          );
        },
        replacePending: replacePending,
      );
      if (!mounted || !result.isCurrent) return;
      final previousRouteId = _selectedRouteId;
      final nextRouteId = _selectRouteId(
        routes: _routes,
        trips: _trips,
        requests: result.value.requests,
        rides: result.value.rides,
      );
      final nextTripId = _selectTripIdForRoute(
        trips: _trips,
        requests: result.value.requests,
        rides: result.value.rides,
        routeId: nextRouteId,
        anchor: _draftPickupPoint,
      );
      setState(() {
        for (final request in result.value.requests) {
          _requests = _upsertPickupRequests(_requests, request);
        }
        for (final ride in result.value.rides) {
          _rides = _upsertRideSessions(_rides, ride);
        }
        _selectedRouteId = nextRouteId;
        _selectedTripId = nextTripId;
      });
      _syncRealtimeRouteSubscription(
        previousRouteId: previousRouteId,
        nextRouteId: nextRouteId,
      );
      unawaited(_maybeAutoUnloadWhenSeparated());
      unawaited(_maybeAutoHandleDestinationApproach());
    } catch (_) {
      // Booking failures must not hide trips or stop map interaction.
    }
  }

  Future<void> _refreshNotifications({
    required bool useCache,
    bool silent = true,
    bool replacePending = false,
  }) async {
    final session = context.read<SessionController>();
    try {
      final result = await _refreshCoordinator.run<List<NotificationModel>>(
        PassengerRefreshDomain.notifications,
        () =>
            NotificationService(session.apiClient).getMine(useCache: useCache),
        replacePending: replacePending,
      );
      if (!mounted || !result.isCurrent) return;
      setState(() => _notifications = result.value);
      _handleRealtimePassengerUpdates(
        notifications: result.value,
        silent: silent,
      );
    } catch (_) {
      // Notification failures do not affect booking or vehicle state.
    }
  }

  Future<void> _refreshRoutes({
    required bool useCache,
    bool replacePending = false,
  }) async {
    final session = context.read<SessionController>();
    try {
      final result = await _refreshCoordinator.run<List<RouteSummaryModel>>(
        PassengerRefreshDomain.routes,
        () => RouteService(session.apiClient).getRoutes(useCache: useCache),
        replacePending: replacePending,
      );
      if (!mounted || !result.isCurrent) return;
      final previousRouteId = _selectedRouteId;
      final currentRouteStillAvailable = previousRouteId != null &&
          result.value.any(
            (route) => route.id == previousRouteId && route.status == 'active',
          );
      final activeRoutes = result.value
          .where((route) => route.status == 'active')
          .toList(growable: false);
      final nextRouteId = currentRouteStillAvailable
          ? previousRouteId
          : _selectRouteId(
              routes: activeRoutes.isEmpty ? result.value : activeRoutes,
              trips: _trips,
              requests: _requests,
              rides: _rides,
            );
      final nextTripId = _selectTripIdForRoute(
        trips: _trips,
        requests: _requests,
        rides: _rides,
        routeId: nextRouteId,
        anchor: _draftPickupPoint,
      );
      setState(() {
        _routes = result.value;
        _selectedRouteId = nextRouteId;
        _selectedTripId = nextTripId;
        _lastRouteMetadataRefreshAt = DateTime.now();
      });
      _syncRealtimeRouteSubscription(
        previousRouteId: previousRouteId,
        nextRouteId: nextRouteId,
      );
    } catch (_) {
      // Route metadata is stable; preserve the last valid list on failure.
    }
  }

  bool _hasFreshRealtimeVehicleState({DateTime? now}) {
    if (!_realtimeSocketService.isConnected) {
      return false;
    }
    final comparisonTime = now ?? DateTime.now();
    return _tripVehicleStates.values.any((state) {
      final lastUpdateAt = state.lastRealtimeUpdateAt;
      if (lastUpdateAt == null) {
        return false;
      }
      return comparisonTime.difference(lastUpdateAt) <= _tripRealtimeStaleAfter;
    });
  }

  bool _shouldRefreshPassengerMetadata({DateTime? now}) {
    final lastSyncAt = _lastPassengerSyncAt;
    if (lastSyncAt == null) {
      return true;
    }
    return (now ?? DateTime.now()).difference(lastSyncAt) >=
        _metadataRefreshInterval;
  }

  bool _applyRealtimePassengerNotification(NotificationModel notification) {
    var needsFallback = false;
    _refreshCoordinator.invalidate(PassengerRefreshDomain.notifications);

    setState(() {
      _notifications = _upsertNotificationList(_notifications, notification);

      switch (notification.type) {
        case 'pickup_request_acknowledged':
        case 'pickup_request_completed':
          _refreshCoordinator.invalidate(PassengerRefreshDomain.bookings);
          final request = _readPassengerPickupRequest(notification.payload);
          if (request == null) {
            needsFallback = true;
            return;
          }
          _requests = _upsertPickupRequests(_requests, request);

          final ride = _readPassengerRideSession(notification.payload);
          if (ride != null) {
            _rides = _upsertRideSessions(_rides, ride);
          }
          break;
        case 'ride_completed':
          _refreshCoordinator.invalidate(PassengerRefreshDomain.bookings);
          final ride = _readPassengerRideSession(notification.payload);
          if (ride == null) {
            needsFallback = true;
            return;
          }
          _rides = _upsertRideSessions(_rides, ride);
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

  List<PickupRequestModel> _upsertPickupRequests(
    List<PickupRequestModel> requests,
    PickupRequestModel request,
  ) {
    final next = List<PickupRequestModel>.from(requests);
    final existingIndex = next.indexWhere((item) => item.id == request.id);
    if (existingIndex >= 0) {
      if (next[existingIndex].status == 'completed' &&
          request.status != 'completed') {
        return next;
      }
      next[existingIndex] = request;
    } else {
      next.insert(0, request);
    }
    next.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return next;
  }

  List<RideSessionModel> _upsertRideSessions(
    List<RideSessionModel> rides,
    RideSessionModel ride,
  ) {
    final next = List<RideSessionModel>.from(rides);
    final existingIndex = next.indexWhere((item) => item.id == ride.id);
    if (existingIndex >= 0) {
      if (next[existingIndex].status == 'completed' &&
          ride.status != 'completed') {
        return next;
      }
      next[existingIndex] = ride;
    } else {
      next.insert(0, ride);
    }
    next.sort((a, b) {
      final endedComparison = (b.endedAt ?? '').compareTo(a.endedAt ?? '');
      if (endedComparison != 0) {
        return endedComparison;
      }
      return (b.boardedAt ?? '').compareTo(a.boardedAt ?? '');
    });
    return next;
  }

  PickupRequestModel? _readPassengerPickupRequest(
      Map<String, dynamic> payload) {
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

  RideSessionModel? _readPassengerRideSession(Map<String, dynamic> payload) {
    final raw = payload['rideSession'];
    if (raw is Map<String, dynamic>) {
      return RideSessionModel.fromJson(raw);
    }
    if (raw is Map) {
      return RideSessionModel.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  void _showPassengerRealtimeSnackBar(NotificationModel notification) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (notification.type == 'passenger_near_destination') {
      final stopLabel = _destinationApproachStopLabel(notification.payload);
      final thresholdMeters =
          _destinationApproachThresholdMeters(notification.payload);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "You're within $thresholdMeters meters of $stopLabel. The driver has been notified.",
          ),
        ),
      );
      return;
    }

    if (notification.type == 'pickup_request_completed') {
      final request = _readPassengerPickupRequest(notification.payload);
      final stopLabel = request?.stopRef ?? 'your selected pickup point';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Pickup confirmed at $stopLabel. Your booking was updated.',
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('${notification.title}: ${notification.body}')),
    );
  }

  Future<void> _runPassengerAction({
    required String loadingMessage,
    required String successMessage,
    required Future<dynamic> Function() action,
    bool reloadAfter = true,
  }) async {
    setState(() => _loading = true);
    try {
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
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _handleRealtimePassengerUpdates({
    required List<NotificationModel> notifications,
    required bool silent,
  }) {
    final notificationIds = notifications.map((item) => item.id).toSet();
    if (!_realtimePrimed) {
      _knownNotificationIds = notificationIds;
      _realtimePrimed = true;
      return;
    }

    final newNotifications = notifications
        .where((item) => !_knownNotificationIds.contains(item.id))
        .toList(growable: false);
    _knownNotificationIds = notificationIds;

    if (!silent || !mounted || newNotifications.isEmpty) {
      return;
    }

    final first = newNotifications.first;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newNotifications.length == 1
              ? '${first.title}: ${first.body}'
              : '${newNotifications.length} new passenger notifications received.',
        ),
      ),
    );
  }

  bool get _hasTerminalSeats => _trips.any((trip) =>
      trip.routeId == _selectedRouteId &&
      trip.operatingMode == 'terminal_queue' &&
      trip.terminalQueueStatus == 'loading' &&
      trip.terminalSummary?['departureRequired'] != true &&
      (trip.terminalSummary?['availableSeats'] as num? ?? 0) > 0);
  bool get _terminalBookingFull =>
      _bookingMode == _PassengerBookingMode.terminal && !_hasTerminalSeats;

  Future<void> _sendPickup() async {
    final selectedRoute = _selectedRoute;
    if (_selectedRouteId == null || selectedRoute == null) {
      setState(() =>
          _statusMessage = 'Choose a route before sending a booking request.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Route required',
        message: 'Choose a route before sending a booking request.',
      );
      return;
    }

    final terminalStop = _routeTerminalStop(selectedRoute);
    final isTerminalBooking = _bookingMode == _PassengerBookingMode.terminal;

    if ((isTerminalBooking && _draftUnloadPoint == null) ||
        (!isTerminalBooking &&
            (_draftPickupPoint == null || _draftUnloadPoint == null))) {
      setState(() => _statusMessage = isTerminalBooking
          ? 'Choose your unload location before booking from the terminal.'
          : 'Pin both your pickup and unload locations on the map before booking.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Pins required',
        message: isTerminalBooking
            ? 'Choose your unload location before booking from the terminal.'
            : 'Pin both your pickup and unload locations on the map before booking.',
      );
      return;
    }
    if (isTerminalBooking && terminalStop == null) {
      setState(() =>
          _statusMessage = 'This route has no terminal stop configured yet.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Terminal unavailable',
        message:
            'This route has no terminal stop configured yet. Use roadside booking for now.',
      );
      return;
    }

    final payload = await _showPickupDialog();
    if (payload == null) return;
    if (!mounted) return;
    final currentLocation = await _ensureCurrentPassengerLocation();
    if (!mounted) return;
    if (currentLocation == null) {
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Location required',
        message:
            'Your current location is required before sending a pickup request.',
      );
      return;
    }
    setState(() {
      _draftPickupPoint = payload.bookingMode == _PassengerBookingMode.terminal
          ? terminalStop?.position
          : _draftPickupPoint;
      _draftPickupLabel = payload.pickupStopRef;
      _draftUnloadLabel = payload.destinationStopRef;
      _bookingMode = payload.bookingMode;
    });

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: payload.bookingMode == _PassengerBookingMode.terminal
          ? 'Sending terminal boarding request...'
          : 'Sending pickup request...',
      successMessage: payload.bookingMode == _PassengerBookingMode.terminal
          ? 'Terminal boarding request sent. A terminal-queue jeep on ${selectedRoute.label} has been notified.'
          : 'Booking request sent. The nearest eligible jeep on ${selectedRoute.label} has been notified.',
      action: () => passengerService.createPickupRequest(
        routeId: _selectedRouteId!,
        currentLat: currentLocation.latitude,
        currentLng: currentLocation.longitude,
        pickupType: payload.bookingMode.apiValue,
        pickupLat: payload.bookingMode == _PassengerBookingMode.terminal
            ? null
            : _draftPickupPoint!.latitude,
        pickupLng: payload.bookingMode == _PassengerBookingMode.terminal
            ? null
            : _draftPickupPoint!.longitude,
        destinationStopRef: payload.destinationStopRef,
        destinationLat: _draftUnloadPoint!.latitude,
        destinationLng: _draftUnloadPoint!.longitude,
        stopRef: payload.pickupStopRef,
        sourceNote: payload.note,
      ),
    );
  }

  List<PickupRequestModel> get _transferOffers => _requests
      .where((r) =>
          r.status == 'transfer_offered' &&
          (DateTime.tryParse(r.expiresAt ?? '')?.isAfter(DateTime.now()) ??
              false))
      .toList();

  Future<void> _showTransferOffers() async {
    if (_transferOffers.isEmpty) return;
    final offer = _transferOffers.first;
    final accept = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Your terminal booking needs a new jeep'),
                content: Text(
                    'Your previous jeep departed or was skipped. Accept a seat on the current loading jeep when available. Your destination (${offer.destinationStopRef ?? "saved destination"}), fare and original expiry stay unchanged.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel booking')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Accept transfer'))
                ]));
    if (accept == null || !mounted) return;
    final service =
        PassengerService(context.read<SessionController>().apiClient);
    await _runPassengerAction(
        loadingMessage: 'Updating booking...',
        successMessage:
            accept ? 'Transferred to the loading jeep.' : 'Booking cancelled.',
        action: () => service.decideTransfer(offer, accept));
  }

  Future<void> _board() async {
    final acknowledgedRequests = _requests
        .where((request) => request.status == 'acknowledged')
        .toList()
      ..sort((a, b) => (b.expiresAt ?? '').compareTo(a.expiresAt ?? ''));

    if (acknowledgedRequests.isEmpty) {
      setState(() => _statusMessage =
          'Wait for the driver to acknowledge your pickup request before boarding.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Acknowledgement required',
        message:
            'Wait for the driver to acknowledge your pickup request before boarding.',
      );
      return;
    }

    final request = _selectedTripBooking?.status == 'acknowledged'
        ? _selectedTripBooking!
        : acknowledgedRequests.first;
    final currentLocation = await _ensureCurrentPassengerLocation(
      silent: true,
      forceRefresh: true,
    );
    if (!mounted) {
      return;
    }

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Validating boarding...',
      successMessage:
          'Boarding validated. Saved unload point is now active for this ride.',
      action: () async {
        if (currentLocation != null) {
          await passengerService.updateLocationForRideAutomation(
              lat: currentLocation.latitude, lng: currentLocation.longitude,
              capturedAt: _currentPassengerLocationAt);
        }
        return passengerService.validateBoarding(
          tripSessionId: request.tripSessionId,
          pickupRequestId: request.id,
          lat: currentLocation?.latitude,
          lng: currentLocation?.longitude,
        );
      },
    );
  }

  Future<void> _sendPara() async {
    final ride = _activeRide;
    if (ride == null ||
        ride.status != 'onboard' ||
        ride.canSendStopAlert == false) {
      setState(() => _statusMessage =
          'Digital para alert is only available for verified onboard riders.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Para unavailable',
        message:
            'Digital para alert is only available for verified onboard riders.',
      );
      return;
    }

    final payload = await _showStopAlertDialog(ride);
    if (payload == null) return;
    if (!mounted) return;

    final session = context.read<SessionController>();
    final alerts = StopAlertService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Sending para alert...',
      successMessage: 'Stop alert sent successfully.',
      action: () => alerts.sendStopAlert(
        tripSessionId: ride.tripSessionId,
        stopRef: payload.stopRef,
        note: payload.note,
        lat: ride.destinationLatitude,
        lng: ride.destinationLongitude,
      ),
    );
  }

  Future<void> _markUnloaded() async {
    final ride = _activeRide;
    if (ride == null || ride.status != 'onboard') {
      setState(() => _statusMessage =
          'A verified onboard ride is required before you can mark yourself as unloaded.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Unload unavailable',
        message:
            'A verified onboard ride is required before you can mark yourself as unloaded.',
      );
      return;
    }

    final confirmed = await _showUnloadConfirmationDialog(
      title: 'Confirm unload',
      message:
          'Mark your ride as unloaded near ${ride.destinationStopRef ?? 'your saved destination'}?',
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Closing your ride session...',
      successMessage: 'Your ride has been marked as unloaded.',
      action: () => passengerService.completeRideSession(ride.id),
    );
  }

  Future<bool> _showUnloadConfirmationDialog({
    required String title,
    required String message,
    String confirmLabel = 'I unloaded',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _resetAutoUnloadWindow({String? rideId}) {
    _outsideAutoUnloadWindowCount = 0;
    _autoUnloadPromptedAt = null;
    _autoUnloadWindowRideId = rideId;
  }

  Future<void> _maybeAutoUnloadWhenSeparated() async {
    final ride = _activeRide;
    if (!mounted || ride == null || ride.status != 'onboard') {
      _resetAutoUnloadWindow();
      return;
    }

    if (_autoUnloadWindowRideId != ride.id) {
      _resetAutoUnloadWindow(rideId: ride.id);
    }

    final trip = _tripById(ride.tripSessionId);
    final jeepneyPoint = trip == null ? null : _tripVehiclePoint(trip);
    if (trip == null || jeepneyPoint == null) {
      _resetAutoUnloadWindow(rideId: ride.id);
      return;
    }

    final passengerLocation = await _ensureCurrentPassengerLocation(
      silent: true,
      triggerAutoUnload: false,
    );
    if (!mounted || passengerLocation == null) {
      return;
    }

    final distanceMeters = _distance.as(
      LengthUnit.Meter,
      passengerLocation,
      jeepneyPoint,
    );
    if (distanceMeters < _autoUnloadDistanceMeters) {
      _resetAutoUnloadWindow(rideId: ride.id);
      return;
    }

    final now = DateTime.now();
    _outsideAutoUnloadWindowCount += 1;
    if (_outsideAutoUnloadWindowCount < _autoUnloadConsecutiveOutsideChecks) {
      return;
    }

    if (_autoUnloadPromptedAt != null) {
      return;
    }

    _autoUnloadPromptedAt = now;
    final roundedDistance = distanceMeters.round();
    final message =
        'You are about $roundedDistance meters away from the jeepney. If you already got off, use "I unloaded" to close the ride manually.';
    setState(() {
      _statusMessage = message;
      _syncMessage = message;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _maybeAutoHandleDestinationApproach() async {
    final ride = _activeRide;
    if (!mounted || ride == null || ride.status != 'onboard') {
      return;
    }

    if (ride.destinationLatitude == null || ride.destinationLongitude == null) {
      return;
    }

    final trip = _tripById(ride.tripSessionId);
    final jeepneyPoint = trip == null ? null : _tripVehiclePoint(trip);
    if (trip == null || jeepneyPoint == null) {
      return;
    }

    final destinationPoint = LatLng(
      ride.destinationLatitude!,
      ride.destinationLongitude!,
    );
    final jeepneyToDestinationMeters = _distance.as(
      LengthUnit.Meter,
      jeepneyPoint,
      destinationPoint,
    );

    if (jeepneyToDestinationMeters > 120 ||
        _destinationReminderRideIds.contains(ride.id)) {
      return;
    }

    _destinationReminderRideIds.add(ride.id);
    final destinationLabel =
        ride.destinationStopRef ?? 'your saved destination';
    final message = ride.canSendStopAlert == false
        ? 'You are near $destinationLabel. ParaGO will notify the driver automatically within 50 meters. Unload manually once you get off.'
        : 'You are near $destinationLabel. ParaGO will notify the driver automatically within 50 meters, but you can still send a para alert anytime if needed.';
    setState(() {
      _statusMessage = message;
      _syncMessage = message;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _shouldReportPassengerLocationForRideAutomation =>
      _activeRide?.status == 'onboard' ||
      _requests.any((request) => request.status == 'acknowledged');

  Future<void> _reportPassengerLocationForAutoBoarding(LatLng location) async {
    if (!_shouldReportPassengerLocationForRideAutomation ||
        _passengerLocationReportInFlight) {
      return;
    }

    final now = DateTime.now();
    final lastReportedAt = _lastPassengerLocationReportedAt;
    final lastReportedLocation = _lastPassengerLocationReported;
    if (lastReportedAt != null &&
        now.difference(lastReportedAt) < _passengerLocationReportInterval &&
        lastReportedLocation != null &&
        _distance.as(
              LengthUnit.Meter,
              lastReportedLocation,
              location,
            ) <
            _passengerLocationReportDistanceMeters) {
      return;
    }

    _passengerLocationReportInFlight = true;
    try {
      final session = context.read<SessionController>();
      final result = await PassengerService(session.apiClient)
          .updateLocationForRideAutomation(
        lat: location.latitude,
        lng: location.longitude,
        capturedAt: _currentPassengerLocationAt,
      );
      _lastPassengerLocationReportedAt = now;
      _lastPassengerLocationReported = location;
      if (mounted && (_syncMessage?.startsWith('Location upload failed.') == true ||
          _syncMessage?.startsWith('Fresh, accurate GPS is unavailable.') == true)) {
        setState(() => _syncMessage = 'Location reporting restored.');
      }
      final boardedRide = result.autoBoardedRide;
      final completedRide = result.autoCompletedRide;
      if (!mounted || (boardedRide == null && completedRide == null)) {
        return;
      }
      final message = completedRide != null
          ? 'Automatic unload detected. Your ride has been closed.'
          : 'Boarding detected automatically. Your ride is now active.';
      setState(() {
        if (boardedRide != null) {
          _rides = _upsertRideSessions(_rides, boardedRide);
        }
        if (completedRide != null) {
          _rides = _upsertRideSessions(_rides, completedRide);
          _resetAutoUnloadWindow();
        }
        _statusMessage = message;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      unawaited(_refreshPassengerMetadata(silent: true));
    } catch (_) {
      if (mounted) {
        setState(() => _syncMessage = 'Location upload failed. Automatic boarding and unloading may be unavailable. Check your connection or sign in again.');
      }
    } finally {
      _passengerLocationReportInFlight = false;
    }
  }

  String _destinationApproachStopLabel(Map<String, dynamic> payload) {
    final value = payload['destinationStopRef']?.toString().trim() ?? '';
    return value.isEmpty ? 'your destination' : value;
  }

  int _destinationApproachThresholdMeters(Map<String, dynamic> payload) {
    final raw = payload['thresholdMeters'];
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '') ?? 50;
  }

  Future<void> _cancelRequest(String requestId) async {
    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Cancelling pickup request...',
      successMessage: 'Pickup request cancelled.',
      action: () => passengerService.cancelPickupRequest(requestId),
    );
  }

  Future<void> _markAllRead() async {
    final session = context.read<SessionController>();
    final notificationService = NotificationService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Marking notifications as read...',
      successMessage: 'All notifications marked as read.',
      action: () => notificationService.markAllRead(),
    );
  }

  Future<_PassengerBookingDetails?> _showPickupDialog() async {
    final terminalStop = _routeTerminalStop(_selectedRoute);
    var selectedBookingMode = _bookingMode;
    final pickupStopCtrl = TextEditingController(
      text: _bookingMode == _PassengerBookingMode.terminal
          ? (terminalStop?.name ?? 'Route terminal')
          : (_draftPickupLabel ?? 'Nearest loading point'),
    );
    final unloadStopCtrl = TextEditingController(
      text: _draftUnloadLabel ?? 'Selected unload location',
    );
    final noteCtrl = TextEditingController();
    final result = await showDialog<_PassengerBookingDetails>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        final farePreview = _estimateFarePreview(
          _selectedRoute,
          selectedBookingMode == _PassengerBookingMode.terminal
              ? terminalStop?.position
              : _draftPickupPoint,
          _draftUnloadPoint,
        );

        void submit() {
          if (selectedBookingMode == _PassengerBookingMode.terminal &&
              !_hasTerminalSeats) {
            return;
          }
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).pop(
            _PassengerBookingDetails(
              bookingMode: selectedBookingMode,
              pickupStopRef: pickupStopCtrl.text.trim().isEmpty
                  ? (selectedBookingMode == _PassengerBookingMode.terminal
                      ? (terminalStop?.name ?? 'Route terminal')
                      : 'Nearest loading point')
                  : pickupStopCtrl.text.trim(),
              destinationStopRef: unloadStopCtrl.text.trim().isEmpty
                  ? 'Selected unload location'
                  : unloadStopCtrl.text.trim(),
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            ),
          );
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Book this route'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, _) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Roadside pickup'),
                        selected: selectedBookingMode ==
                            _PassengerBookingMode.roadside,
                        onSelected: (_) {
                          setDialogState(() {
                            selectedBookingMode =
                                _PassengerBookingMode.roadside;
                            pickupStopCtrl.text =
                                _draftPickupLabel ?? 'Nearest loading point';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Board from terminal'),
                        selected: selectedBookingMode ==
                            _PassengerBookingMode.terminal,
                        onSelected: terminalStop == null
                            ? null
                            : (_) {
                                setDialogState(() {
                                  selectedBookingMode =
                                      _PassengerBookingMode.terminal;
                                  pickupStopCtrl.text =
                                      terminalStop.name.isEmpty
                                          ? 'Route terminal'
                                          : terminalStop.name;
                                });
                              },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              if (farePreview != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF7E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFE1A6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimated fare: ${_formatFareAmount(farePreview.amount)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${farePreview.boardingStopRef} to ${farePreview.destinationStopRef}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: pickupStopCtrl,
                textInputAction: TextInputAction.next,
                readOnly: selectedBookingMode == _PassengerBookingMode.terminal,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Boarding landmark or stop reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unloadStopCtrl,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Unload landmark or stop reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                ),
                minLines: 2,
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  selectedBookingMode == _PassengerBookingMode.terminal &&
                          !_hasTerminalSeats
                      ? null
                      : submit,
              child: Text(
                  selectedBookingMode == _PassengerBookingMode.terminal &&
                          !_hasTerminalSeats
                      ? 'Wait for the next jeep'
                      : 'Book now'),
            ),
          ],
        );
      }),
    );
    pickupStopCtrl.dispose();
    unloadStopCtrl.dispose();
    noteCtrl.dispose();
    return result;
  }

  Future<_PassengerInput?> _showStopAlertDialog(RideSessionModel ride) async {
    final stopCtrl = TextEditingController(
      text: ride.destinationStopRef ?? 'Next preferred drop-off point',
    );
    final noteCtrl = TextEditingController();
    final result = await showDialog<_PassengerInput>(
      context: context,
      builder: (context) {
        void submit() {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).pop(
            _PassengerInput(
              stopRef: stopCtrl.text.trim().isEmpty
                  ? 'Next preferred drop-off point'
                  : stopCtrl.text.trim(),
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            ),
          );
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Send digital para alert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stopCtrl,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Drop-off reference',
                ),
              ),
              if (ride.destinationLatitude != null &&
                  ride.destinationLongitude != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Saved unload pin: ${ride.destinationLatitude!.toStringAsFixed(5)}, '
                  '${ride.destinationLongitude!.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: 'Optional note for driver',
                ),
                minLines: 2,
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('Alert driver'),
            ),
          ],
        );
      },
    );
    stopCtrl.dispose();
    noteCtrl.dispose();
    return result;
  }

  RouteSummaryModel? _routeById(String id) {
    for (final route in _routes) {
      if (route.id == id) return route;
    }
    return null;
  }

  bool _tripIsLive(TripSession trip) =>
      trip.status == 'active' || trip.active == true;

  bool _tripMatchesRoute(TripSession trip, RouteSummaryModel? route) {
    if (route == null) {
      return false;
    }
    if (trip.routeId == route.id) {
      return true;
    }
    if ((trip.routeCode ?? '').trim().isNotEmpty &&
        (route.code).trim().isNotEmpty &&
        trip.routeCode!.trim().toLowerCase() ==
            route.code.trim().toLowerCase()) {
      return true;
    }
    if ((trip.routeName ?? '').trim().isNotEmpty &&
        route.name.trim().isNotEmpty &&
        trip.routeName!.trim().toLowerCase() ==
            route.name.trim().toLowerCase()) {
      return true;
    }
    return false;
  }

  List<TripSession> _routeTrips(String routeId) {
    final route = _routeById(routeId);
    return _trips
        .where((trip) => _tripIsLive(trip) && _tripMatchesRoute(trip, route))
        .toList(growable: false);
  }

  LatLng? _selectedRouteDisplayAnchor(
    RouteSummaryModel? route, {
    LatLng? overrideAnchor,
  }) {
    return overrideAnchor ??
        _draftPickupPoint ??
        _currentPassengerLocation ??
        _routeCenter(route);
  }

  List<TripSession> _selectedRouteDisplayTrips(
    String routeId, {
    LatLng? anchor,
  }) {
    return _selectedRouteDisplayTripsFrom(
      _trips,
      routeId,
      anchor: anchor,
    );
  }

  List<TripSession> _selectedRouteDisplayTripsFrom(
    List<TripSession> trips,
    String routeId, {
    LatLng? anchor,
  }) {
    final route = _routeById(routeId);
    if (route == null) {
      return const <TripSession>[];
    }
    final comparisonAnchor = _selectedRouteDisplayAnchor(
      route,
      overrideAnchor: anchor,
    );
    final candidates = trips
        .where(
          (trip) => _isTripEligibleForSelectedRouteDisplay(
            trip,
            route,
            anchor: comparisonAnchor,
          ),
        )
        .toList(growable: false);
    if (comparisonAnchor == null) {
      return candidates
          .take(_selectedRouteVisibleTripLimit)
          .toList(growable: false);
    }
    final sortedCandidates = List<TripSession>.from(candidates)
      ..sort((left, right) {
        return _tripDistanceMeters(left, comparisonAnchor)
            .compareTo(_tripDistanceMeters(right, comparisonAnchor));
      });
    return sortedCandidates
        .take(_selectedRouteVisibleTripLimit)
        .toList(growable: false);
  }

  bool _isTripEligibleForSelectedRouteDisplay(
    TripSession trip,
    RouteSummaryModel? route, {
    LatLng? anchor,
  }) {
    if (!_tripIsLive(trip) || !_tripMatchesRoute(trip, route)) {
      return false;
    }
    final vehiclePoint = _tripVehiclePoint(trip);
    if (vehiclePoint == null) {
      return false;
    }
    final comparisonAnchor = anchor ?? _selectedRouteDisplayAnchor(route);
    if (comparisonAnchor == null) {
      return true;
    }
    return !_hasTripPassedAnchorByMoreThanThreshold(
      route,
      anchor: comparisonAnchor,
      vehiclePoint: vehiclePoint,
    );
  }

  bool _hasTripPassedAnchorByMoreThanThreshold(
    RouteSummaryModel? route, {
    required LatLng anchor,
    required LatLng vehiclePoint,
  }) {
    final anchorProjection = _nearestRouteProjection(route, anchor);
    final vehicleProjection = _nearestRouteProjection(route, vehiclePoint);
    if (anchorProjection == null || vehicleProjection == null) {
      return false;
    }
    if (vehicleProjection.progress <= anchorProjection.progress) {
      return false;
    }
    final traveledDistance = _routeDistanceBetweenProgresses(
      route,
      anchorProjection.progress,
      vehicleProjection.progress,
    );
    return traveledDistance > _selectedRoutePassedAnchorMeters;
  }

  String? _selectRouteId({
    required List<RouteSummaryModel> routes,
    required List<TripSession> trips,
    required List<PickupRequestModel> requests,
    required List<RideSessionModel> rides,
  }) {
    final rideFocusedRouteId = _preferredRouteIdFromRides(
      rides: rides,
      requests: requests,
      trips: trips,
      routes: routes,
    );
    if (rideFocusedRouteId != null) {
      return rideFocusedRouteId;
    }

    final requestFocusedRouteId = _preferredRouteIdFromRequests(
      requests: requests,
      routes: routes,
    );
    if (requestFocusedRouteId != null) {
      return requestFocusedRouteId;
    }

    final existingRouteId = _selectedRouteId;
    if (existingRouteId != null &&
        routes.any((route) => route.id == existingRouteId)) {
      return existingRouteId;
    }

    if (trips.isNotEmpty) {
      return trips.first.routeId;
    }
    if (routes.isNotEmpty) {
      return routes.first.id;
    }
    return null;
  }

  String? _preferredTripIdForRoute(
    List<TripSession> trips,
    String? routeId, {
    LatLng? anchor,
  }) {
    if (routeId == null || routeId.isEmpty) {
      return null;
    }
    final candidates = _selectedRouteDisplayTripsFrom(
      trips,
      routeId,
      anchor: anchor,
    );
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first.id;
  }

  String? _selectTripIdForRoute({
    required List<TripSession> trips,
    required List<PickupRequestModel> requests,
    required List<RideSessionModel> rides,
    required String? routeId,
    LatLng? anchor,
  }) {
    if (routeId == null || routeId.isEmpty) {
      return null;
    }

    final route = _routeById(routeId);
    if (route == null) {
      return _preferredTripIdForRoute(trips, routeId, anchor: anchor);
    }

    for (final ride in rides) {
      if (!_isFocusedRideStatus(ride.status)) {
        continue;
      }
      final trip = _tripFromListById(trips, ride.tripSessionId);
      if (trip != null && _tripIsLive(trip) && _tripMatchesRoute(trip, route)) {
        return trip.id;
      }
    }

    for (final request in requests) {
      if (!_isFocusedRequestStatus(request.status) ||
          request.routeId != routeId ||
          request.tripSessionId.trim().isEmpty) {
        continue;
      }
      final trip = _tripFromListById(trips, request.tripSessionId);
      if (trip != null && _tripIsLive(trip) && _tripMatchesRoute(trip, route)) {
        return trip.id;
      }
    }

    final existingTripId = _selectedTripId;
    if (existingTripId != null && existingTripId.isNotEmpty) {
      final trip = _tripFromListById(trips, existingTripId);
      if (trip != null && _tripIsLive(trip) && _tripMatchesRoute(trip, route)) {
        return trip.id;
      }
    }

    return _preferredTripIdForRoute(trips, routeId, anchor: anchor);
  }

  String? _preferredRouteIdFromRides({
    required List<RideSessionModel> rides,
    required List<PickupRequestModel> requests,
    required List<TripSession> trips,
    required List<RouteSummaryModel> routes,
  }) {
    for (final ride in rides) {
      if (!_isFocusedRideStatus(ride.status)) {
        continue;
      }

      for (final request in requests) {
        if (request.id == ride.pickupRequestId &&
            routes.any((route) => route.id == request.routeId)) {
          return request.routeId;
        }
      }

      for (final trip in trips) {
        if (trip.id == ride.tripSessionId &&
            routes.any((route) => route.id == trip.routeId)) {
          return trip.routeId;
        }
      }
    }
    return null;
  }

  String? _preferredRouteIdFromRequests({
    required List<PickupRequestModel> requests,
    required List<RouteSummaryModel> routes,
  }) {
    for (final request in requests) {
      if (_isFocusedRequestStatus(request.status) &&
          routes.any((route) => route.id == request.routeId)) {
        return request.routeId;
      }
    }
    return null;
  }

  bool _isFocusedRideStatus(String status) =>
      status == 'onboard' || status == 'waiting';

  bool _isFocusedRequestStatus(String status) =>
      status == 'pending' || status == 'acknowledged' || status == 'completed';

  TripSession? _tripFromListById(List<TripSession> trips, String tripId) {
    for (final trip in trips) {
      if (trip.id == tripId) {
        return trip;
      }
    }
    return null;
  }

  LatLng? _routeCenter(RouteSummaryModel? route) {
    if (route?.mapBounds != null) {
      return route!.mapBounds!.center;
    }
    final referencePoints = route?.referencePoints ?? const <LatLng>[];
    if (referencePoints.isNotEmpty) {
      return referencePoints[referencePoints.length ~/ 2];
    }
    return null;
  }

  Future<LatLng?> _ensureCurrentPassengerLocation({
    bool silent = false,
    bool forceRefresh = false,
    bool triggerAutoUnload = true,
    bool recenterMap = false,
  }) async {
    final existingLocation = _currentPassengerLocation;
    final existingTimestamp = _currentPassengerLocationAt;
    if (!forceRefresh &&
        existingLocation != null &&
        existingTimestamp != null &&
        DateTime.now().difference(existingTimestamp) <
            (_shouldReportPassengerLocationForRideAutomation
                ? const Duration(seconds: 5)
                : const Duration(seconds: 20))) {
      return existingLocation;
    }

    if (!mounted) {
      return forceRefresh ? null : existingLocation;
    }
    Future<LatLng?> awaitLocationRequest(Future<LatLng?> request) async {
      final shouldShowProgress = !silent && mounted && !_locatingPassenger;
      if (shouldShowProgress) {
        setState(() => _locatingPassenger = true);
      }
      try {
        return await request;
      } finally {
        if (shouldShowProgress && mounted) {
          setState(() => _locatingPassenger = false);
        }
      }
    }

    final inFlightRequest = _passengerLocationRequest;
    if (inFlightRequest != null) {
      return awaitLocationRequest(inFlightRequest);
    }

    final request = () async {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (!silent && mounted) {
            setState(() {
              _statusMessage =
                  'Turn on device location to place your pickup pin.';
            });
          }
          return forceRefresh ? null : existingLocation;
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (!silent && mounted) {
            setState(() {
              _statusMessage =
                  'Location permission is needed so pickup stays within 50 meters of you.';
            });
          }
          return forceRefresh ? null : existingLocation;
        }

        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy:
                  LocationAccuracy.best,
            ),
          ).timeout(const Duration(seconds: 12));
        } on TimeoutException {
          position = await Geolocator.getLastKnownPosition();
          if (position == null) {
            rethrow;
          }
        }

        final capturedAt = position.timestamp;
        if (!isUsableAutomationLocation(capturedAt: capturedAt, now: DateTime.now(),
            accuracyMeters: position.accuracy)) {
          if (mounted && _shouldReportPassengerLocationForRideAutomation) {
            setState(() => _syncMessage = 'Fresh, accurate GPS is unavailable. Keep location enabled; use manual unload after getting off.');
          }
          return null;
        }

        final previousLocation = _currentPassengerLocation;
        final rawNext = LatLng(position.latitude, position.longitude);
        final reportedAccuracy = position.accuracy;
        final driftMeters = previousLocation == null
            ? null
            : _distance.as(LengthUnit.Meter, previousLocation, rawNext);

        if (previousLocation != null &&
            reportedAccuracy.isFinite &&
            reportedAccuracy > _maxPassengerGpsAccuracyMeters &&
            driftMeters != null &&
            driftMeters <= reportedAccuracy * 1.5) {
          return previousLocation;
        }

        final next = previousLocation != null &&
                driftMeters != null &&
                driftMeters < _passengerGpsJitterMeters
            ? previousLocation
            : rawNext;
        if (!mounted) {
          return next;
        }
        setState(() {
          _currentPassengerLocation = next;
          _currentPassengerLocationAt = capturedAt;
        });
        if (recenterMap || (!silent && previousLocation == null)) {
          _syncPassengerMapCamera(next, preferredZoom: 16, force: true);
        }
        if (triggerAutoUnload) {
          unawaited(_maybeAutoUnloadWhenSeparated());
        }
        unawaited(_reportPassengerLocationForAutoBoarding(next));
        if (_draftPickupPoint == null &&
            previousLocation != null &&
            _distance.as(LengthUnit.Meter, previousLocation, next) >=
                _passengerGpsJitterMeters) {
          _refreshPassengerEtaForTargetChange();
        }
        return next;
      } catch (_) {
        if (!silent && mounted) {
          setState(() {
            _statusMessage =
                'Unable to read your current location right now. Try again in an open area.';
          });
        }
        return forceRefresh ? null : existingLocation;
      }
    }();

    _passengerLocationRequest = request;
    try {
      return await awaitLocationRequest(request);
    } finally {
      if (identical(_passengerLocationRequest, request)) {
        _passengerLocationRequest = null;
      }
    }
  }

  Future<void> _primeCurrentPassengerLocation() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    await _ensureCurrentPassengerLocation(
      silent: true,
      forceRefresh: true,
    );
  }

  double _tripDistanceMeters(TripSession trip, LatLng anchor) {
    final vehiclePoint = _tripVehiclePoint(trip);
    if (vehiclePoint == null) {
      return double.infinity;
    }
    return _distance.as(
      LengthUnit.Meter,
      anchor,
      vehiclePoint,
    );
  }

  TripSession? _tripById(String tripId) {
    for (final trip in _trips) {
      if (trip.id == tripId) {
        return trip;
      }
    }
    return null;
  }

  List<LatLng> _routeMapPath(RouteSummaryModel? route, TripSession? trip) {
    final routePath = route?.mapPath ?? const <LatLng>[];
    if (routePath.length >= 2) {
      return routePath;
    }
    final tripPath = trip?.routePathSnapshotPoints ?? const <LatLng>[];
    if (tripPath.length >= 2) {
      return tripPath;
    }
    return const <LatLng>[];
  }

  List<LatLng> _orderedRoutePoints(RouteSummaryModel? route) {
    if (route == null) {
      return const <LatLng>[];
    }
    final mapPath = route.mapPath;
    if (mapPath.isNotEmpty) {
      return mapPath;
    }
    return route.stopPoints
        .map((stop) => stop.position)
        .toList(growable: false);
  }

  _RouteProjection? _nearestRouteProjection(
      RouteSummaryModel? route, LatLng point) {
    final orderedPoints = _orderedRoutePoints(route);
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
        progress: 0.0,
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

  double? _distanceToRoute(RouteSummaryModel? route, LatLng point) {
    return _nearestRouteProjection(route, point)?.distanceMeters;
  }

  bool _isUnloadAfterPickup(
    RouteSummaryModel? route,
    LatLng pickup,
    LatLng unload,
  ) {
    final pickupProjection = _nearestRouteProjection(route, pickup);
    final unloadProjection = _nearestRouteProjection(route, unload);
    if (pickupProjection == null || unloadProjection == null) {
      return true;
    }
    return unloadProjection.progress > pickupProjection.progress;
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
        fraction: 0.0,
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

  Future<void> _onPassengerMapTap(LatLng point) async {
    final route = _selectedRoute;
    final currentLocation = await _ensureCurrentPassengerLocation();
    final previousPickupPoint = _draftPickupPoint;
    LatLng? labelLookupPoint;
    var lookupPickupLabel = false;
    if (!mounted) {
      return;
    }
    final tappedDistanceToRoute = _distanceToRoute(route, point);
    final snappedPoint = _nearestRouteProjection(route, point)?.point;
    setState(() {
      if (route == null ||
          tappedDistanceToRoute == null ||
          snappedPoint == null) {
        _statusMessage =
            'Choose a route with a visible path before placing pins.';
        return;
      }
      if (_mapSelectionMode == _PassengerMapSelectionMode.pickup) {
        if (tappedDistanceToRoute > _pickupPinToleranceMeters) {
          _statusMessage =
              'Pickup pin must stay close to the route. Move it within ${_pickupPinToleranceMeters.toInt()} meters of the road.';
          return;
        }
        if (currentLocation == null) {
          _statusMessage =
              'Your current location is needed before placing the pickup pin.';
          return;
        }
        final pickupDistanceFromCurrentLocation = _distance.as(
          LengthUnit.Meter,
          currentLocation,
          snappedPoint,
        );
        if (pickupDistanceFromCurrentLocation >
            _pickupFromCurrentLocationMeters) {
          _statusMessage =
              'Pickup pin must stay within ${_pickupFromCurrentLocationMeters.toInt()} meters of your current location.';
          return;
        }
        _draftPickupPoint = snappedPoint;
        _draftPickupLabel = _nearestRoutePlaceName(
          route,
          snappedPoint,
          fallback: 'Selected pickup location',
        );
        labelLookupPoint = snappedPoint;
        lookupPickupLabel = true;
        _selectedTripId = _preferredTripIdForRoute(
          _trips,
          _selectedRouteId,
          anchor: snappedPoint,
        );
        if (_draftUnloadPoint != null &&
            !_isUnloadAfterPickup(route, snappedPoint, _draftUnloadPoint!)) {
          _draftUnloadPoint = null;
          _draftUnloadLabel = null;
          _mapSelectionMode = _PassengerMapSelectionMode.pickup;
          _statusMessage =
              'Unload pin was cleared because it must come after the pickup point on the route.';
        }
      } else {
        final pickupPoint = _draftPickupPoint;
        if (pickupPoint == null) {
          _statusMessage = 'Pin your pickup point first before placing unload.';
          _mapSelectionMode = _PassengerMapSelectionMode.pickup;
          return;
        }
        if (tappedDistanceToRoute > _unloadPinToleranceMeters) {
          _statusMessage =
              'Unload pin must stay on the route and within ${_unloadPinToleranceMeters.toInt()} meters of the road.';
          return;
        }
        if (!_isUnloadAfterPickup(route, pickupPoint, snappedPoint)) {
          _statusMessage =
              'Unload pin must come after the pickup point along the route.';
          return;
        }
        _draftUnloadPoint = snappedPoint;
        _draftUnloadLabel = _nearestRoutePlaceName(
          route,
          snappedPoint,
          fallback: 'Selected unload location',
        );
        labelLookupPoint = snappedPoint;
      }
    });
    if (labelLookupPoint != null) {
      unawaited(
        _refreshPinnedLocationLabel(
          point: labelLookupPoint!,
          forPickup: lookupPickupLabel,
        ),
      );
    }
    if (lookupPickupLabel &&
        !_sameMapPoint(previousPickupPoint, _draftPickupPoint)) {
      _refreshPassengerEtaForTargetChange();
    }
  }

  Future<void> _refreshPinnedLocationLabel({
    required LatLng point,
    required bool forPickup,
  }) async {
    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    final lookupSerial =
        forPickup ? ++_pickupLabelLookupSerial : ++_unloadLabelLookupSerial;
    try {
      final label = await passengerService.reverseGeocodeLabel(
        lat: point.latitude,
        lng: point.longitude,
      );
      if (!mounted || label == null || label.isEmpty) {
        return;
      }
      final latestSerial =
          forPickup ? _pickupLabelLookupSerial : _unloadLabelLookupSerial;
      final activePoint = forPickup ? _draftPickupPoint : _draftUnloadPoint;
      if (lookupSerial != latestSerial || !_sameMapPoint(activePoint, point)) {
        return;
      }
      setState(() {
        if (forPickup) {
          _draftPickupLabel = label;
        } else {
          _draftUnloadLabel = label;
        }
      });
    } catch (_) {
      // Keep the route-based fallback label if reverse geocoding fails.
    }
  }

  bool _sameMapPoint(LatLng? a, LatLng? b) {
    if (a == null || b == null) {
      return false;
    }
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  String _nearestRoutePlaceName(
    RouteSummaryModel? route,
    LatLng point, {
    required String fallback,
  }) {
    final stops = route?.stopPoints ?? const <RouteStopPoint>[];
    if (stops.isEmpty) {
      return fallback;
    }

    RouteStopPoint? nearest;
    var nearestDistance = double.infinity;
    for (final stop in stops) {
      final distance = _distance.as(
        LengthUnit.Meter,
        point,
        stop.position,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = stop;
      }
    }

    if (nearest == null) {
      return fallback;
    }

    final roundedDistance = nearestDistance.round();
    if (nearestDistance <= 35) {
      return nearest.name;
    }
    return '${nearest.name} ($roundedDistance m)';
  }

  _PassengerFarePreview? _estimateFarePreview(
    RouteSummaryModel? route,
    LatLng? pickup,
    LatLng? unload,
  ) {
    if (route == null || pickup == null || unload == null) {
      return null;
    }
    final pickupProjection = _nearestRouteProjection(route, pickup);
    final unloadProjection = _nearestRouteProjection(route, unload);
    if (pickupProjection == null || unloadProjection == null) {
      return null;
    }
    final distanceMeters = _routeDistanceBetweenProgresses(
      route,
      pickupProjection.progress,
      unloadProjection.progress,
    );
    final amount = _computeDistanceFare(route, distanceMeters);
    final stops = _routeFareStops(route);
    final boardingStop = _selectNearestFareStop(
          stops: stops,
          point: pickup,
          progress: pickupProjection.progress,
        ) ??
        _PassengerFareStop(
          name: _draftPickupLabel ?? 'Selected pickup location',
          progress: pickupProjection.progress,
          position: pickupProjection.point,
        );
    final destinationStop = _selectNearestFareStop(
          stops: stops,
          point: unload,
          progress: unloadProjection.progress,
          minProgress: boardingStop.progress,
        ) ??
        _PassengerFareStop(
          name: _draftUnloadLabel ?? 'Selected unload location',
          progress: unloadProjection.progress,
          position: unloadProjection.point,
        );
    return _PassengerFarePreview(
      boardingStopRef: boardingStop.name,
      destinationStopRef: destinationStop.name,
      amount: amount,
    );
  }

  List<_PassengerFareStop> _routeFareStops(RouteSummaryModel route) {
    final stops = <_PassengerFareStop>[];
    for (final stop in route.stopPoints) {
      stops.add(
        _PassengerFareStop(
          name: stop.name,
          progress: _nearestRouteProjection(route, stop.position)?.progress ??
              stop.order.toDouble(),
          position: stop.position,
        ),
      );
    }
    stops.sort((left, right) => left.progress.compareTo(right.progress));
    return stops;
  }

  _PassengerFareStop? _selectNearestFareStop({
    required List<_PassengerFareStop> stops,
    required LatLng point,
    double? progress,
    double? minProgress,
  }) {
    final candidates = minProgress == null
        ? stops
        : stops.where((stop) => stop.progress >= minProgress).toList();
    final pool = candidates.isEmpty ? stops : candidates;
    _PassengerFareStop? nearest;
    var nearestScore = double.infinity;
    for (final stop in pool) {
      final progressDelta =
          progress == null ? 0 : (stop.progress - progress).abs();
      final distanceMeters = _distance.as(
        LengthUnit.Meter,
        point,
        stop.position,
      );
      final score = progress == null
          ? distanceMeters
          : progressDelta * 1000 + distanceMeters;
      if (score < nearestScore) {
        nearestScore = score;
        nearest = stop;
      }
    }
    return nearest;
  }

  double _routeDistanceBetweenProgresses(
    RouteSummaryModel? route,
    double startProgress,
    double endProgress,
  ) {
    final orderedPoints = _orderedRoutePoints(route);
    if (orderedPoints.length < 2) {
      return 0;
    }
    return math.max(
      0,
      _routeDistanceAtProgress(orderedPoints, endProgress) -
          _routeDistanceAtProgress(orderedPoints, startProgress),
    );
  }

  double _routeDistanceAtProgress(List<LatLng> orderedPoints, double progress) {
    if (orderedPoints.length < 2) {
      return 0;
    }
    final maxProgress = orderedPoints.length - 1;
    final clampedProgress = progress.clamp(0.0, maxProgress.toDouble());
    final segmentIndex = math.min(
      orderedPoints.length - 2,
      math.max(0, clampedProgress.floor()),
    );
    final fraction = clampedProgress - segmentIndex;
    var distanceMeters = 0.0;
    for (var index = 0; index < segmentIndex; index += 1) {
      distanceMeters += _distance.as(
        LengthUnit.Meter,
        orderedPoints[index],
        orderedPoints[index + 1],
      );
    }
    distanceMeters += _distance.as(
          LengthUnit.Meter,
          orderedPoints[segmentIndex],
          orderedPoints[segmentIndex + 1],
        ) *
        fraction;
    return distanceMeters;
  }

  double _computeDistanceFare(RouteSummaryModel? route, double distanceMeters) {
    final fareConfig = route?.fareConfig ?? const RouteFareConfig();
    final baseDistanceMeters = fareConfig.baseDistanceKm * 1000;
    if (distanceMeters <= baseDistanceMeters) {
      return fareConfig.baseAmount;
    }
    final additionalKm = ((distanceMeters - baseDistanceMeters) / 1000).ceil();
    return fareConfig.baseAmount +
        additionalKm * fareConfig.additionalAmountPerKm;
  }

  String _formatFareAmount(double? amount) {
    final value = amount ?? 0;
    final decimals = value == value.truncateToDouble() ? 0 : 2;
    return 'PHP ${value.toStringAsFixed(decimals)}';
  }

  _PassengerFarePreview? _draftFarePreview(RouteSummaryModel? route) {
    return _estimateFarePreview(route, _draftPickupPoint, _draftUnloadPoint);
  }

  List<Marker> _routeLandmarkMarkers(RouteSummaryModel? route) {
    final stops = route?.stopPoints ?? const <RouteStopPoint>[];
    return [
      for (var index = 0; index < stops.length; index += 1)
        Marker(
          point: stops[index].position,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {
              _showLandmarkDetails(stops[index], index + 1);
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF8A3B5D),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  String _bookingStateText(PickupRequestModel request) {
    final boardingLabel =
        request.pickupType == 'terminal' ? 'terminal boarding' : 'pickup';
    switch (request.status) {
      case 'pending':
        return request.pickupType == 'terminal'
            ? 'Waiting for terminal queue acknowledgement'
            : 'Waiting for driver acknowledgement';
      case 'acknowledged':
        return 'Driver acknowledged your $boardingLabel';
      case 'completed':
        return 'Boarding confirmed and ride is active';
      case 'cancelled':
        return 'Booking was cancelled';
      default:
        return ParagoFormat.statusLabel(request.status);
    }
  }

  Future<void> _showLandmarkDetails(RouteStopPoint stop, int stopNumber) async {
    final selectedRoute = _selectedRoute;
    if (selectedRoute == null) return;

    final canSetAsUnload = _draftPickupPoint != null &&
        _isUnloadAfterPickup(selectedRoute, _draftPickupPoint!, stop.position);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8A3B5D),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Center(
                        child: Text(
                          '$stopNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Stop #$stopNumber on ${selectedRoute.name}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF67726E),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow(
                        label: 'Coordinates',
                        value:
                            '${stop.position.latitude.toStringAsFixed(5)}, ${stop.position.longitude.toStringAsFixed(5)}',
                      ),
                      _DetailRow(
                        label: 'Stop order',
                        value: '${stop.order}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (canSetAsUnload)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _draftUnloadPoint = stop.position;
                          _draftUnloadLabel = stop.name;
                          _mapSelectionMode = _PassengerMapSelectionMode.unload;
                          _statusMessage =
                              'Unload point set to ${stop.name}. You can now book this route.';
                        });
                      },
                      icon: const Icon(Icons.flag_circle),
                      label: const Text('Set as unload point'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD84315),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF7E8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFFE1A6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFFE29B2D),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _draftPickupPoint == null
                                ? 'Set your pickup point first before selecting an unload stop.'
                                : 'This stop comes before your pickup point. Choose a stop further along the route.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _canCancelRequest(PickupRequestModel request) {
    return request.status == 'pending' || request.status == 'acknowledged';
  }

  RouteStopPoint? _routeTerminalStop(RouteSummaryModel? route) {
    if (route == null || route.stopPoints.isEmpty) {
      return null;
    }
    final stops = List<RouteStopPoint>.from(route.stopPoints)
      ..sort((left, right) => left.order.compareTo(right.order));
    return stops.first;
  }

  String _rideStatusMessage(RideSessionModel ride) {
    switch (ride.status) {
      case 'waiting':
        return 'Boarding is being validated for this ride.';
      case 'onboard':
        return ride.canSendStopAlert == true
            ? 'You are onboard and can send a digital para alert.'
            : 'You are onboard for this ride.';
      case 'completed':
        return 'Drop-off completed. This ride session has been closed.';
      default:
        return ParagoFormat.statusLabel(ride.status);
    }
  }

  LatLng? _passengerEtaRequestedDestination;

  LatLng? get _passengerEtaDestination {
    final ride = _activeRide;
    if (ride != null && ride.tripSessionId == _passengerEtaTripId) {
      final latitude = ride.destinationLatitude;
      final longitude = ride.destinationLongitude;
      return latitude == null || longitude == null
          ? null
          : LatLng(latitude, longitude);
    }
    return _draftPickupPoint ?? _currentPassengerLocation;
  }

  PassengerJeepEta? get _freshPassengerEta {
    final eta = _selectedJeepEta;
    if (eta == null ||
        _passengerEtaError != null ||
        eta.expiresAt == null ||
        !DateTime.now().isBefore(eta.expiresAt!) ||
        !_sameMapPoint(
            _passengerEtaRequestedDestination, _passengerEtaDestination)) {
      return null;
    }
    return eta;
  }

  void _startPassengerEtaRefreshLoop() {
    _passengerEtaTimer?.cancel();
    _passengerEtaTimer = Timer.periodic(_passengerEtaRefreshInterval, (_) {
      unawaited(_refreshSelectedPassengerEta());
    });
  }

  void _selectPassengerJeep(TripSession trip) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedTripId = trip.id;
      _passengerEtaTripId = trip.id;
      _selectedJeepEta = null;
      _passengerEtaError = null;
      _passengerEtaLoading = true;
      _passengerEtaLastRequestedAt = null;
      _passengerEtaLastOrigin = null;
      _passengerEtaRequestSerial += 1;
    });
    unawaited(_refreshSelectedPassengerEta(force: true));
  }

  void _clearPassengerEtaSelection() {
    _passengerEtaRequestSerial += 1;
    _passengerEtaRequestInFlight = false;
    _passengerEtaTripId = null;
    _selectedJeepEta = null;
    _passengerEtaError = null;
    _passengerEtaLoading = false;
    _passengerEtaLastRequestedAt = null;
    _passengerEtaLastOrigin = null;
  }

  void _refreshPassengerEtaForTargetChange() {
    if (_passengerEtaTripId == null) {
      return;
    }
    setState(() {
      _passengerEtaRequestSerial += 1;
      _passengerEtaRequestInFlight = false;
      _selectedJeepEta = null;
      _passengerEtaError = null;
      _passengerEtaLoading = true;
      _passengerEtaLastRequestedAt = null;
    });
    unawaited(_refreshSelectedPassengerEta(force: true));
  }

  Future<void> _refreshSelectedPassengerEta({bool force = false}) async {
    final ride = _activeRide;
    if (ride != null && _passengerEtaTripId != ride.tripSessionId) {
      _passengerEtaTripId = ride.tripSessionId;
      _selectedJeepEta = null;
      _passengerEtaLastRequestedAt = null;
    }
    final tripId = _passengerEtaTripId;
    final destination = _passengerEtaDestination;
    if (tripId == null || tripId.isEmpty) {
      return;
    }
    if (destination == null) {
      if (mounted) {
        setState(() {
          _selectedJeepEta = null;
          _passengerEtaError = 'ETA unavailable';
          _passengerEtaLoading = false;
        });
      }
      return;
    }
    final now = DateTime.now();
    final lastRequestedAt = _passengerEtaLastRequestedAt;
    if (!force &&
        _sameMapPoint(_passengerEtaRequestedDestination, destination) &&
        lastRequestedAt != null &&
        now.difference(lastRequestedAt) < _passengerEtaRefreshInterval) {
      return;
    }
    if (_passengerEtaRequestInFlight) {
      return;
    }

    final trip = _tripById(tripId);
    final origin = trip == null ? null : _tripVehiclePoint(trip);
    final requestSerial = ++_passengerEtaRequestSerial;
    final destinationSnapshot = destination;
    _passengerEtaRequestInFlight = true;
    _passengerEtaLastRequestedAt = now;
    _passengerEtaLastOrigin = origin;
    if (mounted) {
      setState(() {
        _passengerEtaLoading = true;
        _passengerEtaError = null;
      });
    }

    try {
      final session = context.read<SessionController>();
      final eta = await TripService(session.apiClient).getPassengerEta(
        tripId: tripId,
        destinationLatitude: destinationSnapshot.latitude,
        destinationLongitude: destinationSnapshot.longitude,
      );
      if (!mounted ||
          requestSerial != _passengerEtaRequestSerial ||
          _passengerEtaTripId != tripId ||
          !_sameMapPoint(_passengerEtaDestination, destinationSnapshot)) {
        return;
      }
      setState(() {
        _selectedJeepEta = eta;
        _passengerEtaRequestedDestination = destinationSnapshot;
        _passengerEtaError = null;
        _passengerEtaLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          requestSerial != _passengerEtaRequestSerial ||
          _passengerEtaTripId != tripId) {
        return;
      }
      setState(() {
        _selectedJeepEta = null;
        _passengerEtaError = 'ETA unavailable';
        _passengerEtaLoading = false;
      });
    } finally {
      if (requestSerial == _passengerEtaRequestSerial) {
        _passengerEtaRequestInFlight = false;
      }
    }
  }

  void _maybeRefreshPassengerEtaForMovement(
    TripSession trip,
    LatLng nextPoint,
  ) {
    if (_passengerEtaTripId != trip.id) {
      return;
    }
    final lastRequestedAt = _passengerEtaLastRequestedAt;
    final lastOrigin = _passengerEtaLastOrigin;
    if (lastRequestedAt == null || lastOrigin == null) {
      unawaited(_refreshSelectedPassengerEta(force: true));
      return;
    }
    if (DateTime.now().difference(lastRequestedAt) <
        _passengerEtaMovementRefreshFloor) {
      return;
    }
    final movedMeters = _distance.as(
      LengthUnit.Meter,
      lastOrigin,
      nextPoint,
    );
    if (movedMeters >= _passengerEtaMovementRefreshMeters) {
      unawaited(_refreshSelectedPassengerEta(force: true));
    }
  }

  String _passengerEtaLabel() {
    final eta = _freshPassengerEta;
    if (_passengerEtaLoading && eta == null) {
      return 'ETA loading';
    }
    if (eta == null || _passengerEtaError != null) {
      return 'ETA unavailable';
    }
    final duration = _compactDurationLabel(
      eta.durationSeconds,
      fallback: 'ETA unavailable',
    );
    if (_activeRide?.tripSessionId == _passengerEtaTripId) {
      return '$duration to destination';
    }
    return _draftPickupPoint != null
        ? '$duration to pickup'
        : '$duration to you';
  }

  String _selectedJeepLocationFreshness(TripSession trip) {
    final seenAt = _selectedJeepEta?.vehicleLocationLastSeenAt ??
        _tripVehicleStates[trip.id]?.lastRealtimeUpdateAt;
    if (seenAt == null) {
      return 'Location syncing';
    }
    final age = DateTime.now().difference(seenAt);
    if (age.inSeconds < 10) {
      return 'Live now';
    }
    if (age.inSeconds < 60) {
      return 'Updated ${age.inSeconds}s ago';
    }
    return 'Location stale';
  }

  List<Marker> _tripVehicleMarkers(
    List<TripSession> routeTrips,
    TripSession? selectedTrip,
  ) {
    final visibleTrips = List<TripSession>.from(routeTrips);
    final onboardTrip = _onboardedTripForCamera();
    if (onboardTrip != null &&
        _tripVehiclePoint(onboardTrip) != null &&
        visibleTrips.every((trip) => trip.id != onboardTrip.id)) {
      visibleTrips.add(onboardTrip);
    }
    return visibleTrips
        .where((trip) => _tripVehiclePoint(trip) != null)
        .map((trip) {
      final showDetails = trip.id == _passengerEtaTripId;
      final directDistance = _distanceFromPassengerToTrip(trip);
      final etaDistance = showDetails ? _selectedJeepEta?.distanceMeters : null;
      final etaPlateNumber =
          showDetails ? _selectedJeepEta?.plateNumber.trim() : null;
      return Marker(
        point: _tripVehiclePoint(trip)!,
        width: showDetails ? 220 : (trip.id == selectedTrip?.id ? 52 : 44),
        height: showDetails ? 118 : (trip.id == selectedTrip?.id ? 52 : 44),
        alignment: Alignment.bottomCenter,
        child: _PassengerVehicleMarker(
          color: trip.id == selectedTrip?.id
              ? const Color(0xFF0F6A5F)
              : const Color(0xFF2157A5),
          size: trip.id == selectedTrip?.id ? 36 : 30,
          headingDegrees: _tripVehicleHeading(trip),
          selected: showDetails,
          plateNumber: etaPlateNumber?.isNotEmpty == true
              ? etaPlateNumber!
              : (trip.jeepneyPlateNumber ?? trip.jeepneyLabel),
          etaLabel: _passengerEtaLabel(),
          distanceLabel: _compactDistanceLabel(
            etaDistance ?? directDistance,
            fallback: 'Distance unavailable',
          ),
          seatsLabel: _availableSeatsLabel(trip),
          freshnessLabel: _selectedJeepLocationFreshness(trip),
          onTap: () => _selectPassengerJeep(trip),
        ),
      );
    }).toList(growable: false);
  }

  Widget _buildPassengerMapSurface({
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required List<TripSession> routeTrips,
  }) {
    final routePath = _routeMapPath(selectedRoute, selectedTrip);
    final tripMarkers = [
      ..._routeLandmarkMarkers(selectedRoute),
      ..._tripVehicleMarkers(routeTrips, selectedTrip),
    ];

    if (_draftPickupPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftPickupPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftPickupLabel ?? 'Selected pickup location',
            icon: Icons.person_pin_circle,
            color: const Color(0xFFE29B2D),
          ),
        ),
      );
    }
    if (_draftUnloadPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftUnloadPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftUnloadLabel ?? 'Selected unload location',
            icon: Icons.flag_circle,
            color: const Color(0xFFD84315),
          ),
        ),
      );
    }

    final selectedTripLat = selectedTrip?.jeepneyLatitude;
    final selectedTripLng = selectedTrip?.jeepneyLongitude;

    final mapCenter = _currentPassengerLocation ??
        _draftPickupPoint ??
        _draftUnloadPoint ??
        (selectedTripLat != null && selectedTripLng != null
            ? LatLng(selectedTripLat, selectedTripLng)
            : _routeCenter(selectedRoute)) ??
        _defaultMapCenter;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _passengerMapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: _currentPassengerLocation == null
                  ? (selectedRoute == null ? 13 : 14)
                  : 16,
              onMapReady: _handlePassengerMapReady,
              onPositionChanged: _handlePassengerMapPositionChanged,
              onTap: (_, point) => _onPassengerMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.parago.passenger',
              ),
              if (_currentPassengerLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentPassengerLocation!,
                      radius: _pickupFromCurrentLocationMeters,
                      useRadiusInMeter: true,
                      color: const Color(0x332157A5),
                      borderStrokeWidth: 2,
                      borderColor: const Color(0xCC2157A5),
                    ),
                    CircleMarker(
                      point: _currentPassengerLocation!,
                      radius: 10,
                      color: const Color(0xCC2157A5),
                      borderStrokeWidth: 4,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              if (routePath.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePath,
                      strokeWidth: 5,
                      color: const Color(0xFF0F6A5F),
                    ),
                  ],
                ),
              MarkerLayer(markers: tripMarkers),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerMapCard({
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required List<TripSession> routeTrips,
  }) {
    final routePath = _routeMapPath(selectedRoute, selectedTrip);
    final tripMarkers = [
      ..._routeLandmarkMarkers(selectedRoute),
      ..._tripVehicleMarkers(routeTrips, selectedTrip),
    ];

    if (_draftPickupPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftPickupPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftPickupLabel ?? 'Selected pickup location',
            icon: Icons.person_pin_circle,
            color: const Color(0xFFE29B2D),
          ),
        ),
      );
    }
    if (_draftUnloadPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftUnloadPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftUnloadLabel ?? 'Selected unload location',
            icon: Icons.flag_circle,
            color: const Color(0xFFD84315),
          ),
        ),
      );
    }

    final selectedTripLat = selectedTrip?.jeepneyLatitude;
    final selectedTripLng = selectedTrip?.jeepneyLongitude;

    final mapCenter = _currentPassengerLocation ??
        _draftPickupPoint ??
        _draftUnloadPoint ??
        (selectedTripLat != null && selectedTripLng != null
            ? LatLng(
                selectedTripLat,
                selectedTripLng,
              )
            : _routeCenter(selectedRoute)) ??
        _defaultMapCenter;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passenger live map',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              selectedRoute == null
                  ? 'Choose a route first, then tap the map to pin where you will board and unload.'
                  : 'Tap near the route to place pins. The blue radar is your 50-meter pickup zone, centered on your current location. Pickup must stay inside it and within 300 meters of the route, while unload must be pinned after pickup and within about 5 meters of the route.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('Pin pickup'),
                  selected:
                      _mapSelectionMode == _PassengerMapSelectionMode.pickup,
                  onSelected: (_) {
                    setState(() {
                      _mapSelectionMode = _PassengerMapSelectionMode.pickup;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Pin unload'),
                  selected:
                      _mapSelectionMode == _PassengerMapSelectionMode.unload,
                  onSelected: _draftPickupPoint == null
                      ? null
                      : (_) {
                          setState(() {
                            _mapSelectionMode =
                                _PassengerMapSelectionMode.unload;
                          });
                        },
                ),
                TextButton.icon(
                  onPressed: _locatingPassenger
                      ? null
                      : () => _ensureCurrentPassengerLocation(
                            forceRefresh: true,
                            recenterMap: true,
                          ),
                  icon: _locatingPassenger
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                  label: const Text('Refresh my location'),
                ),
                TextButton.icon(
                  onPressed:
                      _draftPickupPoint == null && _draftUnloadPoint == null
                          ? null
                          : () {
                              setState(() {
                                _draftPickupPoint = null;
                                _draftUnloadPoint = null;
                                _draftPickupLabel = null;
                                _draftUnloadLabel = null;
                                _mapSelectionMode =
                                    _PassengerMapSelectionMode.pickup;
                              });
                              _refreshPassengerEtaForTargetChange();
                            },
                  icon: const Icon(Icons.layers_clear_outlined),
                  label: const Text('Clear pins'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 340,
                width: double.infinity,
                child: FlutterMap(
                  mapController: _passengerMapController,
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: _currentPassengerLocation == null
                        ? (selectedRoute == null ? 13 : 14)
                        : 16,
                    onMapReady: _handlePassengerMapReady,
                    onPositionChanged: _handlePassengerMapPositionChanged,
                    onTap: (_, point) => _onPassengerMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.parago.passenger',
                    ),
                    if (_currentPassengerLocation != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _currentPassengerLocation!,
                            radius: _pickupFromCurrentLocationMeters,
                            useRadiusInMeter: true,
                            color: const Color(0x332157A5),
                            borderStrokeWidth: 2,
                            borderColor: const Color(0xCC2157A5),
                          ),
                          CircleMarker(
                            point: _currentPassengerLocation!,
                            radius: 10,
                            color: const Color(0xCC2157A5),
                            borderStrokeWidth: 4,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),
                    if (routePath.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePath,
                            strokeWidth: 5,
                            color: const Color(0xFF0F6A5F),
                          ),
                        ],
                      ),
                    MarkerLayer(markers: tripMarkers),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _DetailRow(
              label: 'Selected route',
              value: selectedRoute?.label ?? 'Choose a route below',
            ),
            _DetailRow(
              label: 'Visible jeepneys',
              value: routeTrips.length.toString(),
            ),
            _DetailRow(
              label: 'Your location',
              value: _currentPassengerLocation == null
                  ? 'Location not ready'
                  : '${_currentPassengerLocation!.latitude.toStringAsFixed(5)}, '
                      '${_currentPassengerLocation!.longitude.toStringAsFixed(5)}',
            ),
            _DetailRow(
              label: 'Pickup radar',
              value: _currentPassengerLocation == null
                  ? 'Waiting for current location'
                  : '${_pickupFromCurrentLocationMeters.toInt()} meters around you',
            ),
            _DetailRow(
              label: 'Tap mode',
              value: _mapSelectionMode == _PassengerMapSelectionMode.pickup
                  ? 'Pickup pin'
                  : 'Unload pin',
            ),
            _DetailRow(
              label: 'Pickup pin',
              value: _draftPickupPoint == null
                  ? 'Not pinned'
                  : '${_draftPickupPoint!.latitude.toStringAsFixed(5)}, '
                      '${_draftPickupPoint!.longitude.toStringAsFixed(5)}',
            ),
            _DetailRow(
              label: 'Pickup place',
              value: _draftPickupLabel ?? 'Not pinned',
            ),
            _DetailRow(
              label: 'Unload pin',
              value: _draftUnloadPoint == null
                  ? 'Not pinned'
                  : '${_draftUnloadPoint!.latitude.toStringAsFixed(5)}, '
                      '${_draftUnloadPoint!.longitude.toStringAsFixed(5)}',
            ),
            _DetailRow(
              label: 'Unload place',
              value: _draftUnloadLabel ?? 'Not pinned',
            ),
            _DetailRow(
              label: 'Estimated fare',
              value: _draftFarePreview(selectedRoute) == null
                  ? 'Pin pickup and unload first'
                  : _formatFareAmount(
                      _draftFarePreview(selectedRoute)!.amount,
                    ),
            ),
            if (_draftFarePreview(selectedRoute) != null)
              _DetailRow(
                label: 'Fare landmarks',
                value:
                    '${_draftFarePreview(selectedRoute)!.boardingStopRef} to ${_draftFarePreview(selectedRoute)!.destinationStopRef}',
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load(preferFresh: true);
      if (!mounted) return;
      _connectRealtimeSocket();
      if (mounted) {
        _showMapPromptNotification(route: _selectedRoute, force: true);
      }
      unawaited(_primeCurrentPassengerLocation());
      _startLiveRefreshLoop();
      _startPassengerEtaRefreshLoop();
    });
  }

  SessionController? _securitySession;
  String? _securitySocketToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionController>();
    if (!identical(session, _securitySession)) {
      _securitySession?.removeListener(_handleSecuritySession);
      _securitySession = session;
      _securitySocketToken = session.token;
      session.addListener(_handleSecuritySession);
    }
  }

  void _handleSecuritySession() {
    final session = _securitySession;
    if (!mounted || session == null || session.token == _securitySocketToken) {
      return;
    }
    _securitySocketToken = session.token;
    if (session.token == null) {
      _realtimeSocketService.disconnect();
      return;
    }
    _connectRealtimeSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _securitySession?.removeListener(_handleSecuritySession);
    _liveRefreshTimer?.cancel();
    _passengerEtaTimer?.cancel();
    _tripMarkerAnimationTimer?.cancel();
    _realtimeNotificationSubscription?.cancel();
    _realtimeOperationsSubscription?.cancel();
    _realtimeLocationSubscription?.cancel();
    _realtimeVehicleBatchSubscription?.cancel();
    _realtimeAnnouncementSubscription?.cancel();
    _realtimeLifecycleSubscription?.cancel();
    _dismissMapPromptNotification();
    _announcementFeedController?.dispose();
    _refreshCoordinator.dispose();
    _realtimeSocketService.dispose();
    _routeVehicleBatchReconciler.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshBookings(useCache: false, replacePending: true));
    }
  }

  void _connectRealtimeSocket() {
    final session = context.read<SessionController>();
    final token = session.token?.trim() ?? '';
    if (token.isEmpty) {
      return;
    }

    _realtimeNotificationSubscription?.cancel();
    _realtimeOperationsSubscription?.cancel();
    _realtimeLocationSubscription?.cancel();
    _realtimeVehicleBatchSubscription?.cancel();
    _realtimeAnnouncementSubscription?.cancel();
    _realtimeLifecycleSubscription?.cancel();

    _realtimeNotificationSubscription =
        _realtimeSocketService.notificationCreatedStream.listen(
      _handleRealtimeSocketNotification,
    );
    _realtimeOperationsSubscription =
        _realtimeSocketService.operationsChangedStream.listen(
      _handleRealtimeOperationsChanged,
    );

    _realtimeLocationSubscription =
        _realtimeSocketService.jeepneyLocationStream.listen(
      (event) {
        if (!AppConfig.enableRouteLocationBatches) {
          unawaited(_handleRealtimeLocationUpdate(event));
        }
      },
    );
    _realtimeVehicleBatchSubscription =
        _realtimeSocketService.routeVehicleBatchStream.listen(
      (event) {
        if (AppConfig.enableRouteLocationBatches) {
          unawaited(_handleRealtimeVehicleBatch(event));
        }
      },
    );
    _realtimeAnnouncementSubscription =
        _realtimeSocketService.announcementActivityStream.listen(
      (_) => unawaited(_refreshAnnouncements()),
    );
    _realtimeLifecycleSubscription =
        _realtimeSocketService.lifecycleStream.listen(
      _handleRealtimeSocketLifecycle,
    );

    _realtimeSocketService.connect(
      apiBaseUrl: session.apiClient.baseUrl,
      token: token,
    );

    _syncRealtimeRouteSubscription(
      previousRouteId: null,
      nextRouteId: _selectedRouteId,
    );
  }

  Future<void> _handleRealtimeOperationsChanged(
    Map<String, dynamic> event,
  ) async {
    if (!mounted || event['type']?.toString() != 'trip.occupancy.updated') {
      return;
    }
    final tripId = event['tripId']?.toString().trim() ?? '';
    if (tripId.isEmpty || !_trips.any((trip) => trip.id == tripId)) {
      return;
    }
    // Reconcile from the backend so occupancy, capacity, and request
    // availability are all updated together instead of applying a partial
    // event over a possibly newer trip snapshot.
    await _refreshTripsOnly(useCache: false, replacePending: true);
  }

  AnnouncementFeedController _announcementFeed() {
    final existing = _announcementFeedController;
    if (existing != null) return existing;
    final session = context.read<SessionController>();
    return _announcementFeedController =
        AnnouncementFeedController(AnnouncementService(session.apiClient));
  }

  void _refreshAnnouncementsIfDue({bool useCache = false}) {
    final lastAttempt = _lastAnnouncementRefreshAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < const Duration(seconds: 30)) {
      return;
    }
    unawaited(_refreshAnnouncements(useCache: useCache));
  }

  Future<void> _refreshAnnouncements({bool useCache = false}) async {
    if (!mounted) return;
    _lastAnnouncementRefreshAttemptAt = DateTime.now();
    final items = await _announcementFeed().refresh(useCache: useCache);
    if (mounted) setState(() => _announcements = items);
  }

  Future<void> _dismissAnnouncement(AnnouncementModel announcement) async {
    final feed = _announcementFeed();
    final resultFuture = feed.dismiss(announcement);
    setState(() => _announcements = feed.items);
    final result = await resultFuture;
    if (!mounted) return;
    setState(() => _announcements = feed.items);
    if (result.status == AnnouncementDismissStatus.failed) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not dismiss announcement. '
            '${ActionFeedback.messageOf(result.error!)}',
          ),
        ),
      );
    }
  }

  Future<void> _showPassengerNoticesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, controller) => Material(
          color: const Color(0xFFFFFEFB),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9DDD7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Notices',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              if (_announcements.isEmpty && _notifications.isEmpty)
                const Text('No notices yet.'),
              for (final announcement in _announcements) ...[
                AnnouncementCard(
                  announcement: announcement,
                  onDismiss: () {
                    Navigator.pop(sheetContext);
                    unawaited(_dismissAnnouncement(announcement));
                  },
                ),
                const SizedBox(height: 12),
              ],
              for (final notification in _notifications) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      notification.isRead
                          ? Icons.mark_email_read_outlined
                          : Icons.notifications_active,
                    ),
                    title: Text(notification.title, softWrap: true),
                    subtitle: Text(
                      '${notification.body}\n'
                      '${ParagoFormat.relative(notification.createdAt)}',
                      softWrap: true,
                    ),
                    isThreeLine: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _ensureRealtimeSocketConnection() {
    if (!mounted || _realtimeSocketService.isConnected) {
      return;
    }
    _connectRealtimeSocket();
  }

  void _handleRealtimeSocketLifecycle(RealtimeSocketLifecycleEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case RealtimeSocketLifecycleType.connected:
        return;
      case RealtimeSocketLifecycleType.disconnected:
        _realtimeReconciliationGate.disconnected();
        return;
      case RealtimeSocketLifecycleType.ready:
        _realtimeReconciliationGate.socketReady();
        unawaited(_reconcileAfterSocketReady());
    }
  }

  Future<void> _reconcileAfterSocketReady() {
    final active = _socketReconciliationOperation;
    if (active != null) {
      _socketReconciliationQueued = true;
      return active;
    }
    late final Future<void> operation;
    operation = _performSocketReconciliation();
    _socketReconciliationOperation = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearSocketReconciliation(operation),
        onError: (Object _, StackTrace __) =>
            _clearSocketReconciliation(operation),
      ),
    );
    return operation;
  }

  void _clearSocketReconciliation(Future<void> operation) {
    if (identical(_socketReconciliationOperation, operation)) {
      _socketReconciliationOperation = null;
    }
  }

  Future<void> _performSocketReconciliation() async {
    do {
      _socketReconciliationQueued = false;
      _realtimeReconciliationGate.socketReady();
      final routeAtStart = _selectedRouteId;
      final refreshed = await _refreshTripsOnly(
        useCache: false,
        replacePending: true,
      );
      if (!mounted || !refreshed || routeAtStart != _selectedRouteId) return;
      final buffered = _realtimeReconciliationGate.completeSnapshot();
      final batch = buffered.latestBatch;
      if (batch != null && AppConfig.enableRouteLocationBatches) {
        await _handleRealtimeVehicleBatch(batch);
      }
      if (!AppConfig.enableRouteLocationBatches) {
        for (final location in buffered.legacyLocations) {
          await _handleRealtimeLocationUpdate(location);
        }
      }
    } while (_socketReconciliationQueued && mounted);
    unawaited(_refreshPassengerMetadata(silent: true));
    _refreshAnnouncementsIfDue(useCache: false);
  }

  void _syncRealtimeRouteSubscription({
    required String? previousRouteId,
    required String? nextRouteId,
  }) {
    final previous = previousRouteId?.trim() ?? '';
    final next = nextRouteId?.trim() ?? '';
    if (previous.isNotEmpty && previous != next) {
      _clearRealtimeRouteState(next);
    }
    _routeVehicleBatchReconciler.selectRoute(next);
    if (previous.isNotEmpty && previous != next) {
      _realtimeSocketService.unsubscribeFromRoute(previous);
    }
    if (next.isNotEmpty) {
      _realtimeSocketService.subscribeToRoute(next);
    }
  }

  void _clearRealtimeRouteState(String nextRouteId) {
    final keepTripIds = _trips
        .where((trip) => trip.routeId == nextRouteId)
        .map((trip) => trip.id)
        .toSet();
    _tripVehicleStates
        .removeWhere((tripId, _) => !keepTripIds.contains(tripId));
    _tripMarkerAnimations
        .removeWhere((tripId, _) => !keepTripIds.contains(tripId));
    _routeVehicleBatchReconciler.selectRoute(nextRouteId);
    _realtimeReconciliationGate.routeChanged();
    _clearPassengerEtaSelection();
    _passengerEtaTimer?.cancel();
    _startPassengerEtaRefreshLoop();
    _stopTripMarkerAnimationLoopIfIdle();
  }

  Future<void> _handleRealtimeSocketNotification(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }

    _dashboardLoadGeneration += 1;
    final notification = NotificationModel.fromJson(event);
    if (notification.id.isEmpty) {
      return;
    }

    final alreadyKnown = _knownNotificationIds.contains(notification.id) ||
        _notifications.any((item) => item.id == notification.id);
    final applied = _applyRealtimePassengerNotification(notification);
    _knownNotificationIds = {..._knownNotificationIds, notification.id};
    _realtimePrimed = true;

    if (!applied) {
      await Future.wait<void>([
        _refreshBookings(useCache: false, replacePending: true),
        _refreshNotifications(
          useCache: false,
          silent: true,
          replacePending: true,
        ),
      ]);
      return;
    }

    if (!alreadyKnown) {
      _showPassengerRealtimeSnackBar(notification);
    }
  }

  Future<void> _handleRealtimeLocationUpdate(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }
    if (_realtimeReconciliationGate.awaitingSnapshot) {
      _realtimeReconciliationGate.bufferLegacy(event);
      return;
    }

    final receivedAt = DateTime.now();
    const policy = PassengerVehicleReconciliationPolicy();
    final initialDecision = policy.decide(
      payload: event,
      trips: _trips,
      receivedAt: receivedAt,
    );
    if (!initialDecision.hasValidEvent) {
      return;
    }
    final tripIndex = initialDecision.tripIndex;
    if (tripIndex < 0) {
      await _refreshFromSocketEvent();
      return;
    }

    final trip = _trips[tripIndex];
    final previousState = _tripVehicleStates[trip.id];
    final decision = policy.decide(
      payload: event,
      trips: _trips,
      receivedAt: receivedAt,
      previousSampleAt: previousState?.lastAuthoritativeSampleAt,
    );
    if (!decision.shouldApply) {
      return;
    }
    _applyRealtimeVehicleEvents(<PassengerVehicleLocationEvent>[
      decision.event!,
    ]);
  }

  Future<void> _handleRealtimeVehicleBatch(
    Map<String, dynamic> payload,
  ) async {
    if (!mounted || !AppConfig.enableRouteLocationBatches) return;
    if (_realtimeReconciliationGate.awaitingSnapshot) {
      _realtimeReconciliationGate.bufferBatch(payload);
      return;
    }
    final decision = _routeVehicleBatchReconciler.reconcile(
      payload: payload,
      selectedRouteId: _selectedRouteId,
      trips: _trips,
    );
    if (!decision.acceptedSequence) return;
    if (decision.acceptedVehicles.isNotEmpty) {
      _applyRealtimeVehicleEvents(decision.acceptedVehicles);
    }
    if (decision.unmatchedVehicleCount > 0) {
      await _refreshFromSocketEvent();
    }
  }

  void _applyRealtimeVehicleEvents(
    List<PassengerVehicleLocationEvent> events,
  ) {
    if (!mounted || events.isEmpty) return;
    final receivedAt = DateTime.now();
    const policy = PassengerVehicleReconciliationPolicy();
    final etaUpdates = <(TripSession, LatLng)>[];
    final focusedTripId = _selectedTrip?.id;
    (String, LatLng)? cameraUpdate;
    var animationAdded = false;

    setState(() {
      for (final locationEvent in events) {
        final tripIndex = policy.findTripIndex(_trips, locationEvent);
        if (tripIndex < 0) continue;
        final trip = _trips[tripIndex];
        final previousState = _tripVehicleStates[trip.id];
        final nextPoint = LatLng(
          locationEvent.latitude,
          locationEvent.longitude,
        );
        final currentPoint = _tripVehiclePoint(trip);
        final currentHeading = _tripVehicleHeading(trip);
        final sampleAt = locationEvent.sampleAt;
        final sampleGap = _motionSampleGap(
          sampleAt: sampleAt,
          previousSampleAt: previousState?.lastAuthoritativeSampleAt,
          defaultDuration: _tripMarkerAnimationDefaultDuration,
          minDuration: _tripMarkerAnimationMinDuration,
          maxDuration: _tripMarkerAnimationMaxDuration,
        );

        if (currentPoint == null) {
          _mutateTripMarkerPosition(
            tripIndex,
            nextPoint,
            headingDegrees: currentHeading,
            lastRealtimeUpdateAt: receivedAt,
            sampleAt: sampleAt,
            expectedSampleGap: sampleGap,
          );
          if (trip.id == focusedTripId) {
            cameraUpdate = (trip.id, nextPoint);
          }
          etaUpdates.add((trip, nextPoint));
          continue;
        }

        final distanceMeters = Geolocator.distanceBetween(
          currentPoint.latitude,
          currentPoint.longitude,
          nextPoint.latitude,
          nextPoint.longitude,
        );
        if (distanceMeters < _tripMarkerJitterMeters) {
          _mutateTripVehicleRealtimeTimestamp(
            trip.id,
            receivedAt,
            sampleAt: sampleAt,
            expectedSampleGap: sampleGap,
          );
          continue;
        }

        etaUpdates.add((trip, nextPoint));
        final calculatedHeading = _resolveTripMarkerHeading(
          previousPoint: currentPoint,
          nextPoint: nextPoint,
          currentHeading: currentHeading,
        );
        final suppliedHeading = locationEvent.headingDegrees;
        final suppliedSpeed = locationEvent.speedMetersPerSecond;
        final nextHeading = suppliedHeading != null &&
                suppliedHeading.isFinite &&
                suppliedSpeed != null &&
                suppliedSpeed > 0
            ? _normalizeHeading(suppliedHeading)
            : calculatedHeading;
        final calculatedSpeed = _metersPerSecond(distanceMeters, sampleGap);
        final speedMetersPerSecond = suppliedSpeed != null && suppliedSpeed > 0
            ? suppliedSpeed
            : calculatedSpeed;

        if (_shouldSnapTripMarkerPosition(
          distanceMeters: distanceMeters,
          sampleGap: sampleGap,
        )) {
          _mutateTripMarkerPosition(
            tripIndex,
            nextPoint,
            headingDegrees: nextHeading,
            lastRealtimeUpdateAt: receivedAt,
            sampleAt: sampleAt,
            expectedSampleGap: sampleGap,
            speedMetersPerSecond: speedMetersPerSecond ?? 0,
            bearingDegrees: nextHeading,
          );
          if (trip.id == focusedTripId) {
            cameraUpdate = (trip.id, nextPoint);
          }
          continue;
        }

        final animationDuration = _tripMarkerAnimationDuration(
          distanceMeters: distanceMeters,
          sampleGap: sampleGap,
        );
        _tripVehicleStates[trip.id] = _TripVehicleMotionState(
          renderedPosition: currentPoint,
          targetPosition: nextPoint,
          renderedHeading: currentHeading ?? nextHeading,
          targetHeading: nextHeading ?? currentHeading,
          lastRealtimeUpdateAt: receivedAt,
          previousAuthoritativeSampleAt:
              previousState?.lastAuthoritativeSampleAt,
          lastAuthoritativeSampleAt: sampleAt,
          expectedSampleGap: sampleGap,
          lastReliableSpeedMetersPerSecond: speedMetersPerSecond,
          lastReliableBearingDegrees: nextHeading ?? currentHeading,
          isProjected: false,
          projectionHandoffStarted: false,
        );
        _tripMarkerAnimations[trip.id] = _TripMarkerAnimation(
          from: currentPoint,
          to: nextPoint,
          fromHeading: currentHeading ?? nextHeading,
          toHeading: nextHeading ?? currentHeading,
          startedAt: receivedAt,
          duration: animationDuration,
          isProjection: false,
        );
        if (trip.id == focusedTripId) {
          cameraUpdate = (trip.id, currentPoint);
        }
        animationAdded = true;
      }
    });

    for (final update in etaUpdates) {
      _maybeRefreshPassengerEtaForMovement(update.$1, update.$2);
    }
    final nextCameraUpdate = cameraUpdate;
    if (nextCameraUpdate != null) {
      _syncPassengerSelectedTripCamera(
        tripId: nextCameraUpdate.$1,
        target: nextCameraUpdate.$2,
      );
    }
    if (animationAdded) {
      _ensureTripMarkerAnimationLoop();
    } else {
      _stopTripMarkerAnimationLoopIfIdle();
    }
  }

  void _mutateTripMarkerPosition(
    int tripIndex,
    LatLng point, {
    double? headingDegrees,
    DateTime? lastRealtimeUpdateAt,
    DateTime? sampleAt,
    Duration? expectedSampleGap,
    double? speedMetersPerSecond,
    double? bearingDegrees,
  }) {
    if (tripIndex < 0 || tripIndex >= _trips.length) return;
    final trip = _trips[tripIndex];
    _tripMarkerAnimations.remove(trip.id);
    final previousState = _tripVehicleStates[trip.id];
    final resolvedHeading = headingDegrees ??
        previousState?.targetHeading ??
        previousState?.renderedHeading;
    _tripVehicleStates[trip.id] = _TripVehicleMotionState(
      renderedPosition: point,
      targetPosition: point,
      renderedHeading: resolvedHeading,
      targetHeading: resolvedHeading,
      lastRealtimeUpdateAt:
          lastRealtimeUpdateAt ?? previousState?.lastRealtimeUpdateAt,
      previousAuthoritativeSampleAt: previousState?.lastAuthoritativeSampleAt,
      lastAuthoritativeSampleAt:
          sampleAt ?? previousState?.lastAuthoritativeSampleAt,
      expectedSampleGap: expectedSampleGap ??
          previousState?.expectedSampleGap ??
          _tripMarkerAnimationDefaultDuration,
      lastReliableSpeedMetersPerSecond: speedMetersPerSecond ??
          previousState?.lastReliableSpeedMetersPerSecond,
      lastReliableBearingDegrees: bearingDegrees ??
          resolvedHeading ??
          previousState?.lastReliableBearingDegrees,
      isProjected: false,
      projectionHandoffStarted: false,
    );
  }

  void _mutateTripVehicleRealtimeTimestamp(
    String tripId,
    DateTime timestamp, {
    DateTime? sampleAt,
    Duration? expectedSampleGap,
  }) {
    final currentState = _tripVehicleStates[tripId];
    if (currentState == null) return;
    _tripVehicleStates[tripId] = currentState.copyWith(
      lastRealtimeUpdateAt: timestamp,
      previousAuthoritativeSampleAt: currentState.lastAuthoritativeSampleAt,
      lastAuthoritativeSampleAt:
          sampleAt ?? currentState.lastAuthoritativeSampleAt,
      expectedSampleGap: expectedSampleGap ?? currentState.expectedSampleGap,
      lastReliableSpeedMetersPerSecond: 0,
      isProjected: false,
      projectionHandoffStarted: false,
    );
  }

  void _ensureTripMarkerAnimationLoop() {
    if (_tripMarkerAnimationTimer != null) {
      return;
    }

    _tripMarkerAnimationTimer = Timer.periodic(_tripMarkerAnimationTick, (_) {
      if (!mounted) {
        _tripMarkerAnimationTimer?.cancel();
        _tripMarkerAnimationTimer = null;
        return;
      }
      _advanceTripMarkerAnimations();
    });
  }

  void _advanceTripMarkerAnimations() {
    if (_tripMarkerAnimations.isEmpty) {
      _stopTripMarkerAnimationLoopIfIdle();
      return;
    }

    final now = DateTime.now();
    final updatedStates =
        Map<String, _TripVehicleMotionState>.from(_tripVehicleStates);
    final completedTripIds = <String>[];
    final projectionStarts = <_TripProjectionMotion>[];
    final focusedTripId = _selectedTrip?.id;
    LatLng? followTarget;
    var changed = false;

    for (final entry in _tripMarkerAnimations.entries) {
      final tripId = entry.key;
      final animation = entry.value;
      final state = updatedStates[tripId];
      if (state == null) {
        completedTripIds.add(tripId);
        continue;
      }

      final elapsedMicros = now.difference(animation.startedAt).inMicroseconds;
      final durationMicros = animation.duration.inMicroseconds;
      final progress = durationMicros <= 0
          ? 1.0
          : (elapsedMicros / durationMicros).clamp(0.0, 1.0).toDouble();
      final interpolatedPoint = _lerpLatLng(
        animation.from,
        animation.to,
        progress,
      );
      final headingProgress = Curves.easeOutCubic.transform(progress);
      final interpolatedHeading =
          animation.fromHeading == null || animation.toHeading == null
              ? (animation.toHeading ??
                  animation.fromHeading ??
                  state.renderedHeading)
              : _lerpHeading(
                  animation.fromHeading!,
                  animation.toHeading!,
                  headingProgress,
                );

      if (!animation.isProjection &&
          !state.projectionHandoffStarted &&
          progress >= _tripProjectionHandoffThreshold) {
        final handoffState = state.copyWith(
          renderedPosition: interpolatedPoint,
          renderedHeading: interpolatedHeading,
          targetPosition: animation.to,
          targetHeading: animation.toHeading ?? state.targetHeading,
          isProjected: false,
          projectionHandoffStarted: true,
        );
        final projection = _startTripProjection(
          tripId: tripId,
          state: handoffState,
          authoritativeTargetPoint: animation.to,
          startedAt: now,
          fromPoint: interpolatedPoint,
          fromHeading: interpolatedHeading,
          remainingAuthoritativeDuration: Duration(
            microseconds: math.max(durationMicros - elapsedMicros, 0),
          ),
        );
        updatedStates[tripId] = handoffState;
        changed = true;
        if (projection != null) {
          projectionStarts.add(projection);
          continue;
        }
      }

      final currentState = updatedStates[tripId] ?? state;

      if (currentState.renderedPosition != interpolatedPoint ||
          currentState.renderedHeading != interpolatedHeading) {
        updatedStates[tripId] = currentState.copyWith(
          renderedPosition: interpolatedPoint,
          renderedHeading: interpolatedHeading,
          targetPosition: animation.to,
          targetHeading: animation.toHeading ?? currentState.targetHeading,
          lastRealtimeUpdateAt: currentState.lastRealtimeUpdateAt,
          isProjected: animation.isProjection,
          projectionHandoffStarted: currentState.projectionHandoffStarted,
        );
        if (focusedTripId == tripId) {
          followTarget = interpolatedPoint;
        }
        changed = true;
      }

      if (progress >= 1.0) {
        final completedState = updatedStates[tripId]?.copyWith(
              renderedPosition: animation.to,
              targetPosition: animation.to,
              renderedHeading:
                  animation.toHeading ?? updatedStates[tripId]?.renderedHeading,
              targetHeading:
                  animation.toHeading ?? updatedStates[tripId]?.targetHeading,
              isProjected: animation.isProjection,
              projectionHandoffStarted: true,
            ) ??
            currentState;
        updatedStates[tripId] = completedState;
        if (focusedTripId == tripId) {
          followTarget = animation.to;
        }
        completedTripIds.add(tripId);
        changed = true;
      }
    }

    if (completedTripIds.isNotEmpty) {
      for (final tripId in completedTripIds) {
        _tripMarkerAnimations.remove(tripId);
      }
    }
    if (projectionStarts.isNotEmpty) {
      for (final projection in projectionStarts) {
        _tripMarkerAnimations[projection.tripId] = projection.animation;
      }
    }

    if (changed && mounted) {
      setState(() {
        _tripVehicleStates
          ..clear()
          ..addAll(updatedStates);
      });
    }

    if (followTarget != null) {
      _syncPassengerSelectedTripCamera(
        tripId: focusedTripId,
        target: followTarget,
      );
    }

    _stopTripMarkerAnimationLoopIfIdle();
  }

  void _pruneTripMarkerAnimations() {
    final activeTripIds = _trips.map((trip) => trip.id).toSet();
    _tripMarkerAnimations.removeWhere(
      (tripId, _) => !activeTripIds.contains(tripId),
    );
    _tripVehicleStates.removeWhere(
      (tripId, _) => !activeTripIds.contains(tripId),
    );
    _stopTripMarkerAnimationLoopIfIdle();
  }

  void _reconcileTripVehicleStates(List<TripSession> trips) {
    final activeTripIds = trips.map((trip) => trip.id).toSet();
    final now = DateTime.now();
    var changed = false;

    _tripVehicleStates.removeWhere((tripId, _) {
      final shouldRemove = !activeTripIds.contains(tripId);
      changed = changed || shouldRemove;
      return shouldRemove;
    });

    for (final trip in trips) {
      final canonicalPoint = _canonicalTripVehiclePoint(trip);
      final existingState = _tripVehicleStates[trip.id];
      final preserveLive = _shouldPreserveRealtimeVehicleState(
        trip.id,
        now: now,
      );
      if (preserveLive) {
        continue;
      }

      if (canonicalPoint == null) {
        if (existingState != null) {
          _tripVehicleStates.remove(trip.id);
          _tripMarkerAnimations.remove(trip.id);
          changed = true;
        }
        continue;
      }

      final nextState = _TripVehicleMotionState(
        renderedPosition: canonicalPoint,
        targetPosition: canonicalPoint,
        renderedHeading: existingState?.renderedHeading,
        targetHeading:
            existingState?.targetHeading ?? existingState?.renderedHeading,
        lastRealtimeUpdateAt: existingState?.lastRealtimeUpdateAt,
        previousAuthoritativeSampleAt:
            existingState?.previousAuthoritativeSampleAt,
        lastAuthoritativeSampleAt: existingState?.lastAuthoritativeSampleAt,
        expectedSampleGap: existingState?.expectedSampleGap ??
            _tripMarkerAnimationDefaultDuration,
        lastReliableSpeedMetersPerSecond:
            existingState?.lastReliableSpeedMetersPerSecond,
        lastReliableBearingDegrees: existingState?.lastReliableBearingDegrees,
        isProjected: false,
        projectionHandoffStarted: false,
      );
      if (existingState != nextState) {
        _tripVehicleStates[trip.id] = nextState;
        _tripMarkerAnimations.remove(trip.id);
        changed = true;
      }
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  bool _shouldPreserveRealtimeVehicleState(
    String tripId, {
    DateTime? now,
  }) {
    if (!_realtimeSocketService.isConnected) {
      return false;
    }
    final currentState = _tripVehicleStates[tripId];
    final lastRealtimeUpdateAt = currentState?.lastRealtimeUpdateAt;
    if (lastRealtimeUpdateAt == null) {
      return false;
    }
    return (now ?? DateTime.now()).difference(lastRealtimeUpdateAt) <=
        _tripRealtimeStaleAfter;
  }

  LatLng? _canonicalTripVehiclePoint(TripSession trip) {
    if (trip.jeepneyLatitude == null || trip.jeepneyLongitude == null) {
      return null;
    }
    return LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!);
  }

  LatLng? _tripVehiclePoint(TripSession trip) {
    return _tripVehicleStates[trip.id]?.renderedPosition ??
        _canonicalTripVehiclePoint(trip);
  }

  double? _tripVehicleHeading(TripSession trip) {
    return _tripVehicleStates[trip.id]?.renderedHeading;
  }

  void _stopTripMarkerAnimationLoopIfIdle() {
    if (_tripMarkerAnimations.isNotEmpty) {
      return;
    }
    _tripMarkerAnimationTimer?.cancel();
    _tripMarkerAnimationTimer = null;
  }

  Duration _tripMarkerAnimationDuration({
    required double distanceMeters,
    required Duration sampleGap,
  }) {
    final cadenceMilliseconds = (sampleGap.inMilliseconds * 0.98).round();
    final distanceMilliseconds = (420 + (distanceMeters * 16)).round();
    final clampedMilliseconds = (cadenceMilliseconds > 0
            ? cadenceMilliseconds
            : math.max(
                distanceMilliseconds,
                _tripMarkerAnimationDefaultDuration.inMilliseconds,
              ))
        .clamp(
      _tripMarkerAnimationMinDuration.inMilliseconds,
      _tripMarkerAnimationMaxDuration.inMilliseconds,
    );
    return Duration(milliseconds: clampedMilliseconds);
  }

  Duration _motionSampleGap({
    required DateTime sampleAt,
    required DateTime? previousSampleAt,
    required Duration defaultDuration,
    required Duration minDuration,
    required Duration maxDuration,
  }) {
    if (previousSampleAt == null) {
      return defaultDuration;
    }
    final rawGap = sampleAt.difference(previousSampleAt);
    final gapMilliseconds = rawGap.inMilliseconds;
    if (gapMilliseconds <= 0) {
      return defaultDuration;
    }
    return Duration(
      milliseconds: gapMilliseconds.clamp(
        minDuration.inMilliseconds,
        maxDuration.inMilliseconds,
      ),
    );
  }

  bool _shouldSnapTripMarkerPosition({
    required double distanceMeters,
    required Duration sampleGap,
  }) {
    final gapSeconds = sampleGap.inMilliseconds / 1000;
    final cadenceAwareThreshold = gapSeconds.isFinite && gapSeconds > 0
        ? gapSeconds * _tripMarkerSnapSpeedAllowanceMetersPerSecond
        : _tripMarkerSnapThresholdMeters;
    final snapThreshold = math.max(
      _tripMarkerSnapThresholdMeters,
      cadenceAwareThreshold,
    );
    return distanceMeters >= snapThreshold;
  }

  double? _metersPerSecond(double distanceMeters, Duration sampleGap) {
    final seconds = sampleGap.inMilliseconds / 1000;
    if (!seconds.isFinite || seconds <= 0) {
      return null;
    }
    final metersPerSecond = distanceMeters / seconds;
    return metersPerSecond.isFinite ? metersPerSecond : null;
  }

  _TripProjectionMotion? _startTripProjection({
    required String tripId,
    required _TripVehicleMotionState state,
    required LatLng authoritativeTargetPoint,
    required DateTime startedAt,
    required LatLng fromPoint,
    required double? fromHeading,
    required Duration remainingAuthoritativeDuration,
  }) {
    final bearingDegrees =
        state.lastReliableBearingDegrees ?? state.targetHeading ?? fromHeading;
    final speedMetersPerSecond = state.lastReliableSpeedMetersPerSecond;
    if (bearingDegrees == null ||
        speedMetersPerSecond == null ||
        !speedMetersPerSecond.isFinite ||
        speedMetersPerSecond < _tripProjectionMinSpeedMetersPerSecond) {
      return null;
    }

    final baseProjectionDuration =
        state.expectedSampleGap < _tripProjectionMaxDuration
            ? state.expectedSampleGap
            : _tripProjectionMaxDuration;
    final projectionDistanceMeters = math.min(
      _tripProjectionMaxDistanceMeters,
      speedMetersPerSecond * (baseProjectionDuration.inMilliseconds / 1000),
    );
    if (projectionDistanceMeters < _tripMarkerJitterMeters) {
      return null;
    }

    final to = _offsetLatLng(
      authoritativeTargetPoint,
      bearingDegrees,
      projectionDistanceMeters,
    );
    final projectionDuration =
        remainingAuthoritativeDuration + baseProjectionDuration;
    final animation = _TripMarkerAnimation(
      from: fromPoint,
      to: to,
      fromHeading: fromHeading ?? state.targetHeading ?? state.renderedHeading,
      toHeading: bearingDegrees,
      startedAt: startedAt,
      duration: projectionDuration,
      isProjection: true,
    );
    final nextState = state.copyWith(
      renderedPosition: fromPoint,
      targetPosition: to,
      renderedHeading:
          fromHeading ?? state.targetHeading ?? state.renderedHeading,
      targetHeading: bearingDegrees,
      isProjected: true,
      projectionHandoffStarted: true,
    );
    return _TripProjectionMotion(
      tripId: tripId,
      state: nextState,
      animation: animation,
    );
  }

  LatLng _lerpLatLng(LatLng from, LatLng to, double t) {
    return LatLng(
      from.latitude + ((to.latitude - from.latitude) * t),
      from.longitude + ((to.longitude - from.longitude) * t),
    );
  }

  LatLng _offsetLatLng(
    LatLng origin,
    double bearingDegrees,
    double distanceMeters,
  ) {
    const earthRadiusMeters = 6371000.0;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = origin.latitude * math.pi / 180;
    final lon1 = origin.longitude * math.pi / 180;
    final sinLat1 = math.sin(lat1);
    final cosLat1 = math.cos(lat1);
    final sinAngularDistance = math.sin(angularDistance);
    final cosAngularDistance = math.cos(angularDistance);
    final lat2 = math.asin(
      sinLat1 * cosAngularDistance +
          cosLat1 * sinAngularDistance * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * sinAngularDistance * cosLat1,
          cosAngularDistance - sinLat1 * math.sin(lat2),
        );

    return LatLng(
      lat2 * 180 / math.pi,
      lon2 * 180 / math.pi,
    );
  }

  double? _resolveTripMarkerHeading({
    required LatLng previousPoint,
    required LatLng nextPoint,
    required double? currentHeading,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      previousPoint.latitude,
      previousPoint.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );
    if (distanceMeters < 1) {
      return currentHeading;
    }
    return _bearingDegrees(previousPoint, nextPoint);
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return _normalizeHeading(bearing);
  }

  double _normalizeHeading(double headingDegrees) {
    final normalized = headingDegrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _shortestHeadingDelta(double from, double to) {
    return ((_normalizeHeading(to) - _normalizeHeading(from) + 540) % 360) -
        180;
  }

  double _lerpHeading(double from, double to, double t) {
    return _normalizeHeading(from + (_shortestHeadingDelta(from, to) * t));
  }

  Future<void> _refreshFromSocketEvent() async {
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    if (_lastSocketRefreshAt != null &&
        now.difference(_lastSocketRefreshAt!) < _socketRefreshThrottle) {
      return;
    }
    _lastSocketRefreshAt = now;
    await _refreshTripsOnly(useCache: false);
  }

  void _expandPassengerSheet() {
    if (mounted && _passengerSheetCollapsed) {
      setState(() => _passengerSheetCollapsed = false);
    }
    if (!_sheetController.isAttached) {
      return;
    }
    unawaited(
      _sheetController.animateTo(
        _sheetPeekSize,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _collapsePassengerSheet() {
    if (mounted && !_passengerSheetCollapsed) {
      setState(() => _passengerSheetCollapsed = true);
    }
    if (!_sheetController.isAttached) {
      return;
    }
    unawaited(
      _sheetController.animateTo(
        _sheetCollapsedSize,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _togglePassengerSheet() {
    if (_passengerSheetCollapsed) {
      _expandPassengerSheet();
      return;
    }
    _collapsePassengerSheet();
  }

  Future<void> _handleDashboardAction(
    SessionController session,
    String action,
  ) async {
    switch (action) {
      case 'profile':
        await _openProfileSettings(session);
        return;
      case 'mark_all_read':
        await _markAllRead();
        return;
      case 'logout':
        await _confirmPassengerLogout(session);
        return;
      case 'refresh':
        await _refreshPassengerData();
        return;
    }
  }

  void _openSideDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _refreshPassengerData() async {
    final session = context.read<SessionController>();
    await session.apiClient.clearCache();
    await _load();
  }

  Future<void> _confirmPassengerLogout(SessionController session) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of the passenger application?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await session.logout();
    }
  }

  Future<void> _openProfileSettings(SessionController session) async {
    final profileService = PassengerProfileService(session.apiClient);
    final PassengerProfileModel profile =
        await profileService.getProfile(useCache: true);
    if (!mounted) {
      return;
    }

    final activeRoutes = _routes
        .where((route) => route.status == 'active')
        .toList(growable: false);

    final result = await showModalBottomSheet<_PassengerProfileSettingsResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PassengerProfileSettingsSheet(
        profile: profile,
        activeRoutes: activeRoutes,
        profileService: profileService,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final selectedRouteId = result.selectedRouteId;
    await session.refreshCurrentUser();
    if (!mounted) {
      return;
    }

    if (selectedRouteId != null &&
        selectedRouteId.isNotEmpty &&
        _routes.any((route) => route.id == selectedRouteId)) {
      final previousRouteId = _selectedRouteId;
      setState(() {
        if (_selectedRouteId != selectedRouteId) {
          _clearPassengerEtaSelection();
        }
        _selectedRouteId = selectedRouteId;
      });
      _syncRealtimeRouteSubscription(
        previousRouteId: previousRouteId,
        nextRouteId: selectedRouteId,
      );
    }

    await _load(silent: true);
    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = 'Passenger profile updated successfully.';
    });
  }

  Future<void> _openRoutePicker() async {
    final routes = _routes
        .where((route) => route.status == 'active')
        .toList(growable: false);
    final fallbackRoutes = routes.isEmpty ? _routes : routes;
    if (fallbackRoutes.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'No active routes are available right now.';
      });
      return;
    }

    final selectedRouteId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                'Choose a route',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select the route you want to book so the map and quick actions stay focused.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              for (final route in fallbackRoutes) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: route.id == _selectedRouteId
                        ? const Color(0xFF0F6A5F)
                        : const Color(0xFFEAF5F2),
                    foregroundColor: route.id == _selectedRouteId
                        ? Colors.white
                        : const Color(0xFF0F6A5F),
                    child: Text(
                      route.code.isEmpty
                          ? '${route.stopsCount}'
                          : route.code.characters.first,
                    ),
                  ),
                  title: Text(route.label),
                  subtitle: Text(
                    '${route.stopsCount} stops · ${_routeTrips(route.id).length} live jeep${_routeTrips(route.id).length == 1 ? '' : 's'}',
                  ),
                  trailing: route.id == _selectedRouteId
                      ? const Icon(
                          Icons.check_circle,
                          color: Color(0xFF0F6A5F),
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(route.id),
                ),
                const Divider(),
              ],
            ],
          ),
        );
      },
    );

    if (!mounted || selectedRouteId == null) {
      return;
    }
    _selectPassengerRoute(selectedRouteId);
  }

  void _selectPassengerRoute(String routeId) {
    final nextRoute = _routeById(routeId);
    final previousRouteId = _selectedRouteId;
    final routeChanged = _selectedRouteId != routeId;

    setState(() {
      if (routeChanged) {
        _clearPassengerEtaSelection();
      }
      _selectedRouteId = routeId;
      _selectedTripId = _preferredTripIdForRoute(
        _trips,
        routeId,
        anchor: _draftPickupPoint,
      );
      _draftPickupPoint = null;
      _draftUnloadPoint = null;
      _draftPickupLabel = null;
      _draftUnloadLabel = null;
      _mapSelectionMode = _PassengerMapSelectionMode.pickup;
      _statusMessage = nextRoute == null
          ? _statusMessage
          : 'Map updated for ${nextRoute.label}. Pin your pickup point first.';
    });

    _syncRealtimeRouteSubscription(
      previousRouteId: previousRouteId,
      nextRouteId: routeId,
    );

    final onboardTrip = _onboardedTripForCamera();
    final onboardTripPoint =
        onboardTrip == null ? null : _tripVehiclePoint(onboardTrip);
    final center = onboardTripPoint ?? _routeCenter(nextRoute);
    if (center != null) {
      _syncPassengerMapCamera(
        center,
        preferredZoom: onboardTripPoint == null ? 14 : 15,
        force: true,
      );
    }
    _showMapPromptNotification(route: nextRoute, force: true);
    _expandPassengerSheet();
  }

  void _handlePassengerMapReady() {
    _passengerMapReady = true;
    final target = _lastPassengerMapCenter;
    if (target == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_passengerMapReady) {
        return;
      }
      final zoom = _resolvedPassengerMapZoom();
      _passengerMapController.move(target, zoom);
    });
  }

  void _handlePassengerMapPositionChanged(MapCamera camera, bool hasGesture) {
    _lastPassengerMapCenter = camera.center;
    _lastPassengerMapZoom =
        camera.zoom == 0 ? _lastPassengerMapZoom : camera.zoom;
    if (!hasGesture) {
      return;
    }
    _passengerMapFollowPausedUntil =
        DateTime.now().add(_passengerMapFollowPause);
  }

  void _syncPassengerMapCamera(
    LatLng target, {
    double? preferredZoom,
    bool force = false,
  }) {
    final now = DateTime.now();
    final pausedUntil = _passengerMapFollowPausedUntil;
    if (!force && pausedUntil != null && now.isBefore(pausedUntil)) {
      return;
    }

    if (!_passengerMapReady) {
      _lastPassengerMapCenter = target;
      _lastPassengerMapZoom = preferredZoom ?? _lastPassengerMapZoom;
      return;
    }

    final currentZoom = _passengerMapController.camera.zoom;
    final previous = _lastPassengerMapCenter ??
        (currentZoom == 0 ? target : _passengerMapController.camera.center);
    final distanceMeters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      target.latitude,
      target.longitude,
    );
    if (!force && distanceMeters < _passengerMapFollowJitterMeters) {
      return;
    }
    if (!force &&
        distanceMeters < _passengerMapFollowSnapMeters &&
        _lastPassengerMapFollowAt != null &&
        now.difference(_lastPassengerMapFollowAt!) <
            _passengerMapFollowThrottle) {
      return;
    }

    final nextCenter = force || distanceMeters >= _passengerMapFollowSnapMeters
        ? target
        : _lerpLatLng(previous, target, _passengerMapFollowLerpFactor);
    _lastPassengerMapCenter = nextCenter;
    _lastPassengerMapFollowAt = now;
    if (preferredZoom != null) {
      _lastPassengerMapZoom = preferredZoom;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_passengerMapReady) {
        return;
      }
      _passengerMapController.move(
        nextCenter,
        preferredZoom ?? _resolvedPassengerMapZoom(),
      );
    });
  }

  double _resolvedPassengerMapZoom() {
    final currentZoom = _passengerMapController.camera.zoom;
    if (currentZoom != 0) {
      return currentZoom;
    }
    return _lastPassengerMapZoom ??
        (_currentPassengerLocation == null ? 14 : 16);
  }

  void _syncPassengerSelectedTripCamera({
    String? tripId,
    LatLng? target,
    bool force = false,
  }) {
    final onboardTrip = _onboardedTripForCamera();
    if (onboardTrip == null) {
      return;
    }
    if (tripId != null && onboardTrip.id != tripId) {
      return;
    }
    final followTarget = target ?? _tripVehiclePoint(onboardTrip);
    if (followTarget == null) {
      return;
    }
    _syncPassengerMapCamera(followTarget, force: force);
  }

  TripSession? _onboardedTripForCamera() {
    final activeRide = _activeRide;
    if (activeRide == null || activeRide.status != 'onboard') {
      return null;
    }
    return _tripById(activeRide.tripSessionId);
  }

  String _mapPromptMessage(RouteSummaryModel? selectedRoute) {
    if (selectedRoute == null) {
      return 'Choose a route first so the live map can guide your pickup.';
    }
    if (_mapSelectionMode == _PassengerMapSelectionMode.pickup) {
      return 'Place your pickup pin within 50m of your location.';
    }
    return 'Place your unload pin ahead on the route before you ride.';
  }

  void _dismissMapPromptNotification() {
    _mapPromptOverlayTimer?.cancel();
    _mapPromptOverlayTimer = null;
    _mapPromptOverlayEntry?.remove();
    _mapPromptOverlayEntry = null;
  }

  void _showMapPromptNotification({
    RouteSummaryModel? route,
    bool force = false,
  }) {
    if (!mounted) {
      return;
    }

    final message = _mapPromptMessage(route);
    if (!force && _lastMapPromptMessage == message) {
      return;
    }
    _lastMapPromptMessage = message;

    final overlay = Overlay.of(context, rootOverlay: true);
    _dismissMapPromptNotification();

    _mapPromptOverlayEntry = OverlayEntry(
      builder: (context) {
        final topInset = MediaQuery.of(context).padding.top + 88;
        return Positioned(
          top: topInset,
          left: 16,
          right: 16,
          child: IgnorePointer(
            ignoring: false,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: _dismissMapPromptNotification,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEAF5F2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _mapSelectionMode ==
                                        _PassengerMapSelectionMode.pickup
                                    ? Icons.info_outline_rounded
                                    : Icons.flag_circle_outlined,
                                color: const Color(0xFF0F6A5F),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                message,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1F2B2A),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_mapPromptOverlayEntry!);
    _mapPromptOverlayTimer = Timer(
      const Duration(seconds: 3),
      _dismissMapPromptNotification,
    );
  }

  String _compactDistanceLabel(
    double? meters, {
    String fallback = 'Distance pending',
  }) {
    if (meters == null || meters.isNaN || !meters.isFinite) {
      return fallback;
    }
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km';
    }
    return '${meters.round()} m';
  }

  String _compactDurationLabel(
    double? seconds, {
    String fallback = 'ETA pending',
  }) {
    if (seconds == null || seconds.isNaN || !seconds.isFinite) {
      return fallback;
    }
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours hr'
        : '$hours hr $remainingMinutes min';
  }

  double? _distanceFromPassengerToTrip(TripSession? trip) {
    if (trip == null) {
      return null;
    }
    final anchor = _draftPickupPoint ??
        _currentPassengerLocation ??
        _routeCenter(_selectedRoute);
    if (anchor == null) {
      return null;
    }
    return _tripDistanceMeters(trip, anchor);
  }

  int? _availableSeats(TripSession? trip) {
    final capacity = trip?.jeepneyCapacity;
    final occupancy = trip?.occupancyCount;
    if (capacity == null) {
      return null;
    }
    return math.max(capacity - (occupancy ?? 0), 0);
  }

  String _availableSeatsLabel(TripSession? trip) {
    final seats = _availableSeats(trip);
    if (seats == null) {
      return 'Capacity sync pending';
    }
    return '$seats seat${seats == 1 ? '' : 's'} available';
  }

  String _passengerCountLabel(TripSession? trip) {
    final passengerCount = trip?.occupancyCount;
    if (passengerCount == null) {
      return 'Passenger count syncing';
    }
    return '$passengerCount passenger${passengerCount == 1 ? '' : 's'} onboard';
  }

  double? _distanceFromJeepneyToBooking(
    TripSession? trip,
    PickupRequestModel? booking,
  ) {
    final jeepneyPoint = trip == null ? null : _tripVehiclePoint(trip);
    if (jeepneyPoint == null ||
        booking?.pickupLatitude == null ||
        booking?.pickupLongitude == null) {
      return null;
    }
    return _distance.as(
      LengthUnit.Meter,
      jeepneyPoint,
      LatLng(booking!.pickupLatitude!, booking.pickupLongitude!),
    );
  }

  double? _distanceFromJeepneyToRideDestination(
    TripSession? trip,
    RideSessionModel? ride,
  ) {
    final jeepneyPoint = trip == null ? null : _tripVehiclePoint(trip);
    if (jeepneyPoint == null ||
        ride?.destinationLatitude == null ||
        ride?.destinationLongitude == null) {
      return null;
    }
    return _distance.as(
      LengthUnit.Meter,
      jeepneyPoint,
      LatLng(ride!.destinationLatitude!, ride.destinationLongitude!),
    );
  }

  double? _distanceFromPassengerToDestination(RideSessionModel? ride) {
    if (_currentPassengerLocation == null ||
        ride?.destinationLatitude == null ||
        ride?.destinationLongitude == null) {
      return null;
    }
    return _distance.as(
      LengthUnit.Meter,
      _currentPassengerLocation!,
      LatLng(ride!.destinationLatitude!, ride.destinationLongitude!),
    );
  }

  double? _tripProgressFraction(
    TripSession? trip,
    RouteSummaryModel? route,
  ) {
    final jeepneyPoint = trip == null ? null : _tripVehiclePoint(trip);
    if (jeepneyPoint == null || route == null) {
      return null;
    }
    final orderedPoints = _orderedRoutePoints(route);
    if (orderedPoints.length < 2) {
      return null;
    }
    final projection = _nearestRouteProjection(
      route,
      jeepneyPoint,
    );
    if (projection == null) {
      return null;
    }
    final segmentCount = math.max(orderedPoints.length - 1, 1);
    return (projection.progress / segmentCount).clamp(0.0, 1.0);
  }

  String _syncStatusLabel() {
    if (_showingCachedPassengerSnapshot) {
      return 'Cached snapshot in use';
    }
    if (_lastPassengerSyncAt == null) {
      return 'Sync pending';
    }
    return 'Last synced ${ParagoFormat.relative(_lastPassengerSyncAt!.toIso8601String())}';
  }

  Widget _buildSideDrawer({required SessionController session}) {
    return Drawer(
      backgroundColor: const Color(0xFFFFFEFB),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    const Color(0xFF2157A5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Icon(
                      Icons.person,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    session.user?.fullName ?? 'Passenger',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.user?.email ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF0F6A5F),
                      ),
                    ),
                    title: const Text(
                      'History',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_requests.length} booking${_requests.length == 1 ? '' : 's'}, ${_rides.length} ride${_rides.length == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showHistoryBottomSheet();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1D6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bookmark_rounded,
                        color: Color(0xFFE29B2D),
                      ),
                    ),
                    title: const Text(
                      'Saved Places',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Manage favorite locations'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showSavedPlacesBottomSheet();
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Color(0xFF2157A5),
                      ),
                    ),
                    title: const Text(
                      'Support',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Chat with the admin team'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_openSupportCenter());
                    },
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'ACCOUNT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF8A928F),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const LegalLinks(),
                  // Passenger account-menu items temporarily disabled:
                  // ListTile(
                  //   leading: const Icon(Icons.settings_outlined),
                  //   title: const Text('Profile & Settings'),
                  //   onTap: () {
                  //     Navigator.of(context).pop();
                  //     unawaited(_openProfileSettings(session));
                  //   },
                  // ),
                  // ListTile(
                  //   leading: const Icon(Icons.refresh_outlined),
                  //   title: const Text('Refresh Data'),
                  //   onTap: () {
                  //     Navigator.of(context).pop();
                  //     unawaited(_refreshPassengerData());
                  //   },
                  // ),
                  ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: const Text('Log Out'),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_confirmPassengerLogout(session));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHistoryBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ride History',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your recent bookings and completed rides',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF67726E),
                          ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          if (_requests.isEmpty && _rides.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.history_rounded,
                                      size: 64,
                                      color: const Color(0xFFD9DDD7),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No history yet',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Your bookings and rides will appear here',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF67726E),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_requests.isNotEmpty || _rides.isNotEmpty) ...[
                            Text(
                              'BOOKINGS',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF8A928F),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            for (final request in _requests) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8F5),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            request.stopRef ??
                                                'Booking request',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        StatusBadge(status: request.status),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _bookingStateText(request),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      ParagoFormat.relative(request.createdAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF67726E),
                                          ),
                                    ),
                                    if (_canCancelRequest(request)) ...[
                                      const SizedBox(height: 12),
                                      TextButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          unawaited(_cancelRequest(request.id));
                                        },
                                        icon: const Icon(Icons.close),
                                        label: const Text('Cancel booking'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Text(
                              'RIDES',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF8A928F),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            for (final ride in _rides) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8F5),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            ride.destinationStopRef ??
                                                'Ride session',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        StatusBadge(status: ride.status),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _rideStatusMessage(ride),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Boarded ${ParagoFormat.relative(ride.boardedAt)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF67726E),
                                          ),
                                    ),
                                    if (ride.estimatedFare != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Fare: ${_formatFareAmount(ride.estimatedFare)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showSavedPlacesBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved Places',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quick access to your favorite locations',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF67726E),
                      ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.bookmark_border_rounded,
                        size: 64,
                        color: const Color(0xFFD9DDD7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No saved places yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Save your home, work, and frequently visited locations for faster booking',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF67726E),
                            ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Saved places feature coming soon'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add a place'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSupportBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Get help with your ParaGO experience',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF67726E),
                      ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(_openSupportCenter());
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Open support chat'),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5F2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F6A5F),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.support_agent_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Need assistance?',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'We\'re here to help',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF4E5A56),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SupportTile(
                        icon: Icons.email_outlined,
                        title: 'Email Support',
                        subtitle: 'support@parago.com',
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _SupportTile(
                        icon: Icons.phone_outlined,
                        title: 'Hotline',
                        subtitle: '+63 XXX XXX XXXX',
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _SupportTile(
                        icon: Icons.help_outline_rounded,
                        title: 'FAQs',
                        subtitle: 'Common questions answered',
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _SupportTile(
                        icon: Icons.info_outline_rounded,
                        title: 'About ParaGO',
                        subtitle: 'Version 1.0.0 (Thesis)',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF7E8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFFE1A6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFE29B2D),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This is a thesis project for transportation support system research.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSupportCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PassengerSupportScreen(
          routeId: _selectedRoute?.id ?? _selectedRouteId,
          tripSessionId: _selectedTrip?.id,
          pickupRequestId: _selectedTripBooking?.id,
          rideSessionId: _displayRide?.id ?? _activeRide?.id,
          realtimeSocketService: _realtimeSocketService,
        ),
      ),
    );
  }

  String _routeQuickMeta(RouteSummaryModel route) {
    final liveCount = _routeTrips(route.id).length;
    final eta = _compactDurationLabel(
      route.durationSeconds,
      fallback: '${route.stopsCount} stops',
    );
    return '$eta · $liveCount live jeep${liveCount == 1 ? '' : 's'}';
  }

  Widget _buildRouteSearchBar({
    required RouteSummaryModel? selectedRoute,
    required int liveTripCount,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: () {
          unawaited(_openRoutePicker());
        },
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: Color(0xFF0F6A5F),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedRoute?.label ?? 'Where are you going?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selectedRoute == null
                                ? const Color(0xFF7D8784)
                                : const Color(0xFF1F2B2A),
                          ),
                    ),
                    if (selectedRoute != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$liveTripCount live jeep${liveTripCount == 1 ? '' : 's'} on this route',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF67726E),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF0F6A5F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF5F2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF0F6A5F)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF67726E),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRouteCard({
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required PickupRequestModel? selectedBooking,
    required List<TripSession> routeTrips,
  }) {
    if (selectedRoute == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F5),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Text(
          'Choose a route to unlock the pickup map, quick routes, and ride actions.',
        ),
      );
    }

    final nearestDistance = _distanceFromPassengerToTrip(selectedTrip);
    final routeMeta = _compactDurationLabel(
      selectedRoute.durationSeconds,
      fallback: _compactDistanceLabel(
        selectedRoute.distanceMeters,
        fallback: 'Route ready',
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.directions_bus_filled_rounded,
                  size: 40,
                  color: Color(0xFF0F6A5F),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedRoute.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: routeTrips.isEmpty
                                ? const Color(0xFFF0F2ED)
                                : const Color(0xFFFFE083),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            routeTrips.isEmpty ? 'WAITING' : 'FASTEST',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5A4A14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${selectedRoute.code} · ${selectedRoute.direction}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF0F6A5F),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedTrip == null
                          ? 'No live jeepney is broadcasting on this route yet.'
                          : '${_compactDistanceLabel(nearestDistance)} away · ${selectedTrip.jeepneyLabel}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4E5A56),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedTrip?.driverName?.isNotEmpty == true
                          ? 'Driver ${selectedTrip!.driverName}'
                          : routeMeta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF67726E),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route est.',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF8A928F),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        routeMeta,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7F2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seats available',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF8A928F),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _availableSeatsLabel(selectedTrip),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _passengerCountLabel(selectedTrip),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF67726E),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (selectedBooking != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF7E8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFE1A6)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    color: Color(0xFFE29B2D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${selectedBooking.stopRef ?? 'Pickup saved'} to ${selectedBooking.destinationStopRef ?? 'Unload saved'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  StatusBadge(status: selectedBooking.status),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveTrackingCard({
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required RideSessionModel? activeRide,
    required PickupRequestModel? selectedBooking,
  }) {
    if (selectedTrip == null || selectedRoute == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8E9E3)),
        ),
        child: const Text(
          'Live tracking becomes active when a jeepney on your selected route is broadcasting location updates.',
        ),
      );
    }

    final progress = _tripProgressFraction(selectedTrip, selectedRoute);
    final passengerToJeepneyMeters = _distanceFromPassengerToTrip(selectedTrip);
    final jeepneyToPickupMeters =
        _distanceFromJeepneyToBooking(selectedTrip, selectedBooking);
    final jeepneyToDestinationMeters =
        _distanceFromJeepneyToRideDestination(selectedTrip, activeRide);
    final passengerToDestinationMeters =
        _distanceFromPassengerToDestination(activeRide);
    final trackingEta = _passengerEtaTripId == selectedTrip.id
        ? _freshPassengerEta?.durationSeconds
        : null;
    final approachingDestination =
        jeepneyToDestinationMeters != null && jeepneyToDestinationMeters <= 180;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E9E3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF0F6A5F),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live tracking',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeRide?.status == 'onboard'
                          ? 'Tracking your onboard trip toward ${activeRide?.destinationStopRef ?? 'your saved destination'}.'
                          : 'Tracking the nearest live jeepney on ${selectedRoute.code}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF67726E),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: approachingDestination
                      ? const Color(0xFFFFF1D6)
                      : const Color(0xFFEAF5F2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  approachingDestination ? 'Approaching stop' : 'Live',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: approachingDestination
                        ? const Color(0xFF8C5E12)
                        : const Color(0xFF0F6A5F),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: const Color(0xFFE6ECE8),
              color: const Color(0xFF0F6A5F),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress == null
                ? 'Route progress will appear once the route geometry and jeepney position are both available.'
                : '${(progress * 100).round()}% of the visible route has been covered by the tracked jeepney.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF67726E),
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSummaryChip(
                label: activeRide?.status == 'onboard'
                    ? 'ETA to unload'
                    : 'ETA to pickup',
                value: _compactDurationLabel(
                  trackingEta,
                  fallback: activeRide?.status == 'onboard'
                      ? 'ETA pending'
                      : 'ETA unavailable',
                ),
                icon: Icons.schedule_outlined,
              ),
              _buildSummaryChip(
                label: 'Passenger to jeep',
                value: _compactDistanceLabel(
                  passengerToJeepneyMeters,
                  fallback: 'Distance pending',
                ),
                icon: Icons.social_distance_outlined,
              ),
              _buildSummaryChip(
                label: activeRide?.status == 'onboard'
                    ? 'Jeep to destination'
                    : 'Jeep to pickup',
                value: _compactDistanceLabel(
                  activeRide?.status == 'onboard'
                      ? jeepneyToDestinationMeters
                      : jeepneyToPickupMeters,
                  fallback: 'Distance pending',
                ),
                icon: Icons.place_outlined,
              ),
              _buildSummaryChip(
                label: 'Sync status',
                value: _syncStatusLabel(),
                icon: Icons.sync_outlined,
              ),
            ],
          ),
          if (passengerToDestinationMeters != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Passenger to saved destination: ${_compactDistanceLabel(passengerToDestinationMeters)}. Auto para uses your saved stop. Automatic unload requires repeated fresh GPS readings at least 120 meters from the jeepney.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF55615D),
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRideSnapshotCard(RideSessionModel? displayRide) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E9E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PassengerSectionHeading(
            title: 'Ride snapshot',
            actionLabel: displayRide == null ? null : 'DETAILS',
            onActionPressed: _expandPassengerSheet,
          ),
          const SizedBox(height: 10),
          if (displayRide == null)
            const Text(
              'No verified ride session yet. Book a route, board, and your live ride details will appear here.',
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                StatusBadge(status: displayRide.status),
                if (displayRide.canSendStopAlert == true)
                  const StatusBadge(status: 'para enabled'),
              ],
            ),
            const SizedBox(height: 12),
            Text(_rideStatusMessage(displayRide)),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Ride',
              value: ParagoFormat.shortId(displayRide.id),
            ),
            _DetailRow(
              label: 'Boarded',
              value: ParagoFormat.dateTime(displayRide.boardedAt),
            ),
            _DetailRow(
              label: 'Destination',
              value: displayRide.destinationStopRef ?? 'Not saved',
            ),
            if (displayRide.estimatedFare != null)
              _DetailRow(
                label: 'Fare',
                value: _formatFareAmount(displayRide.estimatedFare),
              ),
            if (displayRide.fareBoardingStopRef != null &&
                displayRide.fareDestinationStopRef != null)
              _DetailRow(
                label: 'Fare landmarks',
                value:
                    '${displayRide.fareBoardingStopRef} to ${displayRide.fareDestinationStopRef}',
              ),
            if (displayRide.endedAt != null)
              _DetailRow(
                label: 'Dropped off',
                value: ParagoFormat.dateTime(displayRide.endedAt),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPassengerBottomSheet({
    required List<RouteSummaryModel> quickRoutes,
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required RideSessionModel? activeRide,
    required RideSessionModel? displayRide,
    required PickupRequestModel? selectedBooking,
    required List<TripSession> routeTrips,
    required List<PickupRequestModel> recentRequests,
    required int pendingCount,
    required int onboardCount,
    required int unreadCount,
  }) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final shouldCollapse =
            notification.extent <= (_sheetCollapsedSize + 0.01);
        if (shouldCollapse != _passengerSheetCollapsed && mounted) {
          setState(() => _passengerSheetCollapsed = shouldCollapse);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize:
            _passengerSheetCollapsed ? _sheetCollapsedSize : _sheetPeekSize,
        minChildSize: _sheetCollapsedSize,
        maxChildSize: _sheetExpandedSize,
        snap: true,
        snapSizes: const [_sheetCollapsedSize, _sheetPeekSize],
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFFEFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            child: RefreshIndicator(
              onRefresh: _refreshPassengerData,
              child: CustomScrollView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        12,
                        18,
                        24 + MediaQuery.of(context).padding.bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  child: Container(
                                    width: 58,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD9DDD7),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: _togglePassengerSheet,
                                icon: Icon(
                                  _passengerSheetCollapsed
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFF0F6A5F),
                                ),
                                tooltip: _passengerSheetCollapsed
                                    ? 'Show panel'
                                    : 'Hide panel',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_passengerSheetCollapsed) ...[
                            Center(
                              child: Text(
                                'Swipe up or tap the arrow to show the panel',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF67726E),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            const SizedBox(height: 8),
                            if (_announcements.isNotEmpty) ...[
                              AnnouncementCard(
                                announcement: _announcements.first,
                                compact: true,
                                onDismiss: () => _dismissAnnouncement(
                                  _announcements.first,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_statusMessage != null) ...[
                              _InfoBanner(
                                message: _statusMessage!,
                                onClose: () {
                                  setState(() => _statusMessage = null);
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            PassengerPrimaryButton(
                              label: 'Request pickup',
                              icon: Icons.near_me_rounded,
                              onPressed: _loading || _terminalBookingFull
                                  ? null
                                  : _sendPickup,
                            ),
                            const SizedBox(height: 12),
                            PassengerSecondaryActionCard(
                              icon: Icons.fact_check_outlined,
                              title: 'I boarded',
                              subtitle:
                                  'Validate boarding using your current booking.',
                              color: const Color(0xFF2157A5),
                              enabled: !_loading,
                              onTap: _loading ? null : _board,
                            ),
                            const SizedBox(height: 12),
                            PassengerSecondaryActionCard(
                              icon: Icons.notifications_active_outlined,
                              title: 'Send para alert',
                              subtitle:
                                  'Available only for verified onboard passengers.',
                              color: const Color(0xFFE29B2D),
                              enabled:
                                  !_loading && activeRide?.status == 'onboard',
                              onTap: _loading || activeRide?.status != 'onboard'
                                  ? null
                                  : _sendPara,
                            ),
                            const SizedBox(height: 12),
                            PassengerSecondaryActionCard(
                              icon: Icons.exit_to_app_outlined,
                              title: 'I unloaded',
                              subtitle:
                                  'Close your ride manually when you get off.',
                              color: const Color(0xFF0F6A5F),
                              enabled:
                                  !_loading && activeRide?.status == 'onboard',
                              onTap: _loading || activeRide?.status != 'onboard'
                                  ? null
                                  : _markUnloaded,
                            ),
                            if (_loading) ...[
                              const SizedBox(height: 14),
                              const LinearProgressIndicator(),
                            ],
                            if (displayRide != null) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8F5),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Current Ride',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        StatusBadge(status: displayRide.status),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      displayRide.destinationStopRef ??
                                          'Ride in progress',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _rideStatusMessage(displayRide),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final unreadCount =
        _notifications.where((notification) => !notification.isRead).length;
    final pendingCount = _requests
        .where((request) =>
            request.status == 'pending' || request.status == 'acknowledged')
        .length;
    final onboardCount =
        _rides.where((ride) => ride.status == 'onboard').length;
    final availableRoutes = _routes
        .where((route) => route.status == 'active')
        .toList(growable: false);
    final selectedRoute = _selectedRoute;
    final selectedTrip = _selectedTrip;
    final activeRide = _activeRide;
    final displayRide = _displayRide;
    final selectedBooking = _selectedTripBooking;
    final routeTrips = selectedRoute == null
        ? const <TripSession>[]
        : _selectedRouteDisplayTrips(selectedRoute.id);
    final quickRoutes = (availableRoutes.isEmpty ? _routes : availableRoutes)
        .take(4)
        .toList(growable: false);
    final recentRequests = List<PickupRequestModel>.from(_requests)
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final showDashboardRedesign = DateTime.now().year >= 2024;

    if (showDashboardRedesign) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFEAF1ED),
        drawer: _buildSideDrawer(session: session),
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildPassengerMapSurface(
                selectedRoute: selectedRoute,
                selectedTrip: selectedTrip,
                routeTrips: routeTrips,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.transparent,
                        const Color(0xFF17312C).withValues(alpha: 0.28),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PassengerDashboardTopBar(
                      unreadCount: unreadCount,
                      onMenuPressed: _openSideDrawer,
                      onNoticesPressed: () =>
                          unawaited(_showPassengerNoticesSheet()),
                      onRefreshPressed: () {
                        _showMapPromptNotification(route: selectedRoute);
                        unawaited(_refreshPassengerData());
                      },
                      onAccountSelected: (action) {
                        unawaited(_handleDashboardAction(session, action));
                      },
                    ),
                    if (_terminalBookingFull)
                      const Material(
                          child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                  'No terminal seats available. Wait for the loading jeep to depart.'))),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Terminal hours: 4:30 AM–7:30 PM (Philippine time). '
                          'Actual first/final departures depend on available jeeps. Roadside service may continue.'),
                    ),
                    if (_transferOffers.isNotEmpty)
                      FilledButton.icon(
                          onPressed: _loading ? null : _showTransferOffers,
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(
                              'Review terminal transfers (${_transferOffers.length})')),
                    if (selectedTrip?.operatingMode == 'terminal_queue')
                      TerminalLoadingClock(summary: selectedTrip?.terminalSummary),
                    if (selectedTrip?.operatingMode == 'terminal_queue')
                      Material(
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                  'Terminal jeep: ${selectedTrip!.terminalQueueStatus}. ${selectedTrip.terminalSummary?["availableSeats"] ?? 0} unreserved seats. ${selectedTrip.terminalSummary?["availableSeats"] == 0 ? "Wait for departure before booking." : ""}'))),
                    const SizedBox(height: 14),
                    _buildRouteSearchBar(
                      selectedRoute: selectedRoute,
                      liveTripCount: routeTrips.length,
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          PassengerMapControlChip(
                            label: 'Pickup',
                            icon: Icons.person_pin_circle_outlined,
                            selected: _mapSelectionMode ==
                                _PassengerMapSelectionMode.pickup,
                            onTap: () {
                              setState(() {
                                _mapSelectionMode =
                                    _PassengerMapSelectionMode.pickup;
                              });
                              _showMapPromptNotification(
                                route: selectedRoute,
                                force: true,
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          PassengerMapControlChip(
                            label: 'Unload',
                            icon: Icons.flag_circle_outlined,
                            selected: _mapSelectionMode ==
                                _PassengerMapSelectionMode.unload,
                            onTap: _draftPickupPoint == null
                                ? null
                                : () {
                                    setState(() {
                                      _mapSelectionMode =
                                          _PassengerMapSelectionMode.unload;
                                    });
                                    _showMapPromptNotification(
                                      route: selectedRoute,
                                      force: true,
                                    );
                                  },
                          ),
                          const SizedBox(width: 10),
                          PassengerMapControlChip(
                            label: _locatingPassenger
                                ? 'Locating'
                                : 'Refresh location',
                            icon: Icons.my_location_rounded,
                            selected: false,
                            onTap: _locatingPassenger
                                ? null
                                : () => _ensureCurrentPassengerLocation(
                                      forceRefresh: true,
                                      recenterMap: true,
                                    ),
                          ),
                          const SizedBox(width: 10),
                          PassengerMapControlChip(
                            label: 'Clear pins',
                            icon: Icons.layers_clear_outlined,
                            selected: false,
                            onTap: _draftPickupPoint == null &&
                                    _draftUnloadPoint == null
                                ? null
                                : () {
                                    setState(() {
                                      _draftPickupPoint = null;
                                      _draftUnloadPoint = null;
                                      _draftPickupLabel = null;
                                      _draftUnloadLabel = null;
                                      _mapSelectionMode =
                                          _PassengerMapSelectionMode.pickup;
                                    });
                                    _refreshPassengerEtaForTargetChange();
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildPassengerBottomSheet(
              quickRoutes: quickRoutes,
              selectedRoute: selectedRoute,
              selectedTrip: selectedTrip,
              activeRide: activeRide,
              displayRide: displayRide,
              selectedBooking: selectedBooking,
              routeTrips: routeTrips,
              recentRequests: recentRequests,
              pendingCount: pendingCount,
              onboardCount: onboardCount,
              unreadCount: unreadCount,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passenger Console'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) {
              unawaited(_handleDashboardAction(session, action));
            },
            itemBuilder: (context) => const [
              // Passenger user-menu items temporarily disabled:
              // PopupMenuItem<String>(
              //   value: 'profile',
              //   child: Text('Profile & settings'),
              // ),
              // PopupMenuItem<String>(
              //   value: 'refresh',
              //   child: Text('Refresh data'),
              // ),
              PopupMenuItem<String>(
                value: 'mark_all_read',
                child: Text('Mark alerts read'),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text('Log out'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPassengerData,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _RoleHero(
              title: 'Book your next jeepney ride',
              subtitle:
                  'Select a route, pin your pickup and unload points on the map, and let the nearest eligible jeep on that route receive your booking request.',
              accent: Theme.of(context).colorScheme.secondary,
              badge: session.user?.fullName ?? 'Passenger',
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Terminal service hours: 4:30 AM–7:30 PM (Philippine time). '
                    'First loading begins at 4:30 AM; final terminal loading is around 7:30 PM. '
                    'Actual departures depend on available jeeps. Jeeps already on the road may continue serving passengers.'),
              )),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              _InfoBanner(
                message: _statusMessage!,
                onClose: () {
                  setState(() => _statusMessage = null);
                },
              ),
            ],
            if (_syncMessage != null && _syncMessage != _statusMessage) ...[
              const SizedBox(height: 16),
              _InfoBanner(
                message: _syncMessage!,
                onClose: () {
                  setState(() => _syncMessage = null);
                },
              ),
            ],
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: compact ? 1 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: compact ? 1.7 : 1.05,
                  children: [
                    MetricCard(
                      label: 'Live jeeps',
                      value: _trips.length.toString(),
                      icon: Icons.directions_bus_filled_outlined,
                      accent: const Color(0xFF0F6A5F),
                      caption:
                          'Jeepneys currently broadcasting on active trips',
                    ),
                    MetricCard(
                      label: 'Active bookings',
                      value: pendingCount.toString(),
                      icon: Icons.event_seat_outlined,
                      accent: const Color(0xFFE29B2D),
                      caption:
                          'Bookings waiting for acknowledgement or boarding',
                    ),
                    MetricCard(
                      label: 'Onboard rides',
                      value: onboardCount.toString(),
                      icon: Icons.directions_bus_filled_outlined,
                      accent: const Color(0xFF2157A5),
                      caption:
                          'Verified ride sessions with para support enabled',
                    ),
                    MetricCard(
                      label: 'Unread notices',
                      value: unreadCount.toString(),
                      icon: Icons.notifications_active_outlined,
                      accent: const Color(0xFF7B4F9D),
                      caption:
                          'Pickup, boarding, and trip updates from the backend',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _buildPassengerMapCard(
              selectedRoute: selectedRoute,
              selectedTrip: selectedTrip,
              routeTrips: routeTrips,
            ),
            const SizedBox(height: 18),
            _buildLiveTrackingCard(
              selectedRoute: selectedRoute,
              selectedTrip: selectedTrip,
              activeRide: activeRide,
              selectedBooking: selectedBooking,
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Booking panel',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose your route, pin where you will board and unload on the map, then send one booking request to the nearest jeep with available capacity.',
                    ),
                    const SizedBox(height: 16),
                    if (availableRoutes.isEmpty)
                      const Text(
                        'No active routes are available right now.',
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedRoute?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Route to ride',
                        ),
                        items: availableRoutes
                            .map(
                              (route) => DropdownMenuItem<String>(
                                value: route.id,
                                child: Text(route.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          _selectPassengerRoute(value);
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (selectedRoute != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                StatusBadge(status: selectedRoute.status),
                                StatusBadge(
                                  status: routeTrips.isEmpty
                                      ? 'no live jeep'
                                      : '${routeTrips.length} live jeep${routeTrips.length == 1 ? '' : 's'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _DetailRow(
                              label: 'Route',
                              value: selectedRoute.label,
                            ),
                            _DetailRow(
                              label: 'Stops',
                              value: selectedRoute.stopsCount.toString(),
                            ),
                            _DetailRow(
                              label: 'Nearest jeep',
                              value: selectedTrip == null
                                  ? 'Waiting for an active jeep on this route'
                                  : selectedTrip.jeepneyLabel,
                            ),
                            _DetailRow(
                              label: 'Driver',
                              value:
                                  selectedTrip?.driverName?.isNotEmpty == true
                                      ? selectedTrip!.driverName!
                                      : 'Not available',
                            ),
                            if (selectedTrip?.startedAt != null)
                              _DetailRow(
                                label: 'Started',
                                value: ParagoFormat.dateTime(
                                    selectedTrip!.startedAt),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (selectedBooking != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFE29B2D).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                const Color(0xFFE29B2D).withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current booking',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              selectedBooking.stopRef ?? 'Booking request',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(_bookingStateText(selectedBooking)),
                            const SizedBox(height: 8),
                            _DetailRow(
                              label: 'Unload destination',
                              value: selectedBooking.destinationStopRef ??
                                  'Not saved',
                            ),
                            if (selectedBooking.estimatedFare != null)
                              _DetailRow(
                                label: 'Estimated fare',
                                value: _formatFareAmount(
                                    selectedBooking.estimatedFare),
                              ),
                            if (selectedBooking.fareBoardingStopRef != null &&
                                selectedBooking.fareDestinationStopRef != null)
                              _DetailRow(
                                label: 'Fare landmarks',
                                value:
                                    '${selectedBooking.fareBoardingStopRef} to ${selectedBooking.fareDestinationStopRef}',
                              ),
                            if (selectedBooking.pickupLatitude != null &&
                                selectedBooking.pickupLongitude != null)
                              _DetailRow(
                                label: 'Pickup pin',
                                value:
                                    '${selectedBooking.pickupLatitude!.toStringAsFixed(5)}, '
                                    '${selectedBooking.pickupLongitude!.toStringAsFixed(5)}',
                              ),
                            if (selectedBooking.destinationLatitude != null &&
                                selectedBooking.destinationLongitude != null)
                              _DetailRow(
                                label: 'Unload pin',
                                value:
                                    '${selectedBooking.destinationLatitude!.toStringAsFixed(5)}, '
                                    '${selectedBooking.destinationLongitude!.toStringAsFixed(5)}',
                              ),
                            if ((selectedBooking.sourceNote ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(selectedBooking.sourceNote!),
                            ],
                            if (_canCancelRequest(selectedBooking)) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () =>
                                          _cancelRequest(selectedBooking.id),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Cancel booking'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _PassengerActionButton(
                      icon: Icons.event_seat_outlined,
                      title: 'Book this route',
                      subtitle:
                          'Send your pinned pickup and unload points to the nearest eligible jeep',
                      onPressed:
                          _loading || _terminalBookingFull ? null : _sendPickup,
                    ),
                    const SizedBox(height: 12),
                    _PassengerActionButton(
                      icon: Icons.fact_check_outlined,
                      title: 'I boarded',
                      subtitle:
                          'Validate boarding using the unload point already saved in your booking',
                      onPressed: _loading ? null : _board,
                    ),
                    const SizedBox(height: 12),
                    _PassengerActionButton(
                      icon: Icons.notifications_active_outlined,
                      title: 'Send digital para alert',
                      subtitle:
                          'Available only for verified onboard passengers',
                      onPressed: _loading || activeRide?.status != 'onboard'
                          ? null
                          : _sendPara,
                      highlight: const Color(0xFFE29B2D),
                    ),
                    const SizedBox(height: 12),
                    _PassengerActionButton(
                      icon: Icons.exit_to_app_outlined,
                      title: 'I unloaded',
                      subtitle:
                          'Manually close your ride after you get off the jeepney',
                      onPressed: _loading || activeRide?.status != 'onboard'
                          ? null
                          : _markUnloaded,
                      highlight: const Color(0xFF0F6A5F),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
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
                    Text('Ride session',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (displayRide == null)
                      const Text(
                        'No verified ride session yet. Pin your pickup and unload points, send a route booking, then confirm boarding after entering the jeepney.',
                      )
                    else ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          StatusBadge(status: displayRide.status),
                          if (displayRide.canSendStopAlert == true)
                            const StatusBadge(status: 'para enabled'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(_rideStatusMessage(displayRide)),
                      const SizedBox(height: 14),
                      _DetailRow(
                        label: 'Ride session',
                        value: ParagoFormat.shortId(displayRide.id),
                      ),
                      _DetailRow(
                        label: 'Boarded',
                        value: ParagoFormat.dateTime(displayRide.boardedAt),
                      ),
                      _DetailRow(
                        label: 'Pickup request',
                        value:
                            ParagoFormat.shortId(displayRide.pickupRequestId),
                      ),
                      _DetailRow(
                        label: 'Unload destination',
                        value: displayRide.destinationStopRef ?? 'Not saved',
                      ),
                      if (displayRide.destinationLatitude != null &&
                          displayRide.destinationLongitude != null)
                        _DetailRow(
                          label: 'Destination pin',
                          value:
                              '${displayRide.destinationLatitude!.toStringAsFixed(5)}, '
                              '${displayRide.destinationLongitude!.toStringAsFixed(5)}',
                        ),
                      if (displayRide.endedAt != null)
                        _DetailRow(
                          label: 'Dropped off',
                          value: ParagoFormat.dateTime(displayRide.endedAt),
                        ),
                    ],
                  ],
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_requests.length} total',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF67726E),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_requests.isEmpty)
                      const Text('No bookings yet for this account.')
                    else
                      for (final request in _requests.take(6)) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              request.stopRef ?? 'Unspecified booking stop'),
                          subtitle: Text(
                            '${_bookingStateText(request)} · ${ParagoFormat.relative(request.createdAt)}',
                          ),
                          trailing: _canCancelRequest(request)
                              ? TextButton(
                                  onPressed: () => _cancelRequest(request.id),
                                  child: const Text('Cancel'),
                                )
                              : StatusBadge(status: request.status),
                        ),
                        const Divider(),
                      ],
                  ],
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: unreadCount == 0 ? null : _markAllRead,
                        child: const Text('Mark all read'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_announcements.isEmpty && _notifications.isEmpty)
                      const Text('No notifications yet.')
                    else
                      for (final announcement in _announcements) ...[
                        AnnouncementCard(
                          announcement: announcement,
                          onDismiss: () => _dismissAnnouncement(announcement),
                        ),
                        const SizedBox(height: 12),
                      ],
                    for (final notification in _notifications.take(5)) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          notification.isRead
                              ? Icons.mark_email_read_outlined
                              : Icons.notifications_active,
                          color: notification.isRead
                              ? Theme.of(context).colorScheme.outline
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(notification.title),
                        subtitle: Text(
                          '${notification.body}\n${ParagoFormat.relative(notification.createdAt)}',
                        ),
                        isThreeLine: true,
                      ),
                      const Divider(),
                    ],
                  ],
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
                    Text('Available routes',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_routes.isEmpty)
                      const Text('Route list unavailable.')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _routes
                            .map(
                              (route) => Chip(
                                label: Text('${route.code} · ${route.name}'),
                                avatar: CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  child: Text('${route.stopsCount}'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
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

class _PassengerProfileSettingsResult {
  const _PassengerProfileSettingsResult({
    required this.selectedRouteId,
  });

  final String? selectedRouteId;
}

class _PassengerProfileSettingsSheet extends StatefulWidget {
  const _PassengerProfileSettingsSheet({
    required this.profile,
    required this.activeRoutes,
    required this.profileService,
  });

  final PassengerProfileModel profile;
  final List<RouteSummaryModel> activeRoutes;
  final PassengerProfileService profileService;

  @override
  State<_PassengerProfileSettingsSheet> createState() =>
      _PassengerProfileSettingsSheetState();
}

class _PassengerProfileSettingsSheetState
    extends State<_PassengerProfileSettingsSheet> {
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _photoUrlCtrl;
  late final TextEditingController _emergencyNameCtrl;
  late final TextEditingController _emergencyPhoneCtrl;
  late String? _selectedRouteId;
  bool _saving = false;

  String? get _normalizedSelectedRouteId {
    final value = _selectedRouteId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _fullNameCtrl = TextEditingController(text: profile.fullName);
    _emailCtrl = TextEditingController(text: profile.email);
    _phoneCtrl = TextEditingController(text: profile.phone ?? '');
    _photoUrlCtrl = TextEditingController(text: profile.photoUrl ?? '');
    _emergencyNameCtrl = TextEditingController(
      text: profile.emergencyContactName ?? '',
    );
    _emergencyPhoneCtrl = TextEditingController(
      text: profile.emergencyContactPhone ?? '',
    );
    _selectedRouteId = _normalizedRouteId(profile.defaultRouteId);
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _photoUrlCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await ActionFeedback.run<_PassengerProfileSettingsResult>(
        context: context,
        loadingMessage: 'Saving passenger profile...',
        showSuccess: false,
        action: () async {
          final selectedRouteId = _normalizedSelectedRouteId;
          await widget.profileService.updateAccount(
            fullName: _fullNameCtrl.text,
            email: _emailCtrl.text,
          );
          await widget.profileService.updatePassengerProfile(
            phone: _phoneCtrl.text,
            photoUrl: _photoUrlCtrl.text,
            defaultRouteId: selectedRouteId,
            emergencyContactName: _emergencyNameCtrl.text,
            emergencyContactPhone: _emergencyPhoneCtrl.text,
          );
          return _PassengerProfileSettingsResult(
            selectedRouteId: selectedRouteId,
          );
        },
      );
      if (!mounted || result == null) {
        return;
      }

      Navigator.of(context).pop(result);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _normalizedRouteId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final selectedRouteId = _normalizedSelectedRouteId;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile & settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keep your account details, emergency contact, and default route preference up to date.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _fullNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Passenger phone',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _photoUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Photo URL',
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String?>(
                initialValue: widget.activeRoutes.any(
                  (route) => route.id == selectedRouteId,
                )
                    ? selectedRouteId
                    : null,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No default route'),
                  ),
                  for (final route in widget.activeRoutes)
                    DropdownMenuItem<String?>(
                      value: route.id,
                      child: Text(route.label),
                    ),
                ],
                onChanged: (value) {
                  setState(
                    () => _selectedRouteId = _normalizedRouteId(value),
                  );
                },
                decoration: const InputDecoration(
                  labelText: 'Default route',
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Emergency contact',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emergencyNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emergencyPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact phone',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'Saving...' : 'Save profile',
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

class _TripMarkerAnimation {
  const _TripMarkerAnimation({
    required this.from,
    required this.to,
    this.fromHeading,
    this.toHeading,
    required this.startedAt,
    required this.duration,
    this.isProjection = false,
  });

  final LatLng from;
  final LatLng to;
  final double? fromHeading;
  final double? toHeading;
  final DateTime startedAt;
  final Duration duration;
  final bool isProjection;
}

class _TripVehicleMotionState {
  const _TripVehicleMotionState({
    required this.renderedPosition,
    required this.targetPosition,
    this.renderedHeading,
    this.targetHeading,
    this.lastRealtimeUpdateAt,
    this.previousAuthoritativeSampleAt,
    this.lastAuthoritativeSampleAt,
    this.expectedSampleGap = const Duration(milliseconds: 900),
    this.lastReliableSpeedMetersPerSecond,
    this.lastReliableBearingDegrees,
    this.isProjected = false,
    this.projectionHandoffStarted = false,
  });

  final LatLng renderedPosition;
  final LatLng targetPosition;
  final double? renderedHeading;
  final double? targetHeading;
  final DateTime? lastRealtimeUpdateAt;
  final DateTime? previousAuthoritativeSampleAt;
  final DateTime? lastAuthoritativeSampleAt;
  final Duration expectedSampleGap;
  final double? lastReliableSpeedMetersPerSecond;
  final double? lastReliableBearingDegrees;
  final bool isProjected;
  final bool projectionHandoffStarted;

  _TripVehicleMotionState copyWith({
    LatLng? renderedPosition,
    LatLng? targetPosition,
    double? renderedHeading,
    double? targetHeading,
    DateTime? lastRealtimeUpdateAt,
    DateTime? previousAuthoritativeSampleAt,
    DateTime? lastAuthoritativeSampleAt,
    Duration? expectedSampleGap,
    double? lastReliableSpeedMetersPerSecond,
    double? lastReliableBearingDegrees,
    bool? isProjected,
    bool? projectionHandoffStarted,
    bool keepLastRealtimeUpdateAt = true,
  }) {
    return _TripVehicleMotionState(
      renderedPosition: renderedPosition ?? this.renderedPosition,
      targetPosition: targetPosition ?? this.targetPosition,
      renderedHeading: renderedHeading ?? this.renderedHeading,
      targetHeading: targetHeading ?? this.targetHeading,
      lastRealtimeUpdateAt: keepLastRealtimeUpdateAt
          ? (lastRealtimeUpdateAt ?? this.lastRealtimeUpdateAt)
          : lastRealtimeUpdateAt,
      previousAuthoritativeSampleAt:
          previousAuthoritativeSampleAt ?? this.previousAuthoritativeSampleAt,
      lastAuthoritativeSampleAt:
          lastAuthoritativeSampleAt ?? this.lastAuthoritativeSampleAt,
      expectedSampleGap: expectedSampleGap ?? this.expectedSampleGap,
      lastReliableSpeedMetersPerSecond: lastReliableSpeedMetersPerSecond ??
          this.lastReliableSpeedMetersPerSecond,
      lastReliableBearingDegrees:
          lastReliableBearingDegrees ?? this.lastReliableBearingDegrees,
      isProjected: isProjected ?? this.isProjected,
      projectionHandoffStarted:
          projectionHandoffStarted ?? this.projectionHandoffStarted,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _TripVehicleMotionState &&
        other.renderedPosition == renderedPosition &&
        other.targetPosition == targetPosition &&
        other.renderedHeading == renderedHeading &&
        other.targetHeading == targetHeading &&
        other.lastRealtimeUpdateAt == lastRealtimeUpdateAt &&
        other.previousAuthoritativeSampleAt == previousAuthoritativeSampleAt &&
        other.lastAuthoritativeSampleAt == lastAuthoritativeSampleAt &&
        other.expectedSampleGap == expectedSampleGap &&
        other.lastReliableSpeedMetersPerSecond ==
            lastReliableSpeedMetersPerSecond &&
        other.lastReliableBearingDegrees == lastReliableBearingDegrees &&
        other.isProjected == isProjected &&
        other.projectionHandoffStarted == projectionHandoffStarted;
  }

  @override
  int get hashCode => Object.hash(
        renderedPosition,
        targetPosition,
        renderedHeading,
        targetHeading,
        lastRealtimeUpdateAt,
        previousAuthoritativeSampleAt,
        lastAuthoritativeSampleAt,
        expectedSampleGap,
        lastReliableSpeedMetersPerSecond,
        lastReliableBearingDegrees,
        isProjected,
        projectionHandoffStarted,
      );
}

class _TripProjectionMotion {
  const _TripProjectionMotion({
    required this.tripId,
    required this.state,
    required this.animation,
  });

  final String tripId;
  final _TripVehicleMotionState state;
  final _TripMarkerAnimation animation;
}

enum _PassengerBookingMode {
  roadside('roadside'),
  terminal('terminal');

  const _PassengerBookingMode(this.apiValue);

  final String apiValue;
}

enum _PassengerMapSelectionMode {
  pickup,
  unload,
}

class _PassengerInput {
  const _PassengerInput({
    required this.stopRef,
    this.note,
  });

  final String stopRef;
  final String? note;
}

class _PassengerBookingDetails {
  const _PassengerBookingDetails({
    required this.bookingMode,
    required this.pickupStopRef,
    required this.destinationStopRef,
    this.note,
  });

  final _PassengerBookingMode bookingMode;
  final String pickupStopRef;
  final String destinationStopRef;
  final String? note;
}

class _PassengerFarePreview {
  const _PassengerFarePreview({
    required this.boardingStopRef,
    required this.destinationStopRef,
    required this.amount,
  });

  final String boardingStopRef;
  final String destinationStopRef;
  final double amount;
}

class _PassengerFareStop {
  const _PassengerFareStop({
    required this.name,
    required this.progress,
    required this.position,
  });

  final String name;
  final double progress;
  final LatLng position;
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

class _PassengerMapPin extends StatelessWidget {
  const _PassengerMapPin({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Icon(icon, color: color, size: 36),
      ],
    );
  }
}

class _PassengerVehicleMarker extends StatelessWidget {
  const _PassengerVehicleMarker({
    required this.color,
    required this.size,
    required this.selected,
    required this.plateNumber,
    required this.etaLabel,
    required this.distanceLabel,
    required this.seatsLabel,
    required this.freshnessLabel,
    required this.onTap,
    this.headingDegrees,
  });

  final Color color;
  final double size;
  final bool selected;
  final String plateNumber;
  final String etaLabel;
  final String distanceLabel;
  final String seatsLabel;
  final String freshnessLabel;
  final VoidCallback onTap;
  final double? headingDegrees;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.directions_bus_filled,
      color: color,
      size: size,
    );

    return Semantics(
      button: true,
      label: selected
          ? '$plateNumber, $etaLabel, $distanceLabel'
          : 'Select jeepney $plateNumber',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: selected
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 214,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF0F6A5F).withValues(alpha: 0.24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plateNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF17312C),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              etaLabel,
                              style: const TextStyle(
                                color: Color(0xFF0F6A5F),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$distanceLabel · $seatsLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF55615D),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          freshnessLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF7A8580),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: ((headingDegrees ?? 0) * math.pi) / 180,
                    child: icon,
                  ),
                ],
              )
            : Center(
                child: Transform.rotate(
                  angle: ((headingDegrees ?? 0) * math.pi) / 180,
                  child: icon,
                ),
              ),
      ),
    );
  }
}

class _PassengerMapLabel extends StatelessWidget {
  const _PassengerMapLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoleHero extends StatelessWidget {
  const _RoleHero({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            accent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, this.onClose});

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              tooltip: 'Dismiss',
            ),
          ],
        ],
      ),
    );
  }
}

class _PassengerActionButton extends StatelessWidget {
  const _PassengerActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.highlight,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
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
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0F6A5F)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF67726E),
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF8A928F),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerBookingSnapshot {
  const _PassengerBookingSnapshot({
    required this.requests,
    required this.rides,
  });

  final List<PickupRequestModel> requests;
  final List<RideSessionModel> rides;
}
