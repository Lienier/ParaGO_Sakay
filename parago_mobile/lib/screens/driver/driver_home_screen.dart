import '../../widgets/driver_action_toast.dart';
import '../../core/utils/navigation_follow.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../../widgets/terminal_loading_clock.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/operations/notification.dart';
import '../../models/operations/announcement.dart';
import '../../models/operations/pickup_request.dart';
import '../../models/operations/ride_session.dart';
import '../../models/operations/stop_alert.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/trip_session.dart';
import '../../services/driver_service.dart';
import '../../services/location_tracking_service.dart';
import '../../services/notification_service.dart';
import '../../services/para_sound_service.dart';
import '../../services/announcement_service.dart';
import '../../services/ride_session_service.dart';
import '../../services/route_preview_cache.dart';
import '../../services/route_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../services/stop_alert_service.dart';
import '../../services/trip_service.dart';
import '../../services/occupancy_adjustment_queue.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/confirm_unload_dialog.dart';
import '../../widgets/announcement_card.dart';
import '../support/driver_support_screen.dart';
import 'driver_profile_screen.dart';

part 'driver_home_screen_sections.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverTripLaunchChoice {
  const _DriverTripLaunchChoice({
    required this.route,
    required this.operatingMode,
  });

  final RouteSummaryModel route;
  final String operatingMode;
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  static const _pickupStatuses = {'pending', 'acknowledged'};
  static const _activeAlertStatuses = {'sent', 'seen'};
  static const _dismissedNotificationsStoragePrefix =
      'driver.dismissed.notifications.v1';
  static const double _vehicleGpsJitterMeters = 2;
  static const double _maxVehicleGpsAccuracyMeters = 20;
  static const Duration _vehicleMotionDefaultDuration =
      Duration(milliseconds: 900);
  static const Duration _vehicleMotionTick = Duration(milliseconds: 16);
  static const Duration _vehicleMotionMinDuration = Duration(milliseconds: 550);
  static const Duration _vehicleMotionMaxDuration =
      Duration(milliseconds: 1400);
  static const double _vehicleProjectionHandoffThreshold = 0.88;
  static const Duration _vehicleProjectionMaxDuration = Duration(seconds: 1);
  static const double _vehicleProjectionMaxDistanceMeters = 8;
  static const double _vehicleProjectionMinSpeedMetersPerSecond = 0.8;
  static const Duration _driverMapFollowThrottle = Duration(milliseconds: 150);
  static const double _driverMapFollowJitterMeters = 2;
  static const double _vehicleTeleportSnapMeters = 90;

  List<TripSession> _trips = [];
  List<RouteSummaryModel> _routes = [];
  Map<String, List<LatLng>> _cachedRoutePreviewPoints = {};
  List<NotificationModel> _notifications = [];
  List<AnnouncementModel> _announcements = [];
  Map<String, List<PickupRequestModel>> _tripRequests = {};
  Map<String, List<StopAlertModel>> _tripAlerts = {};
  Map<String, List<RideSessionModel>> _tripRides = {};
  bool _driverActionBusy = false;
  final _countQueues = <String, OccupancyAdjustmentQueue>{};
  Map<String, dynamic> _driverProfile = {};
  String? _assignedRouteId;
  String? _focusedTripId;
  int _tabIndex = 0;
  bool _isOnline = false;
  bool _hasInternet = true;
  bool _loading = false;
  String? _statusMessage;
  String _availabilityNote = 'Checking driver availability...';
  LatLng? _vehicleLocation;
  LatLng? _vehicleTargetLocation;
  LatLng? _vehicleMotionFromLocation;
  LatLng? _vehicleLastAuthoritativeLocation;
  double? _vehicleHeadingDegrees;
  double? _vehicleTargetHeadingDegrees;
  double? _vehicleMotionFromHeadingDegrees;
  double? _vehicleLastReliableHeadingDegrees;
  double? _vehicleLastReliableSpeedMetersPerSecond;
  double? _vehicleLastReliableBearingDegrees;
  DateTime? _vehicleMotionStartedAt;
  DateTime? _vehicleLastAuthoritativeSampleAt;
  DateTime? _vehiclePreviousAuthoritativeSampleAt;
  Duration _vehicleMotionDuration = Duration.zero;
  Duration _vehicleExpectedSampleGap = _vehicleMotionDefaultDuration;
  bool _vehicleMotionIsProjected = false;
  bool _vehicleProjectionHandoffStarted = false;
  LocationTrackingService? _locationTrackingService;
  Timer? _liveRefreshTimer;
  Timer? _availabilityTimer;
  Timer? _vehicleMotionTimer;
  StreamSubscription<Map<String, dynamic>>? _realtimeNotificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeOperationsSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimePickupRequestSubscription;
  StreamSubscription<Map<String, dynamic>>? _realtimeAnnouncementSubscription;
  bool _locationTrackingSyncInFlight = false;
  bool _silentRefreshActive = false;
  bool _realtimePrimed = false;
  bool _availabilitySyncInFlight = false;
  bool? _lastPublishedOnline;
  AppLifecycleState? _appLifecycleState;
  int _loadGeneration = 0;
  DateTime? _lastRealtimeOpsRefreshAt;
  DateTime? _lastAnnouncementRefreshAttemptAt;
  Set<String> _knownNotificationIds = <String>{};
  Set<String> _knownActiveStopAlertIds = <String>{};
  Set<String> _subscribedRealtimeTripIds = <String>{};
  Set<String> _dismissedNotificationIds = <String>{};
  Set<String> _dismissedDriveAlertIds = <String>{};
  Set<String> _dismissedInfoMessages = <String>{};
  bool _dismissedNotificationsLoaded = false;
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  AnnouncementFeedController? _announcementFeedController;
  final MapController _driverMapController = MapController();
  bool _driverMapReady = false;
  LatLng? _lastDriverMapCenter;
  DateTime? _lastDriverMapFollowAt;
  final _mapFollow = NavigationFollow();
  LatLng? _lastDriverFollowTarget;
  bool get _driverFollowLocationFresh => NavigationFollow.isFresh(
      _vehicleLastAuthoritativeSampleAt, DateTime.now());
  String get _driverFollowStatus => !_driverFollowLocationFresh
      ? 'Location unavailable or old. View retained.'
      : _mapFollow.following
          ? 'Following'
          : 'Free view';
  void _recenterDriverMap() {
    _mapFollow.recenter();
    final target = _vehicleLocation ?? _vehicleTargetLocation;
    if (target != null) _syncDriverMapCamera(target, force: true);
    if (mounted) setState(() {});
  }

  TripSession? get _focusedTrip {
    for (final trip in _trips) {
      if (trip.id == _focusedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  bool _routeHasTerminalStop(RouteSummaryModel route) {
    return route.stopPoints.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted) {
        final session = context.read<SessionController>();
        unawaited(_paraSound.start(session).then((enabled) {
          if (mounted && !enabled) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Para notification sound is unavailable. Check notification permissions and connection.'),
            ));
          }
        }).catchError((Object _) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Background para notifications could not be enabled. Keep the app open.'),
            ));
          }
        }));
        _syncRealtimeSocket(session, forceReconnect: true);
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

  SessionController? _securitySession;
  final _paraSound = ParaSoundService();
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
    _syncRealtimeSocket(session, forceReconnect: true);
  }

  @override
  void dispose() {
    _paraSound.dispose();
    _securitySession?.removeListener(_handleSecuritySession);
    WidgetsBinding.instance.removeObserver(this);
    _vehicleMotionTimer?.cancel();
    _locationTrackingService?.dispose();
    _liveRefreshTimer?.cancel();
    _availabilityTimer?.cancel();
    _realtimeNotificationSubscription?.cancel();
    _realtimeOperationsSubscription?.cancel();
    _realtimePickupRequestSubscription?.cancel();
    _realtimeAnnouncementSubscription?.cancel();
    _announcementFeedController?.dispose();
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
      return 'Driver stays online in the background and keeps sharing location whenever background tracking is available.';
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
      final availabilityChanged = _lastPublishedOnline != targetOnline;
      await DriverService(session.apiClient).setStatus(active: targetOnline);
      _lastPublishedOnline = targetOnline;
      if (availabilityChanged && targetOnline) {
        unawaited(_locationTrackingService?.sendLatestNow());
      }
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
      await _syncDriverLocationTracking(session);
      return;
    }

    if (!_isAppForeground) {
      _applyAutomaticAvailabilityState(session, hasInternet: _hasInternet);
      _syncRealtimeSocket(session);
      await _syncAutomaticAvailability(session, forcePush: forcePush);
      await _syncDriverLocationTracking(session);
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
    await _syncDriverLocationTracking(session);
    if (!previousHasInternet && _hasInternet) {
      await _locationTrackingService?.sendLatestNow();
    }
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
    await _locationTrackingService?.stopTracking();
    try {
      await DriverService(session.apiClient).setStatus(active: false);
      _lastPublishedOnline = false;
    } catch (_) {
      // Keep logout resilient even when the status endpoint cannot be reached.
    }
    await session.logout();
  }

  Future<void> _confirmLogoutDriver() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of the driver application?',
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
      await _logoutDriver();
    }
  }

  Future<void> _openSupportCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverSupportScreen(
          routeId: _assignedRouteId,
          tripSessionId: _focusedTrip?.id,
          realtimeSocketService: _realtimeSocketService,
        ),
      ),
    );
  }

  Future<void> _openDriverProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DriverProfileScreen()),
    );
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
    if (!forceReconnect && _realtimeSocketService.isConnected) {
      return;
    }

    _realtimeNotificationSubscription?.cancel();
    _realtimeOperationsSubscription?.cancel();
    _realtimePickupRequestSubscription?.cancel();
    _realtimeAnnouncementSubscription?.cancel();
    _realtimeNotificationSubscription =
        _realtimeSocketService.notificationCreatedStream.listen(
      _handleRealtimeSocketNotification,
    );
    _realtimeOperationsSubscription =
        _realtimeSocketService.operationsChangedStream.listen(
      _handleRealtimeOperationsChanged,
    );
    _realtimePickupRequestSubscription =
        _realtimeSocketService.pickupRequestUpdatedStream.listen(
      _handleRealtimePickupRequestUpdate,
    );
    _realtimeAnnouncementSubscription =
        _realtimeSocketService.announcementActivityStream.listen(
      (_) => unawaited(_refreshAnnouncements()),
    );
    _realtimeSocketService.connect(
      apiBaseUrl: session.apiClient.baseUrl,
      token: token,
    );
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
    if (mounted) {
      setState(() => _announcements = items);
    }
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

  Future<void> _handleRealtimeSocketNotification(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }

    final notification = _extractRealtimeNotification(event);
    if (notification == null || notification.id.isEmpty) {
      await _refreshFromSocketEvent();
      return;
    }

    final alreadyKnown = _knownNotificationIds.contains(notification.id) ||
        _notifications.any((item) => item.id == notification.id);
    _loadGeneration++;
    _applyRealtimeDriverNotification(notification);
    _knownNotificationIds = {..._knownNotificationIds, notification.id};
    _realtimePrimed = true;

    if (!alreadyKnown) {
      _showDriverRealtimeSnackBar(notification);
    }

    // Always reconcile from server after socket events so pull-up controls
    // stay current even when payload shape/type changes.
    await _refreshFromSocketEvent();
  }

  Future<void> _handleRealtimeOperationsChanged(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    final last = _lastRealtimeOpsRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastRealtimeOpsRefreshAt = now;
    await _refreshFromSocketEvent();
  }

  Future<void> _handleRealtimePickupRequestUpdate(
    Map<String, dynamic> event,
  ) async {
    if (!mounted) {
      return;
    }

    final request = _readDriverPickupRequest(event);
    if (request == null || request.id.isEmpty) {
      await _refreshFromSocketEvent();
      return;
    }

    setState(() {
      _tripRequests = _upsertTripRequests(_tripRequests, request);
    });
  }

  NotificationModel? _extractRealtimeNotification(
    Map<String, dynamic> event,
  ) {
    final direct = NotificationModel.fromJson(event);
    if (direct.id.isNotEmpty) {
      return direct;
    }

    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map((key, item) => MapEntry(key.toString(), item));
      }
      return null;
    }

    final nestedCandidates = <dynamic>[
      event['notification'],
      event['data'],
      event['payload'],
    ];

    for (final candidate in nestedCandidates) {
      final normalized = asMap(candidate);
      if (normalized == null) {
        continue;
      }
      final nested = NotificationModel.fromJson(normalized);
      if (nested.id.isNotEmpty) {
        return nested;
      }
    }

    return null;
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
    await _ensureDismissedNotificationsLoaded(session);
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
      _refreshAnnouncementsIfDue();
      final initialResults = await Future.wait<dynamic>([
        tripService.getMyTrips(useCache: false),
        notificationService.getMine(useCache: false),
        routeService.getRoutes(useCache: false),
        driverService.getProfile(useCache: false),
      ]);

      final trips = initialResults[0] as List<TripSession>;
      final notifications = initialResults[1] as List<NotificationModel>;
      final routes = initialResults[2] as List<RouteSummaryModel>;
      final driverProfile = initialResults[3] as Map<String, dynamic>;
      final assignedRouteId = _readAssignedRouteId(driverProfile);
      final driverStatus = driverProfile['status']?.toString().toLowerCase();
      final nextFocus = _resolveNextFocusId(trips);
      final previousTrackingContext =
          '${_focusedTripId ?? ''}|${_assignedRouteId ?? ''}|'
          '${_focusedTrip?.status ?? ''}';
      final focusedTrips = nextFocus == null || nextFocus.isEmpty
          ? const <TripSession>[]
          : trips.where((trip) => trip.id == nextFocus).toList(growable: false);
      final focusedTripIds = focusedTrips.map((trip) => trip.id).toSet();
      final nextFocusedTrip = focusedTrips.isEmpty ? null : focusedTrips.first;
      final nextTrackingContext = '${nextFocus ?? ''}|${assignedRouteId ?? ''}|'
          '${nextFocusedTrip?.status ?? ''}';
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
        _trips = trips.map((incoming) {
          final current = _trips.where((t) => t.id == incoming.id).firstOrNull;
          return current != null && current.isNewerThan(incoming)
              ? current
              : incoming;
        }).toList(growable: false);
        _notifications = notifications;
        _routes = routes;
        _cachedRoutePreviewPoints = cachedRoutePreviewPoints;
        _driverProfile = driverProfile;
        _assignedRouteId = assignedRouteId;
        if (driverStatus == 'active' || driverStatus == 'inactive') {
          _isOnline = driverStatus == 'active';
          _lastPublishedOnline = _isOnline;
        }
        _tripRequests = _replaceTripHydration(
          current: _tripRequests,
          hydrated: focusedHydration.requestsByTrip,
          hydratedTripIds: focusedTripIds,
        );
        _tripAlerts = _replaceTripHydration(
          current: _tripAlerts,
          hydrated: focusedHydration.alertsByTrip,
          hydratedTripIds: focusedTripIds,
        );
        _tripRides = _replaceTripHydration(
          current: _tripRides,
          hydrated: focusedHydration.ridesByTrip,
          hydratedTripIds: focusedTripIds,
        );
        _focusedTripId =
            (nextFocus == null || nextFocus.isEmpty) ? null : nextFocus;
      });
      _syncRealtimeTripSubscriptions(trips);
      _syncRealtimeSocket(
        session,
        forceReconnect: !_realtimeSocketService.isConnected,
      );
      if (previousTrackingContext != nextTrackingContext) {
        unawaited(_locationTrackingService?.sendLatestNow());
      }
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

  Map<String, List<T>> _replaceTripHydration<T>({
    required Map<String, List<T>> current,
    required Map<String, List<T>> hydrated,
    required Set<String> hydratedTripIds,
  }) {
    if (hydratedTripIds.isEmpty) {
      return current;
    }

    final next = <String, List<T>>{
      for (final entry in current.entries) entry.key: List<T>.from(entry.value),
    };
    next.removeWhere((tripId, _) => hydratedTripIds.contains(tripId));
    next.addAll(hydrated);
    return next;
  }

  void _syncRealtimeTripSubscriptions(List<TripSession> trips) {
    final nextTripIds = trips.map((trip) => trip.id).toSet();
    final previousTripIds = _subscribedRealtimeTripIds;
    for (final tripId in previousTripIds.difference(nextTripIds)) {
      _realtimeSocketService.unsubscribeFromTrip(tripId);
    }
    for (final tripId in nextTripIds.difference(previousTripIds)) {
      _realtimeSocketService.subscribeToTrip(tripId);
    }
    _subscribedRealtimeTripIds = nextTripIds;
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
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _silentRefreshActive) {
        return;
      }
      final session = context.read<SessionController>();
      if (!_realtimeSocketService.isConnected) {
        _syncRealtimeSocket(session, forceReconnect: true);
      }
      final lastAnnouncementAttemptAt = _lastAnnouncementRefreshAttemptAt;
      if (lastAnnouncementAttemptAt == null ||
          DateTime.now().difference(lastAnnouncementAttemptAt) >=
              const Duration(seconds: 30)) {
        unawaited(_refreshAnnouncements());
      }
      if (_realtimeSocketService.isConnected) {
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
        case 'ride_count_updated':
          final updatedRide = _readDriverRideSession(notification.payload);
          if (updatedRide == null) {
            needsFallback = true;
            return;
          }
          _tripRides = _upsertTripRides(_tripRides, updatedRide);
          break;
        case 'ride_completed':
          final ride = _readDriverRideSession(notification.payload);
          if (ride == null) {
            needsFallback = true;
            return;
          }
          _tripRides = _upsertTripRides(_tripRides, ride);
          _tripAlerts = _dismissTripAlertsForRide(
            _tripAlerts,
            rideSessionId: ride.id,
          );
          _knownActiveStopAlertIds = _tripAlerts.values
              .expand((items) => items)
              .where((alert) => _activeAlertStatuses.contains(alert.status))
              .map((alert) => alert.id)
              .toSet();
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

  Map<String, List<RideSessionModel>> _upsertTripRides(
    Map<String, List<RideSessionModel>> source,
    RideSessionModel ride,
  ) {
    final next = <String, List<RideSessionModel>>{
      for (final entry in source.entries) entry.key: List.of(entry.value),
    };
    final tripRides = List<RideSessionModel>.from(
      next[ride.tripSessionId] ?? const <RideSessionModel>[],
    );
    final existingIndex = tripRides.indexWhere((item) => item.id == ride.id);
    if (existingIndex >= 0) {
      final previous = tripRides[existingIndex];
      if (previous.revision > ride.revision ||
          (previous.status == 'completed' && ride.status != 'completed')) {
        return next;
      }
      tripRides[existingIndex] = ride;
    } else {
      tripRides.insert(0, ride);
    }
    tripRides.sort((a, b) {
      final endedComparison = (b.endedAt ?? '').compareTo(a.endedAt ?? '');
      if (endedComparison != 0) {
        return endedComparison;
      }
      return (b.boardedAt ?? '').compareTo(a.boardedAt ?? '');
    });
    next[ride.tripSessionId] = tripRides;
    return next;
  }

  Map<String, List<StopAlertModel>> _dismissTripAlertsForRide(
    Map<String, List<StopAlertModel>> source, {
    required String rideSessionId,
  }) {
    final next = <String, List<StopAlertModel>>{};
    for (final entry in source.entries) {
      next[entry.key] = entry.value
          .map((alert) => alert.rideSessionId == rideSessionId
              ? StopAlertModel(
                  id: alert.id,
                  passengerId: alert.passengerId,
                  tripSessionId: alert.tripSessionId,
                  routeId: alert.routeId,
                  rideSessionId: alert.rideSessionId,
                  status: 'dismissed',
                  stopRef: alert.stopRef,
                  note: alert.note,
                  latitude: alert.latitude,
                  longitude: alert.longitude,
                  createdAt: alert.createdAt,
                  acknowledgedAt: alert.acknowledgedAt,
                )
              : alert)
          .toList(growable: false);
    }
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

  RideSessionModel? _readDriverRideSession(Map<String, dynamic> payload) {
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
    if (notification.type == 'pickup_request_created') return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (notification.type == 'passenger_near_destination') {
      final stopLabel = _destinationApproachStopLabel(notification.payload);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Passenger nearing destination: $stopLabel'),
        ),
      );
      return;
    }

    if (notification.type == 'stop_alert_created') {
      final alert = _readDriverStopAlert(notification.payload);
      unawaited(ParaSoundService.play(
        alert?.id ?? '',
        context.read<SessionController>().apiClient,
        sentAt: alert?.createdAt,
      ).catchError((Object _) {}));
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

  String _destinationApproachStopLabel(Map<String, dynamic> payload) {
    final value = payload['destinationStopRef']?.toString().trim() ?? '';
    return value.isEmpty ? 'the saved destination' : value;
  }

  Future<void> _runDriverAction({
    required String loadingMessage,
    required String successMessage,
    required Future<dynamic> Function() action,
    bool reloadAfter = true,
  }) async {
    if (_driverActionBusy || !mounted) return;
    _driverActionBusy = true;
    setState(() => _statusMessage = loadingMessage);
    try {
      await action();
      if (mounted && reloadAfter) await _load(silent: true);
      if (!mounted) return;
      setState(() => _statusMessage = successMessage);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      if (reloadAfter) await _load(silent: true);
      if (!mounted) return;
      final message = ActionFeedback.messageOf(error);
      setState(() => _statusMessage = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      _driverActionBusy = false;
    }
  }

  Future<void> _startTrip(TripSession? trip) async {
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);

    if (trip != null) {
      if (!_ensureDriverReady(
        failurePrefix: 'Cannot start the trip yet.',
        trip: trip,
      )) {
        return;
      }
      await _runDriverAction(
        loadingMessage: 'Checking terminal arrival...',
        successMessage:
            'Terminal arrival is being checked automatically from fresh GPS.',
        action: () => tripService.startTrip(trip.id),
      );
      return;
    }

    final jeepneyId = _readProfileEntityId(_driverProfile['assignedJeepneyId']);
    if (jeepneyId == null) {
      await _showDriverRequirementMessage(
        'Cannot start a trip yet. Assign a jeepney first.',
      );
      return;
    }

    if (!_ensureDriverReady(
      failurePrefix: 'Cannot start the trip yet.',
    )) {
      return;
    }

    final activeRoutes = _routes
        .where((route) => route.status.toLowerCase() == 'active')
        .toList(growable: false);
    if (activeRoutes.isEmpty) {
      await _showDriverRequirementMessage(
        'Cannot start a trip yet. No active route is available.',
      );
      return;
    }

    final tripLaunch = await _chooseRouteForNewTrip(activeRoutes);
    if (tripLaunch == null || !mounted) {
      return;
    }

    await _runDriverAction(
      loadingMessage: 'Creating trip...',
      successMessage:
          'Drive to the configured terminal. The first eligible jeep loads automatically after arrival.',
      action: () => tripService.createTrip(
        jeepneyId: jeepneyId,
        routeId: tripLaunch.route.id,
        operatingMode: tripLaunch.operatingMode,
        status: 'active',
      ),
    );
  }

  Future<_DriverTripLaunchChoice?> _chooseRouteForNewTrip(
    List<RouteSummaryModel> routes,
  ) async {
    if (routes.isEmpty) return null;

    final sortedRoutes = List<RouteSummaryModel>.from(routes)
      ..sort((a, b) => _routeChoiceLabel(a).compareTo(_routeChoiceLabel(b)));

    RouteSummaryModel selectedRoute = sortedRoutes.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final terminalAvailable = _routeHasTerminalStop(selectedRoute);
            return AlertDialog(
              title: const Text('Choose route'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width:
                      math.min(MediaQuery.of(context).size.width * 0.85, 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select the route and direction you want to start for this trip.',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRoute.id,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Route'),
                        selectedItemBuilder: (context) => [
                          for (final route in sortedRoutes)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _routeChoiceLabel(route),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        items: [
                          for (final route in sortedRoutes)
                            DropdownMenuItem(
                              value: route.id,
                              child: Text(
                                _routeChoiceLabel(route),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null || value.isEmpty) return;
                          final match = sortedRoutes.firstWhere(
                            (route) => route.id == value,
                            orElse: () => selectedRoute,
                          );
                          setState(() => selectedRoute = match);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Selected: ${_routeChoiceLabel(selectedRoute)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Drive to the configured terminal. Fresh GPS arrival is required before queue loading begins.',
                      ),
                      if (!terminalAvailable) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Terminal queue is unavailable for this route until a terminal stop is configured.',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Begin terminal entry'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return null;
    }
    return _DriverTripLaunchChoice(
      route: selectedRoute,
      operatingMode: 'terminal_queue',
    );
  }

  String _routeChoiceLabel(RouteSummaryModel route) {
    String endpointLabel = '';
    if (route.stopPoints.length >= 2) {
      final first = route.stopPoints.first.name.trim();
      final last = route.stopPoints.last.name.trim();
      if (first.isNotEmpty && last.isNotEmpty) {
        endpointLabel = '$first to $last';
      }
    }

    final direction = route.direction.trim();
    final parts = <String>[route.label];
    if (direction.isNotEmpty) {
      parts.add(direction);
    }
    if (endpointLabel.isNotEmpty) {
      parts.add(endpointLabel);
    }
    return parts.join(' | ');
  }

  Future<void> _endTrip(String tripId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this trip?'),
        content: const Text(
            'This closes all remaining passenger rides, cancels waiting pickups, and dismisses stop alerts. End only when the journey is finished.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep trip active')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End trip')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Ending trip...',
      successMessage: 'Trip ended. Ride sessions and alerts were closed.',
      action: () => tripService.endTrip(tripId),
    );
  }

  Future<void> _toggleAccept(TripSession trip, bool accept) async {
    if (trip.operatingMode == 'terminal_queue') {
      final action = trip.terminalQueueStatus == 'loading'
          ? 'depart'
          : trip.terminalQueueStatus == 'skipped'
              ? 'restore'
              : 'skip';
      if (action == 'depart') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Depart terminal?'),
                    content: Text(
                        '${trip.terminalSummary?["onboardSeats"] ?? trip.occupancyCount ?? 0} onboard passengers stay on this trip. ${trip.terminalSummary?["reservedSeats"] ?? 0} unboarded bookings will receive transfer offers.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Stay')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Depart terminal'))
                    ]));
        if (confirmed != true || !mounted) return;
      }
      final session = context.read<SessionController>();
      await _runDriverAction(
          loadingMessage: 'Updating terminal queue...',
          successMessage: 'Terminal queue updated.',
          action: () =>
              TripService(session.apiClient).terminalAction(trip.id, action));
      return;
    }
    if (accept &&
        !_ensureDriverReady(
          failurePrefix: 'Cannot reopen pickup requests yet.',
          trip: trip,
          requireActiveTrip: true,
        )) {
      return;
    }
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);
    await _runDriverAction(
      loadingMessage: accept
          ? 'Reopening pickup requests...'
          : 'Pausing pickup requests...',
      successMessage:
          accept ? 'Pickup requests reopened.' : 'Pickup requests paused.',
      action: () => tripService.setTripAvailability(trip.id, accept),
    );
  }

  Future<void> _acknowledgeRequest(
    TripSession trip,
    String requestId,
  ) async {
    if (!_ensureDriverReady(
      failurePrefix: 'Cannot acknowledge pickups yet.',
      trip: trip,
      requireActiveTrip: true,
    )) {
      return;
    }
    final session = context.read<SessionController>();
    final driverService = DriverService(session.apiClient);
    await _runDriverAction(
      loadingMessage: 'Acknowledging pickup request...',
      successMessage: 'Pickup request acknowledged.',
      action: () => driverService.acknowledgeRequest(requestId),
    );
  }

  Future<void> _completeUnloadAlert(StopAlertModel alert) async {
    for (final ride
        in _tripRides[alert.tripSessionId] ?? <RideSessionModel>[]) {
      if (ride.id == alert.rideSessionId) {
        await _completeRideDestination(ride);
        return;
      }
    }
    await _load();
  }

  final Set<String> _pendingUnloads = {};

  Future<void> _completeRideDestination(RideSessionModel ride) async {
    if (ride.status != 'onboard' || !_pendingUnloads.add(ride.id)) return;
    try {
      int? count;
      if (ride.isGroup) {
        count = await confirmPassengerCount(context,
            title: 'How many got off?',
            identity:
                '${ride.passengerLabel} | Booking ${ride.bookingLabel}\n${ride.destinationStopRef ?? "Saved destination"}\n${ride.remainingCount} remaining onboard',
            maximum: ride.remainingCount,
            actionLabel: 'Confirm unloaded');
      } else {
        count = await confirmPassengerUnload(context, ride) ? 1 : null;
      }
      if (!mounted) return;
      if (count == null) return;
      final session = context.read<SessionController>();
      final rideService = RideSessionService(session.apiClient);
      await _runDriverAction(
        loadingMessage: 'Closing ride session...',
        successMessage:
            '$count unloaded. ${ride.remainingCount - count} remain in this booking.',
        action: () =>
            rideService.completeRideSession(ride.id, ride: ride, count: count),
      );
    } finally {
      _pendingUnloads.remove(ride.id);
    }
  }

  LocationTrackingService _driverLocationTrackingService(
    SessionController session,
  ) {
    return _locationTrackingService ??= LocationTrackingService(
      DriverService(session.apiClient),
      onPosition: _handleTrackedDriverPosition,
      onError: _handleTrackedDriverPositionError,
    );
  }

  Future<void> _syncDriverLocationTracking(SessionController session) async {
    if (_locationTrackingSyncInFlight) {
      return;
    }

    final shouldTrack = _shouldBeOnline(session);
    final trackingService = _locationTrackingService;
    if (!shouldTrack && trackingService == null) {
      return;
    }

    _locationTrackingSyncInFlight = true;
    try {
      final service = _driverLocationTrackingService(session);
      if (!shouldTrack) {
        await service.stopTracking();
        return;
      }
      if (service.isTracking) {
        return;
      }
      await service.startTracking();
      if (_statusMessage != null &&
          _statusMessage!.toLowerCase().contains('location')) {
        _setStatusMessage(null);
      }
    } on MissingPluginException {
      _setStatusMessage(
        'Location tracking is not available in this build. Rebuild with mobile platform support.',
      );
    } catch (error) {
      _handleTrackedDriverPositionError(error);
    } finally {
      _locationTrackingSyncInFlight = false;
    }
  }

  void _handleTrackedDriverPosition(Position position) {
    if (!mounted) {
      return;
    }

    final receivedAt = DateTime.now();
    final sampleAt = _positionSampleTime(position, receivedAt);
    final next = _smoothedVehicleLocation(position);
    if (next == null) {
      return;
    }
    final currentAnchor = _vehicleLastAuthoritativeLocation ??
        _vehicleTargetLocation ??
        _vehicleLocation;
    final nextHeading = _resolveVehicleHeading(
      position: position,
      previousPoint: currentAnchor,
      nextPoint: next,
    );
    _startVehicleMotion(
      next,
      headingDegrees: nextHeading,
      sampleAt: sampleAt,
      startedAt: receivedAt,
    );

    if (_statusMessage != null &&
        _statusMessage!.toLowerCase().contains('location')) {
      _setStatusMessage(null);
    }
  }

  LatLng? _smoothedVehicleLocation(Position position) {
    final previousLocation = _vehicleTargetLocation ?? _vehicleLocation;
    final rawNext = LatLng(position.latitude, position.longitude);
    final reportedAccuracy = position.accuracy;
    final driftMeters = previousLocation == null
        ? null
        : Geolocator.distanceBetween(
            previousLocation.latitude,
            previousLocation.longitude,
            rawNext.latitude,
            rawNext.longitude,
          );

    if (previousLocation != null &&
        reportedAccuracy.isFinite &&
        reportedAccuracy > _maxVehicleGpsAccuracyMeters &&
        driftMeters != null &&
        driftMeters <= reportedAccuracy * 1.5) {
      debugPrint(
        'Ignoring noisy vehicle GPS fix '
        '(accuracy: ${reportedAccuracy.toStringAsFixed(1)}m, '
        'drift: ${driftMeters.toStringAsFixed(1)}m)',
      );
      return null;
    }

    if (previousLocation != null &&
        driftMeters != null &&
        driftMeters < _vehicleGpsJitterMeters) {
      return previousLocation;
    }

    return rawNext;
  }

  void _handleTrackedDriverPositionError(Object error) {
    if (_looksLikeConnectivityIssue(error)) {
      final session = context.read<SessionController>();
      _applyAutomaticAvailabilityState(session, hasInternet: false);
      return;
    }

    _setStatusMessage(
      'Location tracking needs attention. Check location permission and device location settings.',
    );
    debugPrint('Driver tracking error: $error');
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

  bool get _hasActiveLocalVehicleTracking =>
      _locationTrackingService?.isTracking == true;

  LatLng? _vehicleLocationForTrip(TripSession trip) {
    final storedLocation = _storedVehicleLocation(trip);
    if (_hasActiveLocalVehicleTracking) {
      return _vehicleLocation ?? _vehicleTargetLocation ?? storedLocation;
    }
    return storedLocation ?? _vehicleLocation ?? _vehicleTargetLocation;
  }

  void _syncDriverMapCamera(LatLng target, {bool force = false}) {
    if (!_mapFollow.following || !_driverFollowLocationFresh) return;
    final now = DateTime.now();
    _mapFollow.updateHeading(
        target: _focusedTripId ?? 'driver',
        sample: _vehicleLastAuthoritativeSampleAt,
        now: now,
        bearing: _vehicleLastReliableBearingDegrees,
        speed: _vehicleLastReliableSpeedMetersPerSecond);
    if (!_driverMapReady) {
      _lastDriverMapCenter = target;
      return;
    }
    final previous = _lastDriverFollowTarget;
    final distance = previous == null
        ? double.infinity
        : Geolocator.distanceBetween(previous.latitude, previous.longitude,
            target.latitude, target.longitude);
    if (!force && previous != null && distance < _driverMapFollowJitterMeters) {
      return;
    }
    if (!force &&
        _lastDriverMapFollowAt != null &&
        now.difference(_lastDriverMapFollowAt!) < _driverMapFollowThrottle) {
      return;
    }
    _lastDriverFollowTarget = target;
    _lastDriverMapFollowAt = now;
    final generation = _mapFollow.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_driverMapReady ||
          !_mapFollow.following ||
          generation != _mapFollow.generation ||
          !_driverFollowLocationFresh) {
        return;
      }
      final zoom = math.max(17.5, _driverMapController.camera.zoom);
      _driverMapController.rotate(-_mapFollow.heading);
      _driverMapController.move(target, zoom,
          offset:
              Offset(0, _driverMapController.camera.nonRotatedSize.y * 0.16));
    });
  }

  void _handleDriverMapReady() {
    _driverMapReady = true;
    if (_mapFollow.following) {
      final target = _vehicleLocation ?? _vehicleTargetLocation;
      if (target != null) _syncDriverMapCamera(target, force: true);
    } else if (_lastDriverMapCenter != null) {
      _driverMapController.move(
          _lastDriverMapCenter!, _driverMapController.camera.zoom);
    }
  }

  void _handleDriverMapPositionChanged(MapCamera camera, bool hasGesture) {
    _lastDriverMapCenter = camera.center;
    if (!hasGesture) {
      return;
    }
    _mapFollow.freeView();
  }

  void _startVehicleMotion(
    LatLng target, {
    double? headingDegrees,
    required DateTime sampleAt,
    required DateTime startedAt,
  }) {
    final currentPoint = _vehicleLocation ?? _vehicleTargetLocation ?? target;
    final previousAuthoritativePoint =
        _vehicleLastAuthoritativeLocation ?? currentPoint;
    final currentHeading = _vehicleHeadingDegrees ??
        _vehicleTargetHeadingDegrees ??
        _vehicleLastReliableHeadingDegrees;
    final resolvedHeading = headingDegrees ?? currentHeading;
    final distanceMeters = Geolocator.distanceBetween(
      currentPoint.latitude,
      currentPoint.longitude,
      target.latitude,
      target.longitude,
    );
    final authoritativeDistanceMeters = Geolocator.distanceBetween(
      previousAuthoritativePoint.latitude,
      previousAuthoritativePoint.longitude,
      target.latitude,
      target.longitude,
    );
    final sampleGap = _motionSampleGap(
      sampleAt: sampleAt,
      previousSampleAt: _vehicleLastAuthoritativeSampleAt ??
          _vehiclePreviousAuthoritativeSampleAt,
      defaultDuration: _vehicleMotionDefaultDuration,
      minDuration: _vehicleMotionMinDuration,
      maxDuration: _vehicleMotionMaxDuration,
    );
    final speedMetersPerSecond =
        _metersPerSecond(authoritativeDistanceMeters, sampleGap);
    final headingDelta = (currentHeading == null || resolvedHeading == null)
        ? 0
        : _shortestHeadingDelta(currentHeading, resolvedHeading).abs();

    if (_vehicleLocation == null && _vehicleTargetLocation == null) {
      setState(() {
        _vehicleLocation = target;
        _vehicleTargetLocation = target;
        _vehicleMotionFromLocation = target;
        _vehicleHeadingDegrees = resolvedHeading;
        _vehicleTargetHeadingDegrees = resolvedHeading;
        _vehicleMotionFromHeadingDegrees = resolvedHeading;
        if (resolvedHeading != null) {
          _vehicleLastReliableHeadingDegrees = resolvedHeading;
          _vehicleLastReliableBearingDegrees = resolvedHeading;
        }
        _vehicleLastAuthoritativeLocation = target;
        _vehiclePreviousAuthoritativeSampleAt =
            _vehicleLastAuthoritativeSampleAt;
        _vehicleLastAuthoritativeSampleAt = sampleAt;
        _vehicleExpectedSampleGap = sampleGap;
        _vehicleLastReliableSpeedMetersPerSecond = speedMetersPerSecond;
        _vehicleMotionIsProjected = false;
        _vehicleProjectionHandoffStarted = false;
      });
      _syncDriverMapCamera(target);
      return;
    }

    if (distanceMeters < 0.8 && headingDelta < 2) {
      _vehiclePreviousAuthoritativeSampleAt = _vehicleLastAuthoritativeSampleAt;
      _vehicleLastAuthoritativeSampleAt = sampleAt;
      _vehicleLastAuthoritativeLocation = target;
      _vehicleExpectedSampleGap = sampleGap;
      _vehicleLastReliableSpeedMetersPerSecond = 0;
      if (resolvedHeading != null) {
        _vehicleLastReliableBearingDegrees = resolvedHeading;
      }
      _vehicleMotionIsProjected = false;
      _vehicleProjectionHandoffStarted = false;
      return;
    }

    if (distanceMeters >= _vehicleTeleportSnapMeters) {
      setState(() {
        _vehicleLocation = target;
        _vehicleTargetLocation = target;
        _vehicleMotionFromLocation = target;
        _vehicleHeadingDegrees = resolvedHeading;
        _vehicleTargetHeadingDegrees = resolvedHeading;
        _vehicleMotionFromHeadingDegrees = resolvedHeading;
        if (resolvedHeading != null) {
          _vehicleLastReliableHeadingDegrees = resolvedHeading;
          _vehicleLastReliableBearingDegrees = resolvedHeading;
        }
        _vehicleLastAuthoritativeLocation = target;
        _vehiclePreviousAuthoritativeSampleAt =
            _vehicleLastAuthoritativeSampleAt;
        _vehicleLastAuthoritativeSampleAt = sampleAt;
        _vehicleExpectedSampleGap = sampleGap;
        _vehicleLastReliableSpeedMetersPerSecond = speedMetersPerSecond;
        _vehicleMotionIsProjected = false;
        _vehicleProjectionHandoffStarted = false;
      });
      _vehicleMotionTimer?.cancel();
      _vehicleMotionTimer = null;
      _syncDriverMapCamera(target);
      return;
    }

    setState(() {
      _vehicleMotionFromLocation = currentPoint;
      _vehicleTargetLocation = target;
      _vehicleMotionStartedAt = startedAt;
      _vehicleMotionDuration = _vehicleMotionDurationFor(
        distanceMeters: authoritativeDistanceMeters,
        sampleGap: sampleGap,
      );
      _vehicleMotionFromHeadingDegrees = currentHeading ?? resolvedHeading;
      _vehicleTargetHeadingDegrees = resolvedHeading ?? currentHeading;
      _vehicleLocation = currentPoint;
      _vehicleHeadingDegrees ??= currentHeading ?? resolvedHeading;
      if (resolvedHeading != null) {
        _vehicleLastReliableHeadingDegrees = resolvedHeading;
        _vehicleLastReliableBearingDegrees = resolvedHeading;
      }
      _vehicleLastAuthoritativeLocation = target;
      _vehiclePreviousAuthoritativeSampleAt = _vehicleLastAuthoritativeSampleAt;
      _vehicleLastAuthoritativeSampleAt = sampleAt;
      _vehicleExpectedSampleGap = sampleGap;
      _vehicleLastReliableSpeedMetersPerSecond = speedMetersPerSecond;
      _vehicleMotionIsProjected = false;
      _vehicleProjectionHandoffStarted = false;
    });
    _ensureVehicleMotionLoop();
  }

  void _ensureVehicleMotionLoop() {
    if (_vehicleMotionTimer != null) {
      return;
    }
    _vehicleMotionTimer = Timer.periodic(_vehicleMotionTick, (_) {
      if (!mounted) {
        _vehicleMotionTimer?.cancel();
        _vehicleMotionTimer = null;
        return;
      }
      _advanceVehicleMotion();
    });
  }

  void _advanceVehicleMotion() {
    final from = _vehicleMotionFromLocation;
    final to = _vehicleTargetLocation;
    final startedAt = _vehicleMotionStartedAt;
    if (from == null || to == null || startedAt == null) {
      _stopVehicleMotionLoop();
      return;
    }

    final durationMicros = _vehicleMotionDuration.inMicroseconds;
    final elapsedMicros = DateTime.now().difference(startedAt).inMicroseconds;
    final progress = durationMicros <= 0
        ? 1.0
        : (elapsedMicros / durationMicros).clamp(0.0, 1.0).toDouble();
    final nextPoint = _lerpLatLng(from, to, progress);
    final fromHeading = _vehicleMotionFromHeadingDegrees;
    final toHeading = _vehicleTargetHeadingDegrees;
    final headingProgress = Curves.easeOutCubic.transform(progress);
    final nextHeading = fromHeading == null || toHeading == null
        ? (toHeading ?? fromHeading ?? _vehicleHeadingDegrees)
        : _lerpHeading(fromHeading, toHeading, headingProgress);

    if (!_vehicleMotionIsProjected &&
        !_vehicleProjectionHandoffStarted &&
        progress >= _vehicleProjectionHandoffThreshold) {
      _vehicleProjectionHandoffStarted = true;
      if (_startProjectedVehicleMotion(
        startedAt: DateTime.now(),
        authoritativeTargetPoint: to,
        fromPoint: nextPoint,
        fromHeading: nextHeading,
        remainingAuthoritativeDuration: Duration(
          microseconds: math.max(durationMicros - elapsedMicros, 0),
        ),
      )) {
        return;
      }
    }

    if (_vehicleLocation != nextPoint ||
        _vehicleHeadingDegrees != nextHeading) {
      setState(() {
        _vehicleLocation = nextPoint;
        _vehicleHeadingDegrees = nextHeading;
        if (nextHeading != null) {
          _vehicleLastReliableHeadingDegrees = nextHeading;
        }
      });
    }
    _syncDriverMapCamera(nextPoint);

    if (progress >= 1.0) {
      final finishedHeading = toHeading ?? nextHeading;
      setState(() {
        _vehicleLocation = to;
        _vehicleMotionFromLocation = to;
        _vehicleHeadingDegrees = finishedHeading;
        if (finishedHeading != null) {
          _vehicleLastReliableHeadingDegrees = finishedHeading;
        }
      });
      _stopVehicleMotionLoop();
    }
  }

  void _stopVehicleMotionLoop() {
    _vehicleMotionTimer?.cancel();
    _vehicleMotionTimer = null;
  }

  bool _startProjectedVehicleMotion({
    required DateTime startedAt,
    required LatLng authoritativeTargetPoint,
    required LatLng fromPoint,
    required double? fromHeading,
    required Duration remainingAuthoritativeDuration,
  }) {
    final bearingDegrees = _vehicleLastReliableBearingDegrees ?? fromHeading;
    final speedMetersPerSecond = _vehicleLastReliableSpeedMetersPerSecond;
    if (bearingDegrees == null ||
        speedMetersPerSecond == null ||
        !speedMetersPerSecond.isFinite ||
        speedMetersPerSecond < _vehicleProjectionMinSpeedMetersPerSecond) {
      return false;
    }

    final baseProjectionDuration =
        _vehicleExpectedSampleGap < _vehicleProjectionMaxDuration
            ? _vehicleExpectedSampleGap
            : _vehicleProjectionMaxDuration;
    final projectionDistanceMeters = math.min(
      _vehicleProjectionMaxDistanceMeters,
      speedMetersPerSecond * (baseProjectionDuration.inMilliseconds / 1000),
    );
    if (projectionDistanceMeters < _vehicleGpsJitterMeters) {
      return false;
    }

    final projectedPoint = _offsetLatLng(
      authoritativeTargetPoint,
      bearingDegrees,
      projectionDistanceMeters,
    );
    final projectionDuration =
        remainingAuthoritativeDuration + baseProjectionDuration;
    setState(() {
      _vehicleMotionFromLocation = fromPoint;
      _vehicleTargetLocation = projectedPoint;
      _vehicleMotionStartedAt = startedAt;
      _vehicleMotionDuration = projectionDuration;
      _vehicleMotionFromHeadingDegrees = fromHeading ?? bearingDegrees;
      _vehicleTargetHeadingDegrees = bearingDegrees;
      _vehicleLocation = fromPoint;
      _vehicleMotionIsProjected = true;
      _vehicleProjectionHandoffStarted = true;
    });
    return true;
  }

  double? _resolveVehicleHeading({
    required Position position,
    required LatLng? previousPoint,
    required LatLng nextPoint,
  }) {
    final reportedHeading = position.heading;
    if (reportedHeading.isFinite &&
        position.speed.isFinite &&
        position.speed > 1.5) {
      return _normalizeHeading(reportedHeading);
    }
    if (previousPoint == null) {
      return _vehicleLastReliableHeadingDegrees;
    }
    final distanceMeters = Geolocator.distanceBetween(
      previousPoint.latitude,
      previousPoint.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );
    if (distanceMeters < 1) {
      return _vehicleLastReliableHeadingDegrees;
    }
    return _bearingDegrees(previousPoint, nextPoint);
  }

  Duration _vehicleMotionDurationFor({
    required double distanceMeters,
    required Duration sampleGap,
  }) {
    final cadenceMilliseconds = (sampleGap.inMilliseconds * 0.98).round();
    final distanceMilliseconds = (420 + (distanceMeters * 16)).round();
    final clampedMilliseconds = (cadenceMilliseconds > 0
            ? cadenceMilliseconds
            : math.max(
                distanceMilliseconds,
                _vehicleMotionDefaultDuration.inMilliseconds,
              ))
        .clamp(
      _vehicleMotionMinDuration.inMilliseconds,
      _vehicleMotionMaxDuration.inMilliseconds,
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

  DateTime _positionSampleTime(Position position, DateTime fallback) {
    final timestamp = position.timestamp;
    return timestamp.toLocal();
  }

  double? _metersPerSecond(double distanceMeters, Duration sampleGap) {
    final seconds = sampleGap.inMilliseconds / 1000;
    if (!seconds.isFinite || seconds <= 0) {
      return null;
    }
    final metersPerSecond = distanceMeters / seconds;
    return metersPerSecond.isFinite ? metersPerSecond : null;
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

  String? _readProfileEntityId(dynamic value) {
    if (value is Map<String, dynamic>) {
      final id = value['_id']?.toString().trim();
      return (id == null || id.isEmpty) ? null : id;
    }
    final id = value?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  String? _readAssignedRouteId(Map<String, dynamic> profile) {
    return _readProfileEntityId(profile['assignedRouteId']);
  }

  bool _isDriverOperationallyOnline() {
    final driverStatus = _driverProfile['status']?.toString().toLowerCase();
    if (driverStatus == 'active') {
      return true;
    }
    // Profile status can lag briefly while automatic availability sync runs.
    return _isOnline;
  }

  String _driverAccountStatus() {
    final direct =
        _driverProfile['accountStatus']?.toString().toLowerCase() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final user = _driverProfile['userId'];
    if (user is Map<String, dynamic>) {
      final nested = user['status']?.toString().toLowerCase() ?? '';
      if (nested.isNotEmpty) {
        return nested;
      }
    }
    return 'unknown';
  }

  List<String> _driverOperationalIssues({
    TripSession? trip,
    bool requireActiveTrip = false,
  }) {
    final issues = <String>[];

    if (requireActiveTrip) {
      if (trip == null) {
        issues.add('Select an active trip first.');
      } else if (trip.status != 'active') {
        issues.add('Start the trip before handling pickups.');
      }
    }

    if (_driverProfile.isEmpty) {
      return issues;
    }

    if (!_isDriverOperationallyOnline()) {
      issues.add('Driver must be online.');
    }

    if (_driverAccountStatus() != 'active') {
      issues.add('Driver account must be active.');
    }

    final assignedJeepneyId =
        _readProfileEntityId(_driverProfile['assignedJeepneyId']);
    if (assignedJeepneyId == null) {
      issues.add('Assign a jeepney first.');
    } else if (trip != null &&
        trip.jeepneyId.isNotEmpty &&
        assignedJeepneyId != trip.jeepneyId) {
      issues.add('Focused trip must use the assigned jeepney.');
    }

    return issues;
  }

  String? _driverStartRequirementMessage({TripSession? trip}) {
    final issues = _driverOperationalIssues(trip: trip);
    if (trip?.status == 'scheduled' &&
        trip?.operatingMode == 'terminal_queue' &&
        trip?.terminalQueueStatus == 'off_queue') {
      issues.add(
        'Drive to the configured terminal; fresh GPS arrival will check you in automatically.',
      );
    }
    if (issues.isEmpty) {
      return null;
    }
    return 'Driver requirements incomplete. ${issues.join(' ')}';
  }

  String? _driverPickupRequirementMessage({TripSession? trip}) {
    final issues = _driverOperationalIssues(
      trip: trip,
      requireActiveTrip: true,
    );
    if (issues.isEmpty) {
      return null;
    }
    return 'Pickup is locked. ${issues.join(' ')}';
  }

  String? _driverOperationsBannerMessage(TripSession? trip) {
    if (trip?.operatingMode == 'terminal_queue') {
      final summary = trip!.terminalSummary;
      return 'Terminal: ${trip.terminalQueueStatus} ? Queue ${summary?["queuePosition"] ?? "?"} ? ${summary?["reservedSeats"] ?? 0} reserved ? ${summary?["onboardSeats"] ?? 0} onboard. ${summary?["gpsWarning"] == true ? "GPS unavailable or old; your queue position is retained." : ""}';
    }
    if (trip?.status == 'active' && trip?.inactivityPausedAt != null) {
      return 'No driver location was received for five minutes. Pickups are paused. Reopen pickup requests to resume, or end this trip.';
    }
    if (trip?.status == 'active') {
      return _driverPickupRequirementMessage(trip: trip);
    }
    return _driverStartRequirementMessage(trip: trip);
  }

  bool _ensureDriverReady({
    required String failurePrefix,
    TripSession? trip,
    bool requireActiveTrip = false,
  }) {
    final issues = _driverOperationalIssues(
      trip: trip,
      requireActiveTrip: requireActiveTrip,
    );
    if (issues.isEmpty) {
      return true;
    }

    final message = '$failurePrefix ${issues.join(' ')}';
    if (mounted) {
      setState(() => _statusMessage = message);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }

  Future<void> _showDriverRequirementMessage(String message) async {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isNotificationDismissed(String notificationId) {
    return _dismissedNotificationIds.contains(notificationId);
  }

  String _dismissedNotificationsStorageKey(SessionController session) {
    final userId = session.user?.userId?.trim() ?? '';
    if (userId.isNotEmpty) {
      return '$_dismissedNotificationsStoragePrefix.$userId';
    }
    return _dismissedNotificationsStoragePrefix;
  }

  Future<void> _ensureDismissedNotificationsLoaded(
    SessionController session,
  ) async {
    if (_dismissedNotificationsLoaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedNotificationsStorageKey(session);
    final storedIds = prefs.getStringList(key) ?? const <String>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _dismissedNotificationIds = storedIds.toSet();
      _dismissedNotificationsLoaded = true;
    });
  }

  Future<void> _persistDismissedNotificationIds() async {
    if (!mounted) {
      return;
    }
    final session = context.read<SessionController>();
    final prefs = await SharedPreferences.getInstance();
    final key = _dismissedNotificationsStorageKey(session);
    final values = _dismissedNotificationIds.toList(growable: false)..sort();
    await prefs.setStringList(key, values);
  }

  bool _isDriveAlertDismissed(String alertId) {
    return _dismissedDriveAlertIds.contains(alertId);
  }

  void _dismissNotification(String notificationId) {
    if (!mounted || notificationId.isEmpty) {
      return;
    }
    setState(() {
      _dismissedNotificationIds = {
        ..._dismissedNotificationIds,
        notificationId,
      };
    });
    unawaited(_persistDismissedNotificationIds());
  }

  void _dismissDriveAlert(String alertId) {
    if (!mounted || alertId.isEmpty) {
      return;
    }
    setState(() {
      _dismissedDriveAlertIds = {
        ..._dismissedDriveAlertIds,
        alertId,
      };
    });
  }

  bool _isInfoMessageDismissed(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _dismissedInfoMessages.contains(normalized);
  }

  String? _visibleInfoMessage(String? message) {
    final normalized = message?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (_isInfoMessageDismissed(normalized)) {
      return null;
    }
    return normalized;
  }

  void _dismissInfoMessage(String message) {
    final normalized = message.trim();
    if (!mounted || normalized.isEmpty) {
      return;
    }
    setState(() {
      _dismissedInfoMessages = {
        ..._dismissedInfoMessages,
        normalized,
      };
      if ((_statusMessage ?? '').trim() == normalized) {
        _statusMessage = null;
      }
    });
  }

  void _replaceTripSnapshot(TripSession updatedTrip) {
    _trips = _trips
        .map((trip) =>
            trip.id == updatedTrip.id && !trip.isNewerThan(updatedTrip)
                ? updatedTrip
                : trip)
        .toList(growable: false);
  }

  int _manualOnboardCount(TripSession? trip) {
    final value = _countQueues[trip?.id]?.projectedManualCount ??
        trip?.manualOccupancyCount;
    return value == null || value < 0 ? 0 : value;
  }

  Future<void> _changePassengerCount(String tripId, int delta) async {
    const supportedDeltas = {-5, -3, -2, -1, 1, 2, 3, 5};
    if (!mounted || !supportedDeltas.contains(delta)) return;
    final queue = _countQueues.putIfAbsent(
        tripId,
        () => OccupancyAdjustmentQueue(
            debounce: const Duration(milliseconds: 300)));
    final trip = _trips.where((trip) => trip.id == tripId).firstOrNull;
    if (trip == null || trip.status != 'active') return;
    final manual = _manualOnboardCount(trip);
    final projectedTotal = (trip.occupancyCount ?? 0) -
        (trip.manualOccupancyCount ?? 0) +
        manual +
        delta;
    if (manual + delta < 0 ||
        (trip.jeepneyCapacity != null &&
            projectedTotal > trip.jeepneyCapacity!)) {
      setState(() => _statusMessage = manual + delta < 0
          ? 'Walk-in passenger count is already zero.'
          : 'Jeep capacity reached.');
      return;
    }
    if (queue.pending >= 30) {
      setState(() => _statusMessage = 'Please wait for pending count changes.');
      return;
    }
    final session = context.read<SessionController>();
    final tripService = TripService(session.apiClient);

    setState(() {
      _statusMessage = 'Updating passenger count...';
    });

    try {
      await queue.add((operationId) async {
        if (!mounted) return;
        // Invalidate GETs started before this mutation, including their hydration.
        _loadGeneration++;
        final updatedTrip = await tripService.updateTripManualOccupancy(
          tripId,
          delta,
          operationId,
        );
        if (!mounted) return;
        _loadGeneration++;
        setState(() => _replaceTripSnapshot(updatedTrip));
      }, delta: delta, manualCount: trip.manualOccupancyCount ?? 0);
      final updatedTrip = _trips.firstWhere((trip) => trip.id == tripId);
      if (!mounted) {
        return;
      }
      final updatedCapacity = updatedTrip.jeepneyCapacity;
      final autoPaused = updatedTrip.acceptRequests == false &&
          updatedCapacity != null &&
          updatedCapacity > 0 &&
          updatedTrip.occupancyCount != null &&
          updatedTrip.occupancyCount! >= updatedCapacity;
      final successMessage = autoPaused
          ? 'Jeep is now full. New pickup requests were paused automatically.'
          : 'Walk-in passenger count updated.';
      setState(() {
        _replaceTripSnapshot(updatedTrip);
        _statusMessage = queue.pending > 0
            ? 'Updating passenger count (${queue.pending} pending)...'
            : successMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      unawaited(_load(silent: true));
      final message =
          '${ActionFeedback.messageOf(error)} Check the refreshed count before retrying.';
      setState(() {
        _statusMessage = message;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _routeLabel(TripSession trip) {
    final effectiveRoute = _effectiveRouteSummaryForTrip(trip);
    if (effectiveRoute != null) {
      final baseLabel = effectiveRoute.label;
      final modeLabel = trip.operatingMode == 'terminal_queue'
          ? 'Terminal queue'
          : 'Route mode';
      return '$baseLabel | $modeLabel';
    }
    if (trip.routeName != null && trip.routeName!.isNotEmpty) {
      final modeLabel = trip.operatingMode == 'terminal_queue'
          ? 'Terminal queue'
          : 'Route mode';
      return '${trip.routeLabel} | $modeLabel';
    }
    for (final route in _routes) {
      if (route.id == trip.routeId) return route.label;
    }
    return ParagoFormat.shortId(trip.routeId);
  }

  int _baseOnboardCount(TripSession? trip, List<RideSessionModel> rides) {
    if (trip?.occupancyCount != null) {
      return math.max(
          0,
          trip!.occupancyCount! -
              (trip.manualOccupancyCount ?? 0) +
              _manualOnboardCount(trip));
    }
    return rides.fold<int>(0, (total, ride) => total + ride.onboardCount);
  }

  List<DriverToastAction> _driverToastActions() {
    final actions = <DriverToastAction>[];
    for (final trip in _trips.where((t) => t.status == 'active')) {
      for (final request in _tripRequests[trip.id] ?? <PickupRequestModel>[]) {
        if (request.partySize > 1 &&
            request.status == 'acknowledged' &&
            request.groupReadyAt != null &&
            (DateTime.tryParse(request.expiresAt ?? '')
                    ?.isAfter(DateTime.now()) ??
                false)) {
          actions.add(DriverToastAction(
            id: 'group-board:${request.id}',
            title: 'Group ready to board',
            detail:
                '${request.partySize} reserved | Booking ${ParagoFormat.shortId(request.id)}',
            label: 'Confirm count',
            run: () async {
              final count = await confirmPassengerCount(context,
                  title: 'How many boarded?',
                  identity:
                      'Booking ${ParagoFormat.shortId(request.id)}\n${request.partySize} reserved. Unused seats are released; late companions need a new booking.',
                  maximum: request.partySize,
                  actionLabel: 'Confirm boarding');
              if (count == null || !mounted) return;
              await _runDriverAction(
                  loadingMessage: 'Confirming group...',
                  successMessage: '$count people boarded.',
                  action: () => RideSessionService(
                          context.read<SessionController>().apiClient)
                      .confirmGroupBoarding(request.id, count));
            },
          ));
          continue;
        }
        if (request.status != 'pending' ||
            !(DateTime.tryParse(request.expiresAt ?? '')
                    ?.isAfter(DateTime.now()) ??
                false)) {
          continue;
        }
        actions.add(DriverToastAction(
          id: 'pickup:${request.id}',
          title: 'Passenger pickup request',
          detail:
              '${request.partySize} people | ${request.stopRef ?? "Selected stop"} | Booking ${ParagoFormat.shortId(request.id)}',
          label: 'Acknowledge',
          run: () async {
            _loadGeneration++;
            final updated =
                await DriverService(context.read<SessionController>().apiClient)
                    .acknowledgeRequest(request.id);
            if (!mounted) return;
            _loadGeneration++;
            setState(() {
              _tripRequests = _upsertTripRequests(_tripRequests, updated);
            });
          },
        ));
      }
      for (final ride in _tripRides[trip.id] ?? <RideSessionModel>[]) {
        if (ride.status != 'onboard') continue;
        final hasPara = (_tripAlerts[trip.id] ?? <StopAlertModel>[]).any((a) =>
            a.rideSessionId == ride.id &&
            _activeAlertStatuses.contains(a.status));
        actions.add(DriverToastAction(
          id: '${hasPara ? "para" : "ride"}:${ride.id}',
          title: hasPara ? 'Passenger para alert' : 'Passenger onboard',
          detail:
              '${ride.remainingCount} onboard | ${ride.passengerLabel} | ${ride.bookingLabel} | ${ride.destinationStopRef ?? "Saved destination"}',
          label: 'Mark unloaded',
          run: () => _completeRideDestination(ride),
        ));
      }
      if (trip.operatingMode == 'terminal_queue' &&
          trip.terminalQueueStatus == 'loading') {
        actions.add(DriverToastAction(
            id: 'depart:${trip.id}',
            title: trip.terminalSummary?['departureRequired'] == true
                ? 'Terminal departure required'
                : 'Loading at terminal',
            detail: 'Onboard passengers remain on this trip.',
            label: 'Depart terminal',
            run: () => _toggleAccept(trip, false)));
      }
    }
    return actions;
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
            tooltip: 'Driver profile',
            onPressed: _openDriverProfile,
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: 'Support',
            onPressed: _loading ? null : _openSupportCenter,
            icon: const Icon(Icons.support_agent_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _confirmLogoutDriver,
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
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: SafeArea(
                    bottom: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.55),
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        DriverActionToast(actions: _driverToastActions()),
                        if (_tabIndex == 0 && _announcements.isNotEmpty)
                          AnnouncementCard(
                              announcement: _announcements.first,
                              compact: true,
                              onDismiss: () =>
                                  _dismissAnnouncement(_announcements.first)),
                      ])),
                    )),
              ),
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
            icon: Icon(Icons.notifications_none_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
        ],
      ),
    );
  }
}

class _DriverStatusBanner extends StatelessWidget {
  const _DriverStatusBanner({
    required this.message,
    this.onClose,
  });

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
          ),
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
          IconButton(
            tooltip: 'Close info',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _DrivePanelLiveData {
  const _DrivePanelLiveData({
    required this.trip,
    required this.routeLabel,
    required this.isOnline,
    required this.availabilityNote,
    required this.requirementMessage,
    required this.statusMessage,
    required this.displayedOnboard,
    required this.seatCapacity,
    required this.manualPassengerCount,
    required this.activePickupCount,
    required this.activeDestinationAlerts,
    required this.onAdjustManualCount,
    required this.onStartTrip,
    required this.onEndTrip,
    required this.onTogglePickup,
    required this.onDismissAlert,
    required this.onDismissRequirementMessage,
    required this.onDismissStatusMessage,
  });

  final TripSession? trip;
  final String routeLabel;
  final bool isOnline;
  final String availabilityNote;
  final String? requirementMessage;
  final String? statusMessage;
  final int displayedOnboard;
  final int? seatCapacity;
  final int manualPassengerCount;
  final int activePickupCount;
  final List<StopAlertModel> activeDestinationAlerts;
  final void Function(int delta)? onAdjustManualCount;
  final VoidCallback? onStartTrip;
  final VoidCallback? onEndTrip;
  final VoidCallback? onTogglePickup;
  final VoidCallback? onDismissAlert;
  final VoidCallback? onDismissRequirementMessage;
  final VoidCallback? onDismissStatusMessage;
}

class _DriveMapPanel extends StatefulWidget {
  const _DriveMapPanel({
    required this.mapController,
    required this.trip,
    required this.cameraTarget,
    required this.driverName,
    required this.statusMessage,
    required this.requirementMessage,
    required this.availabilityNote,
    required this.isOnline,
    required this.activePickupCount,
    required this.routeLabel,
    required this.displayedOnboard,
    required this.seatCapacity,
    required this.manualPassengerCount,
    required this.routePath,
    required this.markers,
    required this.activeDestinationAlerts,
    required this.onIncrement,
    required this.onDecrement,
    required this.onStartTrip,
    required this.onEndTrip,
    required this.onTogglePickup,
    required this.onAcknowledgeAlert,
    required this.onDismissAlert,
    required this.onDismissRequirementMessage,
    required this.onDismissStatusMessage,
    required this.onMapReady,
    required this.onPositionChanged,
    required this.onRecenter,
    required this.readFollowStatus,
    required this.readLiveData,
    this.height,
  });

  final MapController mapController;
  final TripSession? trip;
  final LatLng cameraTarget;
  final String driverName;
  final String? statusMessage;
  final String? requirementMessage;
  final String availabilityNote;
  final bool isOnline;
  final int activePickupCount;
  final String routeLabel;
  final int displayedOnboard;
  final int? seatCapacity;
  final int manualPassengerCount;
  final List<LatLng> routePath;
  final List<_DriveMarkerData> markers;
  final List<StopAlertModel> activeDestinationAlerts;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onStartTrip;
  final VoidCallback? onEndTrip;
  final VoidCallback? onTogglePickup;
  final VoidCallback? onAcknowledgeAlert;
  final VoidCallback? onDismissAlert;
  final VoidCallback? onDismissRequirementMessage;
  final VoidCallback? onDismissStatusMessage;
  final VoidCallback onMapReady;
  final PositionCallback onPositionChanged;
  final VoidCallback onRecenter;
  final String Function() readFollowStatus;
  final _DrivePanelLiveData Function() readLiveData;
  final double? height;

  @override
  State<_DriveMapPanel> createState() => _DriveMapPanelState();
}

class _DriveMapPanelState extends State<_DriveMapPanel> {
  static const Duration _idleCollapseDelay = Duration(seconds: 10);

  Timer? _idleCollapseTimer;
  bool _isChromeCollapsed = false;

  MapController get mapController => widget.mapController;
  TripSession? get trip => widget.trip;
  LatLng get cameraTarget => widget.cameraTarget;
  String get driverName => widget.driverName;
  String? get statusMessage => widget.statusMessage;
  String? get requirementMessage => widget.requirementMessage;
  String get availabilityNote => widget.availabilityNote;
  bool get isOnline => widget.isOnline;
  int get activePickupCount => widget.activePickupCount;
  String get routeLabel => widget.routeLabel;
  int get displayedOnboard => widget.displayedOnboard;
  int? get seatCapacity => widget.seatCapacity;
  int get manualPassengerCount => widget.manualPassengerCount;
  List<LatLng> get routePath => widget.routePath;
  List<_DriveMarkerData> get markers => widget.markers;
  List<StopAlertModel> get activeDestinationAlerts =>
      widget.activeDestinationAlerts;
  VoidCallback? get onIncrement => widget.onIncrement;
  VoidCallback? get onDecrement => widget.onDecrement;
  VoidCallback? get onStartTrip => widget.onStartTrip;
  VoidCallback? get onEndTrip => widget.onEndTrip;
  VoidCallback? get onTogglePickup => widget.onTogglePickup;
  VoidCallback? get onAcknowledgeAlert => widget.onAcknowledgeAlert;
  VoidCallback? get onDismissAlert => widget.onDismissAlert;
  VoidCallback? get onDismissRequirementMessage =>
      widget.onDismissRequirementMessage;
  VoidCallback? get onDismissStatusMessage => widget.onDismissStatusMessage;
  VoidCallback get onMapReady => widget.onMapReady;
  PositionCallback get onPositionChanged => widget.onPositionChanged;
  _DrivePanelLiveData Function() get readLiveData => widget.readLiveData;
  double? get height => widget.height;

  @override
  void initState() {
    super.initState();
    _scheduleIdleCollapse();
  }

  @override
  void dispose() {
    _idleCollapseTimer?.cancel();
    super.dispose();
  }

  void _handleUserInteraction({bool expandChrome = true}) {
    if (expandChrome && _isChromeCollapsed && mounted) {
      setState(() {
        _isChromeCollapsed = false;
      });
    }
    _scheduleIdleCollapse();
  }

  void _scheduleIdleCollapse() {
    _idleCollapseTimer?.cancel();
    _idleCollapseTimer = Timer(_idleCollapseDelay, () {
      if (!mounted || _isChromeCollapsed) return;
      setState(() {
        _isChromeCollapsed = true;
      });
    });
  }

  void _handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    onPositionChanged(camera, hasGesture);
    if (hasGesture) {
      _handleUserInteraction();
    }
  }

  void _openControls(BuildContext context) {
    _handleUserInteraction();
    _openControlSheet(context);
  }

  void _openControlSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.35,
        maxChildSize: 0.78,
        builder: (context, scrollController) {
          return StreamBuilder<int>(
            stream: Stream<int>.periodic(
              const Duration(milliseconds: 500),
              (value) => value,
            ),
            builder: (context, _) {
              final live = readLiveData();
              final trip = live.trip;
              final hasTrip = trip != null;
              final isTripActive = trip?.status == 'active';
              final routeLabel = live.routeLabel;
              final isOnline = live.isOnline;
              final availabilityNote = live.availabilityNote;
              final displayedOnboard = live.displayedOnboard;
              final seatCapacity = live.seatCapacity;
              final manualPassengerCount = live.manualPassengerCount;
              final activePickupCount = live.activePickupCount;
              final activeDestinationAlerts = live.activeDestinationAlerts;
              final onAdjustManualCount = live.onAdjustManualCount;
              final onStartTrip = live.onStartTrip;
              final onEndTrip = live.onEndTrip;
              final onTogglePickup = live.onTogglePickup;
              final scheme = Theme.of(context).colorScheme;
              final reduceBlur = MediaQuery.of(context).disableAnimations;
              final blurSigma = reduceBlur ? 0.0 : 16.0;
              final waitingForTerminalArrival = trip?.status == 'scheduled' &&
                  trip?.operatingMode == 'terminal_queue' &&
                  trip?.terminalQueueStatus == 'off_queue';

              return Container(
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 24,
                      offset: Offset(0, -6),
                    ),
                  ],
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: blurSigma,
                      sigmaY: blurSigma,
                    ),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x80132F2E),
                            Color(0x800F6A5F),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Color(0x66FFFFFF),
                            width: 1,
                          ),
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
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                driverName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                availabilityNote,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: Colors.white70,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        StatusBadge(
                                          status: isOnline
                                              ? (trip?.status ?? 'ready')
                                              : 'offline',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.secondary.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            trip?.acceptRequests == false
                                                ? 'Pickup paused'
                                                : 'Pickup active',
                                            style: TextStyle(
                                              color: scheme.onSecondary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Passengers onboard',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
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
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      seatCapacity == null || seatCapacity <= 0
                                          ? 'capacity open'
                                          : '$displayedOnboard / $seatCapacity seats',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Walk-in passengers: $manualPassengerCount',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
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
                              _PassengerAdjustmentControls(
                                enabled: hasTrip && isTripActive,
                                manualCount: manualPassengerCount,
                                displayedOnboard: displayedOnboard,
                                capacity: seatCapacity,
                                onAdjust: onAdjustManualCount,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: waitingForTerminalArrival
                                        ? null
                                        : onStartTrip,
                                    icon: Icon(waitingForTerminalArrival
                                        ? Icons.location_searching
                                        : Icons.play_arrow),
                                    label: Text(waitingForTerminalArrival
                                        ? 'Await terminal arrival'
                                        : 'Start trip'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: onEndTrip,
                                    icon:
                                        const Icon(Icons.stop_circle_outlined),
                                    label: const Text('End trip'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: onTogglePickup,
                                    icon: Icon(
                                      trip?.acceptRequests == false
                                          ? Icons
                                              .playlist_add_check_circle_outlined
                                          : Icons.pause_circle_outline,
                                    ),
                                    label: Text(
                                      trip?.operatingMode == 'terminal_queue'
                                          ? (trip?.terminalQueueStatus ==
                                                  'loading'
                                              ? 'Depart terminal'
                                              : trip?.terminalQueueStatus ==
                                                      'skipped'
                                                  ? 'Rejoin at back'
                                                  : 'Skip my turn')
                                          : trip?.acceptRequests == false
                                              ? 'Resume pickup'
                                              : 'Pause pickup',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Focused trip snapshot',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        trip == null
                                            ? 'This driver screen handles route-based ride alerts, not direct passenger pickups.'
                                            : 'Passengers can alert along the route, and multiple riders can already be onboard.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                      const SizedBox(height: 14),
                                      _SummaryRow(
                                        label: 'Route',
                                        value: trip == null
                                            ? 'No active route'
                                            : routeLabel,
                                      ),
                                      _SummaryRow(
                                        label: 'Trip status',
                                        value: trip == null
                                            ? (isOnline ? 'Ready' : 'Offline')
                                            : trip.operatingMode == 'route' &&
                                                    trip.terminalQueueStatus ==
                                                        'departed'
                                                ? 'Active · Departed terminal'
                                                : ParagoFormat.statusLabel(
                                                    trip.status),
                                      ),
                                      _SummaryRow(
                                        label: 'Route ride alerts',
                                        value: activePickupCount.toString(),
                                      ),
                                      _SummaryRow(
                                        label: 'Unload alerts',
                                        value: activeDestinationAlerts.length
                                            .toString(),
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
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTrip = trip != null;
    final scheme = Theme.of(context).colorScheme;

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
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _handleUserInteraction(),
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
                      onMapReady: onMapReady,
                      onPositionChanged: _handleMapPositionChanged,
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
                                rotate: true,
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
                if (_isChromeCollapsed)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _DriveMapMiniOverlay(
                      status: isOnline
                          ? hasTrip
                              ? trip!.status
                              : 'ready'
                          : 'offline',
                      routeLabel: routeLabel,
                      displayedOnboard: displayedOnboard,
                      activePickupCount: activePickupCount,
                      activeDropOffCount: activeDestinationAlerts.length,
                      dropOffLabel: activeDestinationAlerts.isEmpty
                          ? null
                          : activeDestinationAlerts.first.stopRef,
                      onOpenControls: () => _openControls(context),
                      onAcknowledgeDropOff: onAcknowledgeAlert == null
                          ? null
                          : () {
                              _handleUserInteraction();
                              onAcknowledgeAlert?.call();
                            },
                    ),
                  ),
                if (!_isChromeCollapsed)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF102725).withValues(alpha: 0.84),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          driverName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          availabilityNote,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white70,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        StatusBadge(
                                          status: isOnline
                                              ? hasTrip
                                                  ? trip!.status
                                                  : 'ready'
                                              : 'offline',
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.route,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  routeLabel,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MapStatTile(
                                      label: 'On board',
                                      value: displayedOnboard.toString(),
                                      accent: scheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _MapStatTile(
                                      label: 'Pickup alerts',
                                      value: activePickupCount.toString(),
                                      accent: const Color(0xFFE29B2D),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _MapStatTile(
                                      label: 'Unload alerts',
                                      value: activeDestinationAlerts.length
                                          .toString(),
                                      accent: const Color(0xFFCC4B7A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (activeDestinationAlerts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DriverPopupAlert(
                            title: 'Passenger nearing destination',
                            message: activeDestinationAlerts.length == 1
                                ? '${activeDestinationAlerts.first.stopRef} is ready for unloading.'
                                : '${activeDestinationAlerts.first.stopRef} plus ${activeDestinationAlerts.length - 1} more unloading alerts are active.',
                            onClose: onDismissAlert,
                          ),
                        ],
                        if (trip?.operatingMode == 'terminal_queue')
                          TerminalLoadingClock(summary: trip?.terminalSummary),
                        if (requirementMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    requirementMessage!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close info',
                                  onPressed: onDismissRequirementMessage,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (statusMessage != null &&
                            statusMessage!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    statusMessage!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close info',
                                  onPressed: onDismissStatusMessage,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Positioned(
                  right: 16,
                  left: 16,
                  bottom: 112,
                  child: StreamBuilder<int>(
                      stream: Stream<int>.periodic(
                          const Duration(seconds: 2), (i) => i),
                      builder: (context, _) => Row(children: [
                            Expanded(
                                child: IgnorePointer(
                                    child: Card(
                                        child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Text(
                                                widget.readFollowStatus()))))),
                            SizedBox(
                                width: 132,
                                child: FilledButton.icon(
                                    onPressed: widget.onRecenter,
                                    icon: const Icon(Icons.my_location),
                                    label: const Text('Recenter'))),
                          ])),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      _handleUserInteraction();
                      if (details.primaryVelocity != null &&
                          details.primaryVelocity! < -120) {
                        _openControlSheet(context);
                      }
                    },
                    onTap: () => _openControls(context),
                    child: _isChromeCollapsed
                        ? _DriveMapMiniControl(hasTrip: trip != null)
                        : Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  scheme.primary.withValues(alpha: 0.94),
                                  const Color(0xFF0D4E47)
                                      .withValues(alpha: 0.96),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.swipe_up,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        trip == null
                                            ? 'No trip selected - pull up for controls'
                                            : 'Trip control panel - pull up',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.keyboard_arrow_up,
                                  color: Colors.white.withValues(alpha: 0.9),
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
      ),
    );
  }
}

class _DriveMapMiniOverlay extends StatelessWidget {
  const _DriveMapMiniOverlay({
    required this.status,
    required this.routeLabel,
    required this.displayedOnboard,
    required this.activePickupCount,
    required this.activeDropOffCount,
    required this.onOpenControls,
    this.dropOffLabel,
    this.onAcknowledgeDropOff,
  });

  final String status;
  final String routeLabel;
  final int displayedOnboard;
  final int activePickupCount;
  final int activeDropOffCount;
  final String? dropOffLabel;
  final VoidCallback onOpenControls;
  final VoidCallback? onAcknowledgeDropOff;

  @override
  Widget build(BuildContext context) {
    final hasDropOff = activeDropOffCount > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102725).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StatusBadge(status: status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open controls',
                  onPressed: onOpenControls,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  color: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    icon: Icons.groups_2_outlined,
                    label: 'Onboard',
                    value: displayedOnboard.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniMetric(
                    icon: Icons.hail_outlined,
                    label: 'Pickup',
                    value: activePickupCount.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniMetric(
                    icon: Icons.flag_outlined,
                    label: 'Drop-off',
                    value: activeDropOffCount.toString(),
                    accent: hasDropOff
                        ? const Color(0xFFFFC3D4)
                        : const Color(0xFFDDE8E7),
                  ),
                ),
              ],
            ),
            if (hasDropOff) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2EE).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFC8BA)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active,
                      color: Color(0xFFB24E34),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dropOffLabel == null
                            ? '$activeDropOffCount passenger drop-off alerts'
                            : '$dropOffLabel drop-off ready',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5F2517),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriveMapMiniControl extends StatelessWidget {
  const _DriveMapMiniControl({
    required this.hasTrip,
  });

  final bool hasTrip;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D4E47).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              hasTrip ? 'Controls' : 'Trip controls',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = const Color(0xFFDDE8E7),
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStatTile extends StatelessWidget {
  const _MapStatTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
  const _NotificationCard({
    required this.notification,
    this.onClose,
  });

  final NotificationModel notification;
  final VoidCallback? onClose;

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
                      IconButton(
                        tooltip: 'Close notification',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
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

class _PassengerAdjustmentControls extends StatelessWidget {
  const _PassengerAdjustmentControls({
    required this.enabled,
    required this.manualCount,
    required this.displayedOnboard,
    required this.capacity,
    required this.onAdjust,
  });

  final bool enabled;
  final int manualCount;
  final int displayedOnboard;
  final int? capacity;
  final void Function(int delta)? onAdjust;

  bool _canApply(int delta) {
    if (!enabled || onAdjust == null) return false;
    if (manualCount + delta < 0) return false;
    if (delta > 0 && capacity != null && capacity! > 0) {
      return displayedOnboard + delta <= capacity!;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    const negative = [-1, -2, -3, -5];
    const positive = [1, 2, 3, 5];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Walk-in passenger adjustments',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                letterSpacing: 0.2,
              ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final delta in negative) ...[
                _PassengerAdjustmentChip(
                  delta: delta,
                  enabled: _canApply(delta),
                  onTap: onAdjust == null ? null : () => onAdjust!(delta),
                ),
                const SizedBox(width: 8),
              ],
              for (final delta in positive) ...[
                _PassengerAdjustmentChip(
                  delta: delta,
                  enabled: _canApply(delta),
                  onTap: onAdjust == null ? null : () => onAdjust!(delta),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PassengerAdjustmentChip extends StatelessWidget {
  const _PassengerAdjustmentChip({
    required this.delta,
    required this.enabled,
    required this.onTap,
  });

  final int delta;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sign = delta > 0 ? '+' : '−';
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          '${delta > 0 ? 'Add' : 'Remove'} ${delta.abs()} walk-in passengers',
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white38,
          minimumSize: const Size(60, 52),
          side: BorderSide(
            color: Colors.white.withValues(alpha: enabled ? 0.42 : 0.14),
          ),
          backgroundColor:
              Colors.white.withValues(alpha: enabled ? 0.10 : 0.04),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          '$sign${delta.abs()}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _DriverPopupAlert extends StatelessWidget {
  const _DriverPopupAlert({
    required this.title,
    required this.message,
    this.onClose,
  });

  final String title;
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2EE).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFC8BA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFB24E34).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active,
                    color: Color(0xFFB24E34)),
              ),
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
                    Text(
                      message,
                      style: const TextStyle(height: 1.35),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close alert',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
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
    final icon = Icon(entry.icon, color: Colors.white, size: 20);
    final markerIcon = entry.rotateWithHeading && entry.headingDegrees != null
        ? Transform.rotate(
            angle: (entry.headingDegrees! + MapCamera.of(context).rotation) *
                math.pi /
                180,
            child: icon,
          )
        : icon;

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
          child: markerIcon,
        ),
      ],
    );
  }
}

enum _DriveMarkerKind {
  landmark,
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
    this.headingDegrees,
    this.rotateWithHeading = false,
  });

  final String label;
  final String detail;
  final LatLng position;
  final IconData icon;
  final Color markerColor;
  final _DriveMarkerKind kind;
  final double? headingDegrees;
  final bool rotateWithHeading;
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
