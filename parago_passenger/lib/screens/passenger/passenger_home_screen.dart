import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/operations/notification.dart';
import '../../models/operations/pickup_request.dart';
import '../../models/operations/ride_session.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/trip_session.dart';
import '../../services/notification_service.dart';
import '../../services/passenger_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/passenger_home_dashboard_widgets.dart';
import '../../widgets/status_badge.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  static const LatLng _defaultMapCenter = LatLng(14.6091, 121.0223);
  static const Distance _distance = Distance();
  static const double _pickupPinToleranceMeters = 300;
  static const double _unloadPinToleranceMeters = 5;
  static const double _pickupFromCurrentLocationMeters = 50;
  static const double _autoUnloadDistanceMeters = 120;
  static const int _autoUnloadConsecutiveOutsideChecks = 3;
  static const Duration _autoUnloadSustainedSeparation = Duration(seconds: 60);
  static const Duration _autoUnloadForceAfterPrompt = Duration(minutes: 2);
  static const double _sheetCollapsedSize = 0.09;
  static const double _sheetPeekSize = 0.38;
  static const double _sheetExpandedSize = 0.90;
  static const Duration _autoUnloadRetryCooldown = Duration(seconds: 45);

  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  List<PickupRequestModel> _requests = [];
  List<RideSessionModel> _rides = [];
  List<NotificationModel> _notifications = [];
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
  Timer? _liveRefreshTimer;
  StreamSubscription<Map<String, dynamic>>? _realtimeNotificationSubscription;
  bool _silentRefreshActive = false;
  bool _realtimePrimed = false;
  bool _locatingPassenger = false;
  bool _autoUnloadInFlight = false;
  bool _passengerSheetCollapsed = false;
  int _outsideAutoUnloadWindowCount = 0;
  DateTime? _outsideAutoUnloadSince;
  DateTime? _autoUnloadPromptedAt;
  String? _autoUnloadWindowRideId;
  String? _lastAutoUnloadRideId;
  DateTime? _lastAutoUnloadAt;
  String? _lastMapPromptMessage;
  Set<String> _knownNotificationIds = <String>{};
  final MapController _passengerMapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  OverlayEntry? _mapPromptOverlayEntry;
  Timer? _mapPromptOverlayTimer;

  TripSession? get _selectedTrip {
    final selectedTripId = _selectedTripId;
    if (selectedTripId != null && selectedTripId.isNotEmpty) {
      for (final trip in _trips) {
        if (trip.id == selectedTripId) {
          return trip;
        }
      }
    }
    final selectedRouteId = _selectedRouteId;
    if (selectedRouteId != null && selectedRouteId.isNotEmpty) {
      final candidates = _routeTrips(selectedRouteId);
      if (candidates.isNotEmpty) {
        final anchor = _draftPickupPoint ?? _routeCenter(_selectedRoute);
        if (anchor == null) {
          return candidates.first;
        }
        final sorted = List<TripSession>.from(candidates)
          ..sort((left, right) {
            return _tripDistanceMeters(left, anchor)
                .compareTo(_tripDistanceMeters(right, anchor));
          });
        return sorted.first;
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
        if (ride.tripSessionId == selectedTripId &&
            ride.status == 'onboard' &&
            ride.canSendStopAlert != false) {
          return ride;
        }
      }
      for (final ride in _rides) {
        if (ride.tripSessionId == selectedTripId && ride.status == 'onboard') {
          return ride;
        }
      }
    }
    for (final ride in _rides) {
      if (ride.status == 'onboard' && ride.canSendStopAlert != false) {
        return ride;
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
    final selectedRouteId = _selectedRouteId;
    if (selectedRouteId != null && selectedRouteId.isNotEmpty) {
      for (final request in _requests) {
        if (request.routeId == selectedRouteId &&
            (request.status == 'pending' ||
                request.status == 'acknowledged' ||
                request.status == 'completed')) {
          return request;
        }
      }
    }

    for (final request in _requests) {
      if (request.status == 'pending' ||
          request.status == 'acknowledged' ||
          request.status == 'completed') {
        return request;
      }
    }
    return null;
  }

  Future<void> _load({bool silent = false}) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    final passengerService = PassengerService(session.apiClient);
    final notificationService = NotificationService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        tripService.getActiveTrips(useCache: false),
        passengerService.getMyPickupRequests(useCache: false),
        passengerService.getMyRides(useCache: false),
        notificationService.getMine(useCache: false),
        routeService.getRoutes(useCache: false),
      ]);

      final trips = results[0] as List<TripSession>;
      final requests = results[1] as List<PickupRequestModel>;
      final rides = results[2] as List<RideSessionModel>;
      final notifications = results[3] as List<NotificationModel>;
      final routes = results[4] as List<RouteSummaryModel>;

      final selectableRoutes = routes
          .where((route) => route.status == 'active')
          .toList(growable: false);
      final nextRouteId = _selectRouteId(
        routes: selectableRoutes.isEmpty ? routes : selectableRoutes,
        trips: trips,
        requests: requests,
        rides: rides,
      );
      String? requestFocusedTripId;
      if (nextRouteId != null) {
        for (final request in requests) {
          if (request.routeId == nextRouteId &&
              (request.status == 'pending' ||
                  request.status == 'acknowledged' ||
                  request.status == 'completed')) {
            requestFocusedTripId = request.tripSessionId;
            break;
          }
        }
      }
      final nextTripId = requestFocusedTripId ??
          _preferredTripIdForRoute(
            trips,
            nextRouteId,
            anchor: _draftPickupPoint,
          );

      if (!mounted) return;
      setState(() {
        _trips = trips;
        _requests = requests;
        _rides = rides;
        _notifications = notifications;
        _routes = routes;
        _selectedTripId = nextTripId;
        _selectedRouteId = nextRouteId;
      });
      _handleRealtimePassengerUpdates(
        notifications: notifications,
        silent: silent,
      );
      unawaited(_maybeAutoUnloadWhenSeparated());
    } catch (error) {
      setState(() => _statusMessage = error.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _startLiveRefreshLoop() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _silentRefreshActive) {
        return;
      }
      _silentRefreshActive = true;
      try {
        await _ensureCurrentPassengerLocation(
          silent: true,
          forceRefresh: true,
        );
        await _load(silent: true);
      } finally {
        _silentRefreshActive = false;
      }
    });
  }

  bool _applyRealtimePassengerNotification(NotificationModel notification) {
    var needsFallback = false;

    setState(() {
      _notifications = _upsertNotificationList(_notifications, notification);

      switch (notification.type) {
        case 'pickup_request_acknowledged':
        case 'pickup_request_completed':
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
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

    if (_draftPickupPoint == null || _draftUnloadPoint == null) {
      setState(() => _statusMessage =
          'Pin both your pickup and unload locations on the map before booking.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Pins required',
        message:
            'Pin both your pickup and unload locations on the map before booking.',
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
      _draftPickupLabel = payload.pickupStopRef;
      _draftUnloadLabel = payload.destinationStopRef;
    });

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Sending pickup request...',
      successMessage:
          'Booking request sent. The nearest eligible jeep on ${selectedRoute.label} has been notified.',
      action: () => passengerService.createPickupRequest(
        routeId: _selectedRouteId!,
        currentLat: currentLocation.latitude,
        currentLng: currentLocation.longitude,
        pickupLat: _draftPickupPoint!.latitude,
        pickupLng: _draftPickupPoint!.longitude,
        destinationStopRef: payload.destinationStopRef,
        destinationLat: _draftUnloadPoint!.latitude,
        destinationLng: _draftUnloadPoint!.longitude,
        stopRef: payload.pickupStopRef,
        sourceNote: payload.note,
      ),
    );
  }

  Future<void> _board() async {
    final pending = _requests
        .where((request) =>
            request.status == 'pending' || request.status == 'acknowledged')
        .toList()
      ..sort((a, b) => (b.expiresAt ?? '').compareTo(a.expiresAt ?? ''));

    if (pending.isEmpty) {
      setState(() => _statusMessage =
          'You need a recent pickup request before boarding confirmation.');
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Pickup needed',
        message:
            'You need a recent pickup request before boarding confirmation.',
      );
      return;
    }

    final request = _selectedTripBooking ?? pending.first;

    final session = context.read<SessionController>();
    final passengerService = PassengerService(session.apiClient);
    await _runPassengerAction(
      loadingMessage: 'Validating boarding...',
      successMessage:
          'Boarding validated. Saved unload point is now active for this ride.',
      action: () => passengerService.validateBoarding(
        tripSessionId: request.tripSessionId,
        pickupRequestId: request.id,
      ),
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
    _outsideAutoUnloadSince = null;
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
    if (trip == null ||
        trip.jeepneyLatitude == null ||
        trip.jeepneyLongitude == null) {
      _resetAutoUnloadWindow(rideId: ride.id);
      return;
    }

    if (_autoUnloadInFlight) {
      return;
    }

    final lastAttemptRideId = _lastAutoUnloadRideId;
    final lastAttemptAt = _lastAutoUnloadAt;
    if (lastAttemptRideId == ride.id &&
        lastAttemptAt != null &&
        DateTime.now().difference(lastAttemptAt) < _autoUnloadRetryCooldown) {
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
      LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!),
    );
    if (distanceMeters < _autoUnloadDistanceMeters) {
      _resetAutoUnloadWindow(rideId: ride.id);
      return;
    }

    final now = DateTime.now();
    _outsideAutoUnloadSince ??= now;
    _outsideAutoUnloadWindowCount += 1;
    final outsideDuration = now.difference(_outsideAutoUnloadSince!);
    final sustainedSeparation =
        _outsideAutoUnloadWindowCount >= _autoUnloadConsecutiveOutsideChecks ||
            outsideDuration >= _autoUnloadSustainedSeparation;
    if (!sustainedSeparation) {
      return;
    }

    var confirmed = false;
    if (_autoUnloadPromptedAt == null) {
      _autoUnloadPromptedAt = now;
      final roundedDistance = distanceMeters.round();
      confirmed = await _showUnloadConfirmationDialog(
        title: 'You seem far from the jeepney',
        message:
            'You are about $roundedDistance meters away from your jeepney. If you already unloaded, confirm now to close this ride session.',
        confirmLabel: 'Yes, close ride',
      );
      if (!mounted) {
        return;
      }
    }

    final promptedAt = _autoUnloadPromptedAt;
    final allowForcedCompletion =
        promptedAt != null &&
        DateTime.now().difference(promptedAt) >= _autoUnloadForceAfterPrompt;
    if (!confirmed && !allowForcedCompletion) {
      return;
    }

    _autoUnloadInFlight = true;
    _lastAutoUnloadRideId = ride.id;
    _lastAutoUnloadAt = DateTime.now();

    try {
      final session = context.read<SessionController>();
      final passengerService = PassengerService(session.apiClient);
      await passengerService.completeRideSession(ride.id);
      if (!mounted) {
        return;
      }
      await _load(silent: true);
      if (!mounted) {
        return;
      }
      final roundedDistance = distanceMeters.round();
      final message = confirmed
          ? 'Ride closed after you confirmed unload at about $roundedDistance meters away from the jeepney.'
          : 'Ride closed automatically after sustained separation of about $roundedDistance meters from the jeepney.';
      setState(() => _statusMessage = message);
      _resetAutoUnloadWindow(rideId: ride.id);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _statusMessage = ActionFeedback.messageOf(error));
    } finally {
      _autoUnloadInFlight = false;
    }
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
    final pickupStopCtrl = TextEditingController(
      text: _draftPickupLabel ?? 'Nearest loading point',
    );
    final unloadStopCtrl = TextEditingController(
      text: _draftUnloadLabel ?? 'Pinned unload point',
    );
    final noteCtrl = TextEditingController();
    final result = await showDialog<_PassengerBookingDetails>(
      context: context,
      builder: (context) {
        void submit() {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).pop(
            _PassengerBookingDetails(
              pickupStopRef: pickupStopCtrl.text.trim().isEmpty
                  ? 'Nearest loading point'
                  : pickupStopCtrl.text.trim(),
              destinationStopRef: unloadStopCtrl.text.trim().isEmpty
                  ? 'Pinned unload point'
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
              TextField(
                controller: pickupStopCtrl,
                textInputAction: TextInputAction.next,
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
              onPressed: submit,
              child: const Text('Book now'),
            ),
          ],
        );
      },
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

  List<TripSession> _routeTrips(String routeId) {
    return _trips
        .where((trip) => trip.routeId == routeId && trip.status == 'active')
        .toList(growable: false);
  }

  String? _selectRouteId({
    required List<RouteSummaryModel> routes,
    required List<TripSession> trips,
    required List<PickupRequestModel> requests,
    required List<RideSessionModel> rides,
  }) {
    final existingRouteId = _selectedRouteId;
    if (existingRouteId != null &&
        routes.any((route) => route.id == existingRouteId)) {
      return existingRouteId;
    }

    for (final ride in rides) {
      for (final request in requests) {
        if (request.id == ride.pickupRequestId) {
          return request.routeId;
        }
      }
    }

    for (final request in requests) {
      if (request.status == 'pending' ||
          request.status == 'acknowledged' ||
          request.status == 'completed') {
        return request.routeId;
      }
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
    final candidates = trips
        .where((trip) => trip.routeId == routeId && trip.status == 'active')
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    final comparisonAnchor = anchor ?? _routeCenter(_routeById(routeId));
    if (comparisonAnchor == null) {
      return candidates.first.id;
    }
    candidates.sort((left, right) {
      return _tripDistanceMeters(left, comparisonAnchor)
          .compareTo(_tripDistanceMeters(right, comparisonAnchor));
    });
    return candidates.first.id;
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
  }) async {
    final existingLocation = _currentPassengerLocation;
    final existingTimestamp = _currentPassengerLocationAt;
    if (!forceRefresh &&
        existingLocation != null &&
        existingTimestamp != null &&
        DateTime.now().difference(existingTimestamp) <
            const Duration(seconds: 20)) {
      return existingLocation;
    }

    if (_locatingPassenger) {
      return existingLocation;
    }

    if (!mounted) {
      return existingLocation;
    }
    setState(() => _locatingPassenger = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent && mounted) {
          setState(() {
            _statusMessage =
                'Turn on device location to place your pickup pin.';
          });
        }
        return existingLocation;
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
        return existingLocation;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      final next = LatLng(position.latitude, position.longitude);
      if (!mounted) {
        return next;
      }
      setState(() {
        _currentPassengerLocation = next;
        _currentPassengerLocationAt = DateTime.now();
      });
      _passengerMapController.move(next, 16);
      if (triggerAutoUnload) {
        unawaited(_maybeAutoUnloadWhenSeparated());
      }
      return next;
    } catch (_) {
      if (!silent && mounted) {
        setState(() {
          _statusMessage =
              'Unable to read your current location right now. Try again in an open area.';
        });
      }
      return existingLocation;
    } finally {
      if (mounted) {
        setState(() => _locatingPassenger = false);
      }
    }
  }

  Future<void> _primeCurrentPassengerLocation() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      return;
    }
    await _ensureCurrentPassengerLocation(
      silent: true,
      forceRefresh: true,
    );
  }

  double _tripDistanceMeters(TripSession trip, LatLng anchor) {
    if (trip.jeepneyLatitude == null || trip.jeepneyLongitude == null) {
      return double.infinity;
    }
    return _distance.as(
      LengthUnit.Meter,
      anchor,
      LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!),
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
          fallback: 'Pinned pickup point',
        );
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
          fallback: 'Pinned unload point',
        );
      }
    });
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

  String _bookingStateText(PickupRequestModel request) {
    switch (request.status) {
      case 'pending':
        return 'Waiting for driver acknowledgement';
      case 'acknowledged':
        return 'Driver acknowledged your booking';
      case 'completed':
        return 'Boarding was validated for this booking';
      case 'cancelled':
        return 'Booking was cancelled';
      default:
        return ParagoFormat.statusLabel(request.status);
    }
  }

  bool _canCancelRequest(PickupRequestModel request) {
    return request.status == 'pending' || request.status == 'acknowledged';
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

  Widget _buildPassengerMapSurface({
    required RouteSummaryModel? selectedRoute,
    required TripSession? selectedTrip,
    required List<TripSession> routeTrips,
  }) {
    final routePath = _routeMapPath(selectedRoute, selectedTrip);
    final tripMarkers = routeTrips
        .where(
          (trip) =>
              trip.jeepneyLatitude != null && trip.jeepneyLongitude != null,
        )
        .map(
          (trip) => Marker(
            point: LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!),
            width: trip.id == selectedTrip?.id ? 52 : 44,
            height: trip.id == selectedTrip?.id ? 52 : 44,
            child: Icon(
              Icons.directions_bus_filled,
              color: trip.id == selectedTrip?.id
                  ? const Color(0xFF0F6A5F)
                  : const Color(0xFF2157A5),
              size: trip.id == selectedTrip?.id ? 36 : 30,
            ),
          ),
        )
        .toList(growable: true);

    if (_currentPassengerLocation != null) {
      tripMarkers.add(
        Marker(
          point: _currentPassengerLocation!,
          width: 180,
          height: 42,
          alignment: Alignment.topCenter,
          child: const _PassengerMapLabel(
            label: 'Your location',
          ),
        ),
      );
    }

    if (_draftPickupPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftPickupPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftPickupLabel ?? 'Pinned pickup point',
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
            label: _draftUnloadLabel ?? 'Pinned unload point',
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
    final tripMarkers = routeTrips
        .where(
          (trip) =>
              trip.jeepneyLatitude != null && trip.jeepneyLongitude != null,
        )
        .map(
          (trip) => Marker(
            point: LatLng(trip.jeepneyLatitude!, trip.jeepneyLongitude!),
            width: trip.id == selectedTrip?.id ? 52 : 44,
            height: trip.id == selectedTrip?.id ? 52 : 44,
            child: Icon(
              Icons.directions_bus_filled,
              color: trip.id == selectedTrip?.id
                  ? const Color(0xFF0F6A5F)
                  : const Color(0xFF2157A5),
              size: trip.id == selectedTrip?.id ? 36 : 30,
            ),
          ),
        )
        .toList(growable: true);

    if (_currentPassengerLocation != null) {
      tripMarkers.add(
        Marker(
          point: _currentPassengerLocation!,
          width: 180,
          height: 42,
          alignment: Alignment.topCenter,
          child: const _PassengerMapLabel(
            label: 'Your current location',
          ),
        ),
      );
    }

    if (_draftPickupPoint != null) {
      tripMarkers.add(
        Marker(
          point: _draftPickupPoint!,
          width: 180,
          height: 78,
          alignment: Alignment.topCenter,
          child: _PassengerMapPin(
            label: _draftPickupLabel ?? 'Pinned pickup point',
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
            label: _draftUnloadLabel ?? 'Pinned unload point',
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
                      : () =>
                          _ensureCurrentPassengerLocation(forceRefresh: true),
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
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _connectRealtimeSocket();
      await _load();
      if (mounted) {
        _showMapPromptNotification(route: _selectedRoute, force: true);
      }
      unawaited(_primeCurrentPassengerLocation());
    });
    _startLiveRefreshLoop();
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    _realtimeNotificationSubscription?.cancel();
    _dismissMapPromptNotification();
    _realtimeSocketService.dispose();
    super.dispose();
  }

  void _connectRealtimeSocket() {
    final session = context.read<SessionController>();
    final token = session.token?.trim() ?? '';
    if (token.isEmpty) {
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
    final applied = _applyRealtimePassengerNotification(notification);
    _knownNotificationIds = {..._knownNotificationIds, notification.id};
    _realtimePrimed = true;

    if (!applied) {
      await _refreshFromSocketEvent();
      return;
    }

    if (!alreadyKnown) {
      _showPassengerRealtimeSnackBar(notification);
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
      case 'logout':
        session.logout();
        return;
      case 'refresh':
        await _load();
        return;
    }
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
    setState(() {
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

    final center = _routeCenter(nextRoute);
    if (center != null) {
      _passengerMapController.move(center, 14);
    }
    _showMapPromptNotification(route: nextRoute, force: true);
    _expandPassengerSheet();
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
    if (overlay == null) {
      return;
    }

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
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: const Color(0xFF8A928F),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        routeMeta,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: const Color(0xFF8A928F),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _availableSeatsLabel(selectedTrip),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
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
        final shouldCollapse = notification.extent <= (_sheetCollapsedSize + 0.01);
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
              onRefresh: _load,
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
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF67726E),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            const SizedBox(height: 8),
                        if (_statusMessage != null) ...[
                          _InfoBanner(message: _statusMessage!),
                          const SizedBox(height: 16),
                        ],
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildSummaryChip(
                              label: 'Live jeeps',
                              value: '${routeTrips.length}',
                              icon: Icons.directions_bus_filled_outlined,
                            ),
                            _buildSummaryChip(
                              label: 'Bookings',
                              value: '$pendingCount',
                              icon: Icons.event_seat_outlined,
                            ),
                            _buildSummaryChip(
                              label: 'Onboard',
                              value: '$onboardCount',
                              icon: Icons.pin_drop_outlined,
                            ),
                            _buildSummaryChip(
                              label: 'Alerts',
                              value: '$unreadCount',
                              icon: Icons.notifications_active_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildSelectedRouteCard(
                          selectedRoute: selectedRoute,
                          selectedTrip: selectedTrip,
                          selectedBooking: selectedBooking,
                          routeTrips: routeTrips,
                        ),
                        const SizedBox(height: 16),
                        PassengerPrimaryButton(
                          label: 'Request pickup',
                          icon: Icons.near_me_rounded,
                          onPressed: _loading ? null : _sendPickup,
                        ),
                        const SizedBox(height: 22),
                        PassengerSectionHeading(
                          title: 'Quick routes',
                          actionLabel: 'SEE ALL',
                          onActionPressed: () {
                            unawaited(_openRoutePicker());
                          },
                        ),
                        const SizedBox(height: 10),
                        if (quickRoutes.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F5),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Text(
                              'Quick routes will appear here once route data is available.',
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: quickRoutes.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.02,
                            ),
                            itemBuilder: (context, index) {
                              final route = quickRoutes[index];
                              final colors = <Color>[
                                const Color(0xFF0F6A5F),
                                const Color(0xFF2157A5),
                                const Color(0xFFE29B2D),
                                const Color(0xFF8C5E12),
                              ];
                              final icons = <IconData>[
                                Icons.home_rounded,
                                Icons.work_rounded,
                                Icons.route_rounded,
                                Icons.place_rounded,
                              ];
                              return PassengerQuickRouteCard(
                                title: route.name,
                                subtitle: route.code,
                                meta: _routeQuickMeta(route),
                                icon: icons[index % icons.length],
                                color: colors[index % colors.length],
                                selected: route.id == selectedRoute?.id,
                                onTap: () => _selectPassengerRoute(route.id),
                              );
                            },
                          ),
                        const SizedBox(height: 22),
                        PassengerSectionHeading(title: 'Ride actions'),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 22),
                        _buildRideSnapshotCard(displayRide),
                        const SizedBox(height: 22),
                        PassengerSectionHeading(title: 'Recent trips'),
                        const SizedBox(height: 10),
                        if (recentRequests.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F5),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Text(
                              'Your recent bookings and ride history will show up here.',
                            ),
                          )
                        else
                          for (final request in recentRequests.take(3)) ...[
                            PassengerActivityTile(
                              icon: Icons.history_rounded,
                              title: request.destinationStopRef ??
                                  request.stopRef ??
                                  'Recent booking',
                              subtitle:
                                  '${_bookingStateText(request)} · ${ParagoFormat.relative(request.createdAt)}',
                              trailing: _canCancelRequest(request)
                                  ? TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () => _cancelRequest(request.id),
                                      child: const Text('Cancel'),
                                    )
                                  : StatusBadge(status: request.status),
                            ),
                            const SizedBox(height: 12),
                          ],
                        if (_notifications.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          PassengerSectionHeading(
                            title: 'Alerts',
                            actionLabel: unreadCount == 0 ? null : 'MARK ALL',
                            onActionPressed: unreadCount == 0
                                ? null
                                : () {
                                    unawaited(_markAllRead());
                                  },
                          ),
                          const SizedBox(height: 10),
                          for (final notification in _notifications.take(2)) ...[
                            PassengerActivityTile(
                              icon: notification.isRead
                                  ? Icons.mark_email_read_outlined
                                  : Icons.notifications_active_outlined,
                              title: notification.title,
                              subtitle:
                                  '${notification.body} · ${ParagoFormat.relative(notification.createdAt)}',
                              trailing: Icon(
                                notification.isRead
                                    ? Icons.done_all_rounded
                                    : Icons.circle,
                                size: notification.isRead ? 20 : 10,
                                color: notification.isRead
                                    ? const Color(0xFF95A09B)
                                    : const Color(0xFF0F6A5F),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
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
        : _routeTrips(selectedRoute.id);
    final quickRoutes = (availableRoutes.isEmpty ? _routes : availableRoutes)
        .take(4)
        .toList(growable: false);
    final recentRequests = List<PickupRequestModel>.from(_requests)
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final showDashboardRedesign = DateTime.now().year >= 2024;

    if (showDashboardRedesign) {
      return Scaffold(
        backgroundColor: const Color(0xFFEAF1ED),
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
                      onMenuPressed: _expandPassengerSheet,
                      onRefreshPressed: () {
                        _showMapPromptNotification(route: selectedRoute);
                        unawaited(_load());
                      },
                      onAccountSelected: (action) {
                        unawaited(_handleDashboardAction(session, action));
                      },
                    ),
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => session.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
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
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              _InfoBanner(message: _statusMessage!),
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
                          setState(() {
                            _selectedRouteId = value;
                            _selectedTripId = _preferredTripIdForRoute(
                              _trips,
                              value,
                              anchor: _draftPickupPoint,
                            );
                            _draftPickupPoint = null;
                            _draftUnloadPoint = null;
                            _draftPickupLabel = null;
                            _draftUnloadLabel = null;
                            _mapSelectionMode =
                                _PassengerMapSelectionMode.pickup;
                          });
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
                      onPressed: _loading ? null : _sendPickup,
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
                    _SectionHeader(
                      title: 'My bookings',
                      trailing: Text('${_requests.length} total'),
                    ),
                    const SizedBox(height: 8),
                    if (_requests.isEmpty)
                      const Text('No bookings yet for this account.')
                    else
                      for (final request in _requests.take(6)) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              request.stopRef ?? 'Unspecified booking stop'),
                          subtitle: Text(
                            '${ParagoFormat.statusLabel(request.status)} · ${ParagoFormat.relative(request.createdAt)}',
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
                    _SectionHeader(
                      title: 'Notifications',
                      trailing: TextButton(
                        onPressed: unreadCount == 0 ? null : _markAllRead,
                        child: const Text('Mark all read'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_notifications.isEmpty)
                      const Text('No notifications yet.')
                    else
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
    required this.pickupStopRef,
    required this.destinationStopRef,
    this.note,
  });

  final String pickupStopRef;
  final String destinationStopRef;
  final String? note;
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
  const _InfoBanner({required this.message});

  final String message;

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
