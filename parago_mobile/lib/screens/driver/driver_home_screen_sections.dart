part of 'driver_home_screen.dart';

extension _DriverHomeScreenSections on _DriverHomeScreenState {
  RouteSummaryModel? _assignedRouteSummary() {
    final routeId = _assignedRouteId;
    if (routeId == null || routeId.isEmpty) {
      return null;
    }
    for (final route in _routes) {
      if (route.id == routeId) {
        return route;
      }
    }
    return null;
  }

  int _displayedOnboardCount(TripSession? trip, List<RideSessionModel> rides) {
    if (trip == null) return 0;
    final base = _baseOnboardCount(trip, rides);
    final delta = _manualOnboardAdjustments[trip.id] ?? 0;
    return math.max(0, base + delta);
  }

  RouteSummaryModel? _routeSummaryForTrip(TripSession trip) {
    for (final route in _routes) {
      if (route.id == trip.routeId) {
        return route;
      }
    }
    return null;
  }

  LatLng _baseMapCenter(TripSession trip) {
    final route = _routeSummaryForTrip(trip);
    final routePoints = route?.referencePoints ?? const <LatLng>[];
    if (routePoints.isNotEmpty) {
      return routePoints[routePoints.length ~/ 2];
    }
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
    final route = _routeSummaryForTrip(trip);
    final savedPath = route?.mapPath ?? const <LatLng>[];
    if (savedPath.length >= 2) {
      return savedPath;
    }
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

  LatLng? _pickupPosition(PickupRequestModel request) {
    final lat = request.pickupLatitude;
    final lng = request.pickupLongitude;
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  LatLng? _unloadPosition(StopAlertModel alert) {
    final lat = alert.latitude;
    final lng = alert.longitude;
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
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
        .where(
          (request) =>
              _DriverHomeScreenState._pickupStatuses.contains(request.status),
        )
        .toList();
    for (var index = 0; index < activeRequests.length; index += 1) {
      final request = activeRequests[index];
      markers.add(
        _DriveMarkerData(
          label: request.stopRef ?? 'Pickup ${index + 1}',
          detail: request.status == 'acknowledged'
              ? 'Acknowledged pickup'
              : 'Waiting pickup',
          position: _pickupPosition(request) ??
              routePath[math.min(index, routePath.length - 1)],
          icon: Icons.person_pin_circle,
          markerColor: request.status == 'acknowledged'
              ? const Color(0xFF1F8FD5)
              : const Color(0xFFE2902D),
          kind: _DriveMarkerKind.pickup,
        ),
      );
    }

    final activeAlerts = alerts
        .where(
          (alert) =>
              _DriverHomeScreenState._activeAlertStatuses.contains(alert.status),
        )
        .toList();
    for (var index = 0; index < activeAlerts.length; index += 1) {
      final alert = activeAlerts[index];
      markers.add(
        _DriveMarkerData(
          label: alert.stopRef,
          detail: 'Unload request near destination',
          position: _unloadPosition(alert) ??
              routePath[math.min(index + 2, routePath.length - 1)],
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
        .where(
          (alert) =>
              _DriverHomeScreenState._activeAlertStatuses.contains(alert.status),
        )
        .toList();
    final assignedRoute = _assignedRouteSummary();
    final liveVehicleLocation = _vehicleLocation;
    final tripVehicleLocation =
        focusedTrip == null ? null : _vehicleLocationForTrip(focusedTrip);
    final routePath = focusedTrip != null
        ? _routePathForTrip(
            focusedTrip,
            center: tripVehicleLocation,
          )
        : (assignedRoute?.mapPath ?? const <LatLng>[]);
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
          .where(
            (request) =>
                _DriverHomeScreenState._pickupStatuses.contains(request.status),
          )
          .length,
      routeLabel: focusedTrip == null
          ? (assignedRoute?.label ?? 'Metro overview')
          : _routeLabel(focusedTrip),
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
              detail:
                  request.sourceNote ?? 'Passenger requested a roadside pickup.',
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
        Text(
          'Passenger destination alerts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
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
              detail:
                  alert.note ?? 'Passenger is nearing the selected unloading point.',
              status: alert.status,
              primaryLabel:
                  _DriverHomeScreenState._activeAlertStatuses.contains(
                alert.status,
              )
                  ? 'Acknowledge'
                  : null,
              onPrimary:
                  _DriverHomeScreenState._activeAlertStatuses.contains(
                alert.status,
              )
                  ? () => _acknowledgeAlert(alert.id)
                  : null,
              icon: Icons.flag_circle_outlined,
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 18),
        Text(
          'Driver notifications',
          style: Theme.of(context).textTheme.titleLarge,
        ),
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
        .where(
          (alert) =>
              _DriverHomeScreenState._activeAlertStatuses.contains(alert.status),
        )
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
                Text(
                  'Operational summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
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
}
