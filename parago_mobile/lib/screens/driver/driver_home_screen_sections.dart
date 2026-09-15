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

  RouteSummaryModel? _effectiveRouteSummaryForTrip(TripSession trip) {
    final tripRoute = _routeSummaryForTrip(trip);
    if (tripRoute != null) {
      return tripRoute;
    }
    return _assignedRouteSummary();
  }

  List<LatLng> _cachedPreviewPath({
    String? routeId,
    String? routeCode,
  }) {
    if (routeId != null) {
      final points = _cachedRoutePreviewPoints[routeId];
      if (points != null && points.length >= 2) {
        return points;
      }
    }

    if (routeCode != null && routeCode.isNotEmpty) {
      for (final route in _routes) {
        if (route.code == routeCode) {
          final points = _cachedRoutePreviewPoints[route.id];
          if (points != null && points.length >= 2) {
            return points;
          }
        }
      }
    }

    return const <LatLng>[];
  }

  // ignore: unused_element
  // Kept temporarily for route troubleshooting without exposing a driver-facing debug panel.
  List<String> _routeDebugLines({
    required TripSession? focusedTrip,
    required RouteSummaryModel? assignedRoute,
    required List<LatLng> routePath,
  }) {
    final lines = <String>[];
    final effectiveRoute = focusedTrip == null
        ? assignedRoute
        : _effectiveRouteSummaryForTrip(focusedTrip);
    final tripRoute =
        focusedTrip == null ? null : _routeSummaryForTrip(focusedTrip);

    lines.add(
      'drawn route: ${effectiveRoute?.code ?? 'none'} · '
      '${effectiveRoute?.id ?? 'no-id'} · ${routePath.length} pts',
    );
    if (effectiveRoute != null) {
      lines.add(
        'cached preview points: '
        '${_cachedPreviewPath(routeId: effectiveRoute.id, routeCode: effectiveRoute.code).length}',
      );
    }

    if (focusedTrip != null) {
      lines.add(
        'trip route: ${tripRoute?.code ?? focusedTrip.routeId} · '
        '${focusedTrip.routeId}',
      );
      lines.add(
        'trip snapshot points: ${focusedTrip.routePathSnapshotPoints.length}',
      );
    }

    if (assignedRoute != null) {
      lines.add(
        'assigned route: ${assignedRoute.code} · ${assignedRoute.id} · '
        '${assignedRoute.mapPath.length} pts',
      );
    }

    return lines;
  }

  int _displayedOnboardCount(TripSession? trip, List<RideSessionModel> rides) {
    if (trip == null) return 0;
    return _baseOnboardCount(trip, rides);
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
    if (trip.routePathSnapshotPoints.isNotEmpty) {
      return trip
          .routePathSnapshotPoints[trip.routePathSnapshotPoints.length ~/ 2];
    }
    final effectiveRoute = _effectiveRouteSummaryForTrip(trip);
    final cachedPreview = _cachedPreviewPath(
      routeId: effectiveRoute?.id ?? trip.routeId,
      routeCode: effectiveRoute?.code ?? trip.routeCode,
    );
    if (cachedPreview.isNotEmpty) {
      return cachedPreview[cachedPreview.length ~/ 2];
    }
    final route = effectiveRoute;
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
    if (trip.routePathSnapshotPoints.length >= 2) {
      return trip.routePathSnapshotPoints;
    }
    final route = _effectiveRouteSummaryForTrip(trip);
    final cachedPreview = _cachedPreviewPath(
      routeId: route?.id ?? trip.routeId,
      routeCode: route?.code ?? trip.routeCode,
    );
    if (cachedPreview.length >= 2) {
      return cachedPreview;
    }
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
    final lat = request.pickupType == 'terminal'
        ? (request.terminalLatitude ?? request.pickupLatitude)
        : request.pickupLatitude;
    final lng = request.pickupType == 'terminal'
        ? (request.terminalLongitude ?? request.pickupLongitude)
        : request.pickupLongitude;
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

  LatLng? _rideDestinationPosition(RideSessionModel ride) {
    final lat = ride.destinationLatitude;
    final lng = ride.destinationLongitude;
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
    final routeSummary = _effectiveRouteSummaryForTrip(trip);

    final markers = <_DriveMarkerData>[
      for (var index = 0;
          index < (routeSummary?.stopPoints.length ?? 0);
          index += 1)
        _DriveMarkerData(
          label: '${index + 1}. ${routeSummary!.stopPoints[index].name}',
          detail: 'Route landmark',
          position: routeSummary.stopPoints[index].position,
          icon: Icons.place,
          markerColor: const Color(0xFF8A3B5D),
          kind: _DriveMarkerKind.landmark,
        ),
      _DriveMarkerData(
        label: trip.jeepneyLabel,
        detail: 'Current jeepney location',
        position: jeepneyPosition,
        icon: Icons.directions_bus_filled,
        markerColor: const Color(0xFF2E8B57),
        kind: _DriveMarkerKind.vehicle,
        headingDegrees: _vehicleHeadingDegrees,
        rotateWithHeading: true,
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
          label: request.pickupType == 'terminal'
              ? (request.terminalStopRef ??
                  request.stopRef ??
                  'Terminal passenger')
              : (request.stopRef ?? 'Pickup ${index + 1}'),
          detail: request.status == 'acknowledged'
              ? request.pickupType == 'terminal'
                  ? 'Acknowledged terminal boarding'
                  : 'Acknowledged pickup'
              : request.pickupType == 'terminal'
                  ? 'Waiting at terminal'
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
          (alert) => _DriverHomeScreenState._activeAlertStatuses
              .contains(alert.status),
        )
        .toList();
    final alertedRideIds = activeAlerts
        .map((alert) => alert.rideSessionId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
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

    final onboardDestinationRides = rides
        .where(
          (ride) =>
              ride.status == 'onboard' &&
              !alertedRideIds.contains(ride.id) &&
              ((ride.destinationStopRef ?? '').trim().isNotEmpty ||
                  _rideDestinationPosition(ride) != null),
        )
        .toList(growable: false);
    for (var index = 0; index < onboardDestinationRides.length; index += 1) {
      final ride = onboardDestinationRides[index];
      markers.add(
        _DriveMarkerData(
          label: (ride.destinationStopRef ?? '').trim().isEmpty
              ? 'Passenger destination'
              : ride.destinationStopRef!.trim(),
          detail: 'Saved unload destination for an onboard passenger',
          position: _rideDestinationPosition(ride) ??
              routePath[math.min(index + 2, routePath.length - 1)],
          icon: Icons.flag_outlined,
          markerColor: const Color(0xFF7B61C8),
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
        return 'Driver Notifications';
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
          rides: focusedRides,
        );
      case 3:
        return _buildNotificationsTab(
          notifications: _notifications,
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
    final startRequirementMessage = focusedTrip == null
        ? null
        : _driverStartRequirementMessage(trip: focusedTrip);
    final pickupRequirementMessage = focusedTrip == null
        ? null
        : _driverPickupRequirementMessage(trip: focusedTrip);
    final visibleOperationsMessage =
        _visibleInfoMessage(_driverOperationsBannerMessage(focusedTrip));
    final visibleStatusMessage = _visibleInfoMessage(_statusMessage);
    final displayedOnboard = _displayedOnboardCount(focusedTrip, focusedRides);
    final activeAlerts = focusedAlerts
        .where(
          (alert) =>
              _DriverHomeScreenState._activeAlertStatuses
                  .contains(alert.status) &&
              !_isDriveAlertDismissed(alert.id),
        )
        .toList();
    final assignedRoute = _assignedRouteSummary();
    final liveVehicleLocation = _vehicleLocation;
    final tripVehicleLocation =
        focusedTrip == null ? null : _vehicleLocationForTrip(focusedTrip);
    final assignedCachedPreview = assignedRoute == null
        ? const <LatLng>[]
        : _cachedPreviewPath(
            routeId: assignedRoute.id,
            routeCode: assignedRoute.code,
          );
    final routePath = focusedTrip != null
        ? _routePathForTrip(
            focusedTrip,
            center: tripVehicleLocation,
          )
        : (assignedCachedPreview.isNotEmpty
            ? assignedCachedPreview
            : (assignedRoute?.mapPath ?? const <LatLng>[]));
    final markers = <_DriveMarkerData>[];

    if (liveVehicleLocation != null && focusedTrip == null) {
      markers.add(
        _DriveMarkerData(
          label: 'Current location',
          detail: 'Live device GPS',
          position: liveVehicleLocation,
          icon: Icons.my_location,
          markerColor: const Color(0xFF1F8FD5),
          kind: _DriveMarkerKind.vehicle,
          headingDegrees: _vehicleHeadingDegrees,
          rotateWithHeading: true,
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

    _routeDebugLines(
      focusedTrip: focusedTrip,
      assignedRoute: assignedRoute,
      routePath: routePath,
    );

    return _DriveMapPanel(
      mapController: _driverMapController,
      cameraTarget: mapCenter,
      trip: focusedTrip,
      driverName: session.user?.fullName ?? 'Driver',
      statusMessage: visibleStatusMessage,
      requirementMessage: visibleOperationsMessage,
      availabilityNote: _availabilityNote,
      isOnline: _isOnline,
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
      seatCapacity: focusedTrip?.jeepneyCapacity,
      manualPassengerCount: _manualOnboardCount(focusedTrip),
      routePath: routePath,
      markers: markers,
      activeDestinationAlerts: activeAlerts,
      onIncrement: focusedTrip == null
          ? null
          : () => _changePassengerCount(focusedTrip.id, 1),
      onDecrement: focusedTrip == null
          ? null
          : () => _changePassengerCount(focusedTrip.id, -1),
      onStartTrip: _loading ||
              (focusedTrip != null && focusedTrip.status == 'active') ||
              startRequirementMessage != null
          ? null
          : () => _startTrip(focusedTrip),
      onEndTrip:
          focusedTrip == null || _loading || focusedTrip.status != 'active'
              ? null
              : () => _endTrip(focusedTrip.id),
      onTogglePickup: focusedTrip == null ||
              _loading ||
              focusedTrip.status != 'active' ||
              (focusedTrip.operatingMode != 'terminal_queue' &&
                  focusedTrip.acceptRequests == false &&
                  pickupRequirementMessage != null)
          ? null
          : () => _toggleAccept(
                focusedTrip,
                !(focusedTrip.acceptRequests ?? true),
              ),
      onAcknowledgeAlert: null,
      onDismissAlert: activeAlerts.isEmpty
          ? null
          : () => _dismissDriveAlert(activeAlerts.first.id),
      onDismissRequirementMessage: visibleOperationsMessage == null
          ? null
          : () => _dismissInfoMessage(visibleOperationsMessage),
      onDismissStatusMessage: visibleStatusMessage == null
          ? null
          : () => _dismissInfoMessage(visibleStatusMessage),
      onMapReady: _handleDriverMapReady,
      onPositionChanged: _handleDriverMapPositionChanged,
      readLiveData: () {
        final liveTrip = _focusedTrip;
        final liveRequests = liveTrip == null
            ? const <PickupRequestModel>[]
            : (_tripRequests[liveTrip.id] ?? const <PickupRequestModel>[]);
        final liveAlerts = liveTrip == null
            ? const <StopAlertModel>[]
            : (_tripAlerts[liveTrip.id] ?? const <StopAlertModel>[]);
        final liveRides = liveTrip == null
            ? const <RideSessionModel>[]
            : (_tripRides[liveTrip.id] ?? const <RideSessionModel>[]);

        final liveStartRequirement = liveTrip == null
            ? null
            : _driverStartRequirementMessage(trip: liveTrip);
        final livePickupRequirement = liveTrip == null
            ? null
            : _driverPickupRequirementMessage(trip: liveTrip);
        final liveActiveAlerts = liveAlerts
            .where(
              (alert) =>
                  _DriverHomeScreenState._activeAlertStatuses.contains(
                    alert.status,
                  ) &&
                  !_isDriveAlertDismissed(alert.id),
            )
            .toList(growable: false);

        final liveOperationsMessage =
            _visibleInfoMessage(_driverOperationsBannerMessage(liveTrip));
        final liveStatusMessage = _visibleInfoMessage(_statusMessage);

        return _DrivePanelLiveData(
          trip: liveTrip,
          routeLabel: liveTrip == null
              ? (_assignedRouteSummary()?.label ?? 'Metro overview')
              : _routeLabel(liveTrip),
          isOnline: _isOnline,
          availabilityNote: _availabilityNote,
          requirementMessage: liveOperationsMessage,
          statusMessage: liveStatusMessage,
          displayedOnboard: _displayedOnboardCount(liveTrip, liveRides),
          seatCapacity: liveTrip?.jeepneyCapacity,
          manualPassengerCount: _manualOnboardCount(liveTrip),
          activePickupCount: liveRequests
              .where(
                (request) => _DriverHomeScreenState._pickupStatuses.contains(
                  request.status,
                ),
              )
              .length,
          activeDestinationAlerts: liveActiveAlerts,
          onIncrement: liveTrip == null
              ? null
              : () => _changePassengerCount(liveTrip.id, 1),
          onDecrement: liveTrip == null
              ? null
              : () => _changePassengerCount(liveTrip.id, -1),
          onStartTrip: _loading ||
                  (liveTrip != null && liveTrip.status == 'active') ||
                  liveStartRequirement != null
              ? null
              : () => _startTrip(liveTrip),
          onEndTrip: liveTrip == null || _loading || liveTrip.status != 'active'
              ? null
              : () => _endTrip(liveTrip.id),
          onTogglePickup: liveTrip == null ||
                  _loading ||
                  liveTrip.status != 'active' ||
                  (liveTrip.operatingMode != 'terminal_queue' &&
                      liveTrip.acceptRequests == false &&
                      livePickupRequirement != null)
              ? null
              : () => _toggleAccept(
                    liveTrip,
                    !(liveTrip.acceptRequests ?? true),
                  ),
          onDismissAlert: liveActiveAlerts.isEmpty
              ? null
              : () => _dismissDriveAlert(liveActiveAlerts.first.id),
          onDismissRequirementMessage: liveOperationsMessage == null
              ? null
              : () => _dismissInfoMessage(liveOperationsMessage),
          onDismissStatusMessage: liveStatusMessage == null
              ? null
              : () => _dismissInfoMessage(liveStatusMessage),
        );
      },
      height: mapHeight,
    );
  }

  Widget _buildRequestsTab({
    required TripSession? focusedTrip,
    required List<PickupRequestModel> requests,
  }) {
    final pickupRequirementMessage = focusedTrip == null
        ? null
        : _driverPickupRequirementMessage(trip: focusedTrip);
    final visiblePickupRequirementMessage =
        _visibleInfoMessage(pickupRequirementMessage);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        if (visiblePickupRequirementMessage != null) ...[
          _DriverStatusBanner(
            message: visiblePickupRequirementMessage,
            onClose: () => _dismissInfoMessage(visiblePickupRequirementMessage),
          ),
          const SizedBox(height: 16),
        ],
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
              detail: request.status == 'acknowledged'
                  ? request.pickupType == 'terminal'
                      ? 'Terminal boarding acknowledged. Wait for the passenger to validate boarding from the passenger app.'
                      : 'Pickup acknowledged. Wait for the passenger to validate boarding from the passenger app.'
                  : request.status == 'completed'
                      ? 'Passenger boarding has been validated and the ride is already active.'
                      : request.sourceNote ??
                          (request.pickupType == 'terminal'
                              ? 'Passenger requested terminal boarding.'
                              : 'Passenger requested a roadside pickup.'),
              status: request.status,
              primaryLabel: request.status == 'pending' ? 'Acknowledge' : null,
              onPrimary: request.status == 'pending' &&
                      visiblePickupRequirementMessage == null
                  ? () => _acknowledgeRequest(focusedTrip, request.id)
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
    required List<RideSessionModel> rides,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        if (focusedTrip == null)
          const _DriverEmptyState(
            title: 'No trip selected',
            message: 'Select a trip to review onboard passenger destinations.',
          )
        else ...[
          () {
            final onboardRides = rides
                .where((ride) => ride.status == 'onboard')
                .toList(growable: false);
            if (onboardRides.isEmpty) {
              return const _DriverEmptyState(
                title: 'No onboard passengers',
                message:
                    'Saved unload destinations appear here once riders board.',
              );
            }
            return Column(
              children: [
                for (var index = 0;
                    index < onboardRides.length;
                    index += 1) ...[
                  () {
                    final ride = onboardRides[index];
                    final destinationLabel =
                        (ride.destinationStopRef ?? '').trim().isEmpty
                            ? 'Saved destination ${index + 1}'
                            : ride.destinationStopRef!.trim();
                    final hasSavedPoint =
                        _rideDestinationPosition(ride) != null;
                    return _DriverActionCard(
                      title: destinationLabel,
                      subtitle:
                          '${ride.passengerLabel} · Booking ${ride.bookingLabel}\nOnboard - ${ParagoFormat.relative(ride.boardedAt)}',
                      detail: hasSavedPoint
                          ? 'Saved drop-off location is pinned on the driver map.'
                          : 'Passenger saved a drop-off stop reference without map coordinates.',
                      status: ride.status,
                      secondaryLabel: 'Mark unloaded',
                      onSecondary: () => _completeRideDestination(ride),
                      icon: Icons.location_on_outlined,
                    );
                  }(),
                  if (index < onboardRides.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            );
          }(),
        ],
        const SizedBox(height: 18),
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
            () {
              RideSessionModel? matchingRide;
              for (final ride in rides) {
                if (ride.id == alert.rideSessionId) {
                  matchingRide = ride;
                  break;
                }
              }
              final canCompleteUnload = matchingRide != null &&
                  matchingRide.status == 'onboard' &&
                  alert.status != 'dismissed';

              return _DriverActionCard(
                title: alert.stopRef,
                subtitle:
                    '${ParagoFormat.statusLabel(alert.status)} - ${ParagoFormat.relative(alert.createdAt)}',
                detail: alert.note ??
                    'Passenger is nearing the selected unloading point.',
                status: alert.status,
                secondaryLabel: canCompleteUnload ? 'Mark unloaded' : null,
                onSecondary: canCompleteUnload
                    ? () => _completeUnloadAlert(alert)
                    : null,
                icon: Icons.flag_circle_outlined,
              );
            }(),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildNotificationsTab({
    required List<NotificationModel> notifications,
  }) {
    final visibleNotifications = notifications
        .where((item) => !_isNotificationDismissed(item.id))
        .toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        for (final announcement in _announcements) ...[
          AnnouncementCard(
            announcement: announcement,
            onDismiss: () => _dismissAnnouncement(announcement),
          ),
          const SizedBox(height: 12),
        ],
        if (visibleNotifications.isEmpty && _announcements.isEmpty)
          const _DriverEmptyState(
            title: 'No notifications yet',
            message: 'System notices and event confirmations will appear here.',
          )
        else
          for (final notification in visibleNotifications) ...[
            _NotificationCard(
              notification: notification,
              onClose: () => _dismissNotification(notification.id),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}
