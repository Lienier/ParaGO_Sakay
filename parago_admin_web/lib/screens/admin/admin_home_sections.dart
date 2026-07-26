part of 'admin_home_screen.dart';

class _AdminCompactNav extends StatelessWidget {
  const _AdminCompactNav({
    required this.selectedSection,
    required this.onSelect,
  });

  final _AdminWorkspaceSection selectedSection;
  final ValueChanged<_AdminWorkspaceSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in _AdminWorkspaceSection.values) ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                avatar: Icon(_sectionIcon(section), size: 18),
                label: Text(_sectionLabel(section)),
                selected: selectedSection == section,
                onSelected: (_) => onSelect(section),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminOverviewPage extends StatelessWidget {
  const _AdminOverviewPage({
    required this.loading,
    required this.error,
    required this.dashboard,
    required this.passengerFlowReport,
    required this.hybridDispatchBoard,
    required this.lastSyncedAt,
    required this.showingCachedSnapshot,
    required this.onRefresh,
    required this.onReorderTerminalTrip,
    required this.onSetTerminalTripSkipped,
    required this.onSetTerminalTripStatus,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final Map<String, dynamic>? passengerFlowReport;
  final Map<String, dynamic>? hybridDispatchBoard;
  final DateTime? lastSyncedAt;
  final bool showingCachedSnapshot;
  final Future<void> Function({bool silent}) onRefresh;
  final Future<void> Function(String tripId, String direction)
      onReorderTerminalTrip;
  final Future<void> Function(String tripId, bool skipped)
      onSetTerminalTripSkipped;
    final Future<void> Function(String tripId, String terminalQueueStatus)
      onSetTerminalTripStatus;

  @override
  Widget build(BuildContext context) {
    final metrics = dashboard ?? const <String, dynamic>{};
    final passengerFlow = passengerFlowReport ?? const <String, dynamic>{};
    final hybridDispatch = hybridDispatchBoard ?? const <String, dynamic>{};
    final terminalQueue = _readDynamicList(hybridDispatch['terminalQueue']);
    final waitingTerminalPassengers = _readDynamicList(
      hybridDispatch['waitingTerminalPassengers'],
    );
    final routeDrivers = _readDynamicList(hybridDispatch['routeDrivers']);
    final summary = _readDynamicMap(passengerFlow['summary']);
    final dailyFlow = _parsePassengerFlowSeries(passengerFlow['daily']);
    final topBoardingLocations = _parsePassengerFlowLocations(
      passengerFlow['topBoardingLocations'],
    );
    final topUnloadLocations = _parsePassengerFlowLocations(
      passengerFlow['topUnloadLocations'],
    );
    final topBoardingLocation = _parsePassengerFlowLocation(
      summary['topBoardingLocation'],
    );
    final topUnloadLocation = _parsePassengerFlowLocation(
      summary['topUnloadLocation'],
    );

    return RefreshIndicator(
      onRefresh: () => onRefresh(silent: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        children: [
          if (loading) ...[
            const LinearProgressIndicator(),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            _AdminInfoBanner(message: error!, isWarning: true),
          ],
          if (lastSyncedAt != null) ...[
            const SizedBox(height: 16),
            _AdminInfoBanner(
              message: showingCachedSnapshot
                  ? 'Showing the latest saved dashboard data from ${ParagoFormat.relative(lastSyncedAt!.toIso8601String())}.'
                  : 'Last synced ${ParagoFormat.relative(lastSyncedAt!.toIso8601String())}.',
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: MetricCard(
                  label: 'Active trips',
                  value: metrics['activeTrips']?.toString() ?? '0',
                  icon: Icons.route_outlined,
                  accent: const Color(0xFF0F6A5F),
                  caption: 'Trips currently operating across the system',
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  label: 'Pending pickups',
                  value: metrics['pendingRequests']?.toString() ?? '0',
                  icon: Icons.near_me_outlined,
                  accent: const Color(0xFFE29B2D),
                  caption: 'Pickup requests still waiting for resolution',
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  label: 'Onboard rides',
                  value: metrics['onboardRides']?.toString() ?? '0',
                  icon: Icons.groups_2_outlined,
                  accent: const Color(0xFF2157A5),
                  caption: 'Passengers currently onboard active trips',
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  label: 'Terminal queue trips',
                  value: metrics['terminalQueueTrips']?.toString() ?? '0',
                  icon: Icons.queue_outlined,
                  accent: const Color(0xFF8A3B5D),
                  caption: 'Active trips currently operating from the terminal',
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  label: 'Route-mode trips',
                  value: metrics['routeModeTrips']?.toString() ?? '0',
                  icon: Icons.alt_route_outlined,
                  accent: const Color(0xFF4E6B2B),
                  caption: 'Active trips already running on the route',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Terminal dispatch board',
            subtitle:
                'Shows the jeepney queue at the terminal, waiting terminal passengers, and route-mode drivers.',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1050;
                final terminalCard = _HybridDispatchColumn(
                  title: 'Terminal queue',
                  accent: const Color(0xFF8A3B5D),
                  emptyMessage: 'No active terminal queue trips yet.',
                  children: [
                    for (final trip in terminalQueue)
                      _HybridDispatchTile(
                          actions: _terminalQueueActions(
                            trip,
                            index: terminalQueue.indexOf(trip),
                            total: terminalQueue.length,
                            onReorder: onReorderTerminalTrip,
                            onSkippedChanged: onSetTerminalTripSkipped,
                            onStatusChanged: onSetTerminalTripStatus,
                          ),
                          title:
                              '#${trip['terminalQueueNumber'] ?? '-'} ${_dispatchTripLabel(trip)}',
                          subtitle:
                              '${_dispatchTripMode(trip)} · ${_dispatchTerminalLabel(trip)}',
                          caption:
                              '${trip['occupancyCount'] ?? 0} onboard · ${ParagoFormat.statusLabel(trip['terminalQueueStatus']?.toString() ?? 'waiting')}',
                        ),
                  ],
                );
                final waitingCard = _HybridDispatchColumn(
                  title: 'Waiting terminal passengers',
                  accent: const Color(0xFFE29B2D),
                  emptyMessage: 'No terminal passengers waiting right now.',
                  children: [
                    if (waitingTerminalPassengers.isEmpty)
                      const Text('No terminal passengers waiting right now.')
                    else
                      for (final request in waitingTerminalPassengers)
                        _HybridDispatchTile(
                          title:
                              '${request['terminalStopRef'] ?? request['stopRef'] ?? 'Terminal passenger'} to ${request['destinationStopRef'] ?? 'Destination pending'}',
                          subtitle:
                              'Trip ${request['tripSessionId'] ?? '-'} · ${ParagoFormat.statusLabel(request['status']?.toString() ?? 'pending')}',
                          caption: request['sourceNote']?.toString() ??
                              'Passenger is waiting at the terminal.',
                        ),
                  ],
                );
                final routeCard = _HybridDispatchColumn(
                  title: 'Route-mode drivers',
                  accent: const Color(0xFF2157A5),
                  emptyMessage: 'No active route-mode trips yet.',
                  children: [
                    if (routeDrivers.isEmpty)
                      const Text('No active route-mode trips yet.')
                    else
                      for (final trip in routeDrivers)
                        _HybridDispatchTile(
                          title: _dispatchTripLabel(trip),
                          subtitle: _dispatchTripMode(trip),
                          caption:
                              '${trip['occupancyCount'] ?? 0} onboard · ${ParagoFormat.statusLabel(trip['status']?.toString() ?? 'active')}',
                        ),
                  ],
                );

                if (stacked) {
                  return Column(
                    children: [
                      terminalCard,
                      const SizedBox(height: 12),
                      waitingCard,
                      const SizedBox(height: 12),
                      routeCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: terminalCard),
                    const SizedBox(width: 12),
                    Expanded(child: waitingCard),
                    const SizedBox(width: 12),
                    Expanded(child: routeCard),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Passenger boarding and unload report',
            subtitle:
                'Shows the locations where passengers most often board and unload, with a separate 7-day trend underneath.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _PassengerFlowStatTile(
                      label: 'Total boarded',
                      value: _readCount(summary['totalBoarded']).toString(),
                      accent: const Color(0xFF0F6A5F),
                    ),
                    _PassengerFlowStatTile(
                      label: 'Total unloaded',
                      value: _readCount(summary['totalUnloaded']).toString(),
                      accent: const Color(0xFFE29B2D),
                    ),
                    _PassengerFlowStatTile(
                      label: 'Top boarding location',
                      value: topBoardingLocation?.label ?? 'No data yet',
                      caption: topBoardingLocation == null
                          ? null
                          : '${topBoardingLocation.count} passengers',
                      accent: const Color(0xFF2157A5),
                    ),
                    _PassengerFlowStatTile(
                      label: 'Top unload location',
                      value: topUnloadLocation?.label ?? 'No data yet',
                      caption: topUnloadLocation == null
                          ? null
                          : '${topUnloadLocation.count} passengers',
                      accent: const Color(0xFF8A3B5D),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (topBoardingLocations.isNotEmpty ||
                    topUnloadLocations.isNotEmpty)
                  _PassengerFlowHotspotMap(
                    boardingLocations: topBoardingLocations,
                    unloadLocations: topUnloadLocations,
                  )
                else
                  const Text('No location-based boarding and unload data yet.'),
                const SizedBox(height: 18),
                if (dailyFlow.isEmpty)
                  const Text('No passenger flow trend data available yet.')
                else
                  _PassengerFlowChart(series: dailyFlow),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 900;
                    final boardingCard = _PassengerFlowTopStopsCard(
                      title: 'Most boarded locations',
                      emptyLabel: 'No boarding-location data yet.',
                      stops: topBoardingLocations,
                      accent: const Color(0xFF0F6A5F),
                    );
                    final unloadCard = _PassengerFlowTopStopsCard(
                      title: 'Most unloaded locations',
                      emptyLabel: 'No unload-location data yet.',
                      stops: topUnloadLocations,
                      accent: const Color(0xFFE29B2D),
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          boardingCard,
                          const SizedBox(height: 12),
                          unloadCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: boardingCard),
                        const SizedBox(width: 12),
                        Expanded(child: unloadCard),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<dynamic> _readDynamicList(dynamic value) {
  return value is List<dynamic> ? value : const <dynamic>[];
}

String _dispatchTripLabel(dynamic value) {
  final map = _readDynamicMap(value);
  final route = _readDynamicMap(map['routeId']);
  final jeepney = _readDynamicMap(map['jeepneyId']);
  final routeCode = route['code']?.toString();
  final routeName = route['name']?.toString();
  final plateNumber = jeepney['plateNumber']?.toString();
  final parts = <String>[
    if (routeCode != null && routeCode.isNotEmpty) routeCode,
    if (routeName != null && routeName.isNotEmpty) routeName,
    if (plateNumber != null && plateNumber.isNotEmpty) plateNumber,
  ];
  return parts.isEmpty ? 'Trip ${map['_id'] ?? '-'}' : parts.join(' · ');
}

String _dispatchTripMode(dynamic value) {
  final map = _readDynamicMap(value);
  return map['operatingMode']?.toString() == 'terminal_queue'
      ? 'Terminal queue mode'
      : 'Route mode';
}

String _dispatchTerminalLabel(dynamic value) {
  final map = _readDynamicMap(value);
  final terminal = map['terminalStopRef']?.toString();
  if (terminal == null || terminal.isEmpty) {
    return 'Terminal pending';
  }
  return terminal;
}

List<Widget> _terminalQueueActions(
  dynamic value, {
  required int index,
  required int total,
  required Future<void> Function(String tripId, String direction) onReorder,
  required Future<void> Function(String tripId, bool skipped)
      onSkippedChanged,
  required Future<void> Function(String tripId, String terminalQueueStatus)
      onStatusChanged,
}) {
  final map = _readDynamicMap(value);
  final tripId = map['_id']?.toString() ?? '';
  if (tripId.isEmpty) {
    return const <Widget>[];
  }
  final skipped = map['terminalQueueStatus']?.toString() == 'skipped';
  final status = map['terminalQueueStatus']?.toString() ?? 'waiting';
  final loading = status == 'loading';
  final departed = status == 'departed';

  return [
    IconButton.outlined(
      onPressed: index <= 0 ? null : () => onReorder(tripId, 'up'),
      tooltip: 'Move up',
      icon: const Icon(Icons.keyboard_arrow_up),
    ),
    IconButton.outlined(
      onPressed: index >= total - 1 ? null : () => onReorder(tripId, 'down'),
      tooltip: 'Move down',
      icon: const Icon(Icons.keyboard_arrow_down),
    ),
    IconButton.filledTonal(
      onPressed: () => onSkippedChanged(tripId, !skipped),
      tooltip: skipped ? 'Restore to queue' : 'Skip this jeepney',
      icon: Icon(skipped ? Icons.undo : Icons.skip_next),
    ),
    IconButton.filledTonal(
      onPressed: departed ? null : () => onStatusChanged(tripId, 'loading'),
      tooltip: 'Mark loading',
      icon: const Icon(Icons.local_shipping_outlined),
    ),
    IconButton.filledTonal(
      onPressed: departed ? null : () => onStatusChanged(tripId, 'departed'),
      tooltip: 'Mark departed',
      icon: const Icon(Icons.departure_board_outlined),
    ),
    if (loading || departed)
      IconButton.outlined(
        onPressed: () => onStatusChanged(tripId, 'waiting'),
        tooltip: 'Mark waiting',
        icon: const Icon(Icons.access_time_outlined),
      ),
  ];
}

class _HybridDispatchColumn extends StatelessWidget {
  const _HybridDispatchColumn({
    required this.title,
    required this.accent,
    required this.emptyMessage,
    required this.children,
  });

  final String title;
  final Color accent;
  final String emptyMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(emptyMessage)
          else
            ...children
                .expand((child) => [child, const SizedBox(height: 10)])
                .toList()
              ..removeLast(),
        ],
      ),
    );
  }
}

class _HybridDispatchTile extends StatelessWidget {
  const _HybridDispatchTile({
    required this.title,
    required this.subtitle,
    required this.caption,
    this.actions = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final String caption;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 6),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF67726E),
                ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _PassengerFlowHotspotMap extends StatelessWidget {
  const _PassengerFlowHotspotMap({
    required this.boardingLocations,
    required this.unloadLocations,
  });

  final List<_PassengerFlowLocation> boardingLocations;
  final List<_PassengerFlowLocation> unloadLocations;

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[
      for (final location in boardingLocations) location.position,
      for (final location in unloadLocations) location.position,
    ];
    final center = _hotspotMapCenter(points);
    final zoom = _hotspotMapZoom(points);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Most boarded and unloaded locations',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Map hotspots show where passengers most often board and unload.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: const [
              _ChartLegend(
                label: 'Boarded',
                color: Color(0xFF0F6A5F),
              ),
              _ChartLegend(
                label: 'Unloaded',
                color: Color(0xFFE29B2D),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: zoom,
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
                  MarkerLayer(
                    markers: [
                      for (final location in boardingLocations)
                        Marker(
                          point: location.position,
                          width: 130,
                          height: 72,
                          child: _HotspotMarker(
                            label: location.label,
                            count: location.count,
                            accent: const Color(0xFF0F6A5F),
                            icon: Icons.login_rounded,
                          ),
                        ),
                      for (final location in unloadLocations)
                        Marker(
                          point: location.position,
                          width: 130,
                          height: 72,
                          child: _HotspotMarker(
                            label: location.label,
                            count: location.count,
                            accent: const Color(0xFFE29B2D),
                            icon: Icons.logout_rounded,
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
        ],
      ),
    );
  }
}

class _HotspotMarker extends StatelessWidget {
  const _HotspotMarker({
    required this.label,
    required this.count,
    required this.accent,
    required this.icon,
  });

  final String label;
  final int count;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
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

class _PassengerFlowStatTile extends StatelessWidget {
  const _PassengerFlowStatTile({
    required this.label,
    required this.value,
    required this.accent,
    this.caption,
  });

  final String label;
  final String value;
  final Color accent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption!),
          ],
        ],
      ),
    );
  }
}

class _PassengerFlowChart extends StatelessWidget {
  const _PassengerFlowChart({required this.series});

  final List<_PassengerFlowDayPoint> series;

  @override
  Widget build(BuildContext context) {
    final maxValue = series.fold<int>(
      1,
      (max, point) => [
        max,
        point.boarded,
        point.unloaded,
      ].reduce((left, right) => left > right ? left : right),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: const [
              _ChartLegend(
                label: 'Boarded',
                color: Color(0xFF0F6A5F),
              ),
              _ChartLegend(
                label: 'Unloaded',
                color: Color(0xFFE29B2D),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in series)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _FlowBar(
                                    value: point.boarded,
                                    maxValue: maxValue,
                                    color: const Color(0xFF0F6A5F),
                                  ),
                                  const SizedBox(width: 6),
                                  _FlowBar(
                                    value: point.unloaded,
                                    maxValue: maxValue,
                                    color: const Color(0xFFE29B2D),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            point.label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
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

class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalized = maxValue <= 0 ? 0.0 : value / maxValue;
    final height = 22 + (normalized * 150);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 16,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _PassengerFlowTopStopsCard extends StatefulWidget {
  const _PassengerFlowTopStopsCard({
    required this.title,
    required this.emptyLabel,
    required this.stops,
    required this.accent,
  });

  final String title;
  final String emptyLabel;
  final List<_PassengerFlowLocation> stops;
  final Color accent;

  @override
  State<_PassengerFlowTopStopsCard> createState() =>
      _PassengerFlowTopStopsCardState();
}

class _PassengerFlowTopStopsCardState extends State<_PassengerFlowTopStopsCard> {
  static const _itemsPerPage = 5;

  int _page = 0;

  @override
  void didUpdateWidget(covariant _PassengerFlowTopStopsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxPage = _pageCount(widget.stops) - 1;
    if (_page > maxPage) {
      _page = maxPage < 0 ? 0 : maxPage;
    }
  }

  int _pageCount(List<_PassengerFlowLocation> stops) {
    if (stops.isEmpty) {
      return 1;
    }
    return ((stops.length - 1) ~/ _itemsPerPage) + 1;
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _pageCount(widget.stops);
    final currentPage = widget.stops.isEmpty
        ? 0
        : _page.clamp(0, totalPages - 1).toInt();
    final start = currentPage * _itemsPerPage;
    final visibleStops = widget.stops
        .skip(start)
        .take(_itemsPerPage)
        .toList(growable: false);
    final end = widget.stops.isEmpty ? 0 : start + visibleStops.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (widget.stops.isEmpty)
            Text(widget.emptyLabel)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < visibleStops.length; index += 1) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: widget.accent.withValues(alpha: 0.12),
                        foregroundColor: widget.accent,
                        child: Text(
                          '${start + index + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          visibleStops[index].label,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${visibleStops[index].count}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  if (index < visibleStops.length - 1) const SizedBox(height: 10),
                ],
                if (widget.stops.length > _itemsPerPage) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Showing ${start + 1}-$end of ${widget.stops.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentPage == 0
                              ? null
                              : () {
                                  setState(() {
                                    _page = currentPage - 1;
                                  });
                                },
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Previous'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentPage >= totalPages - 1
                              ? null
                              : () {
                                  setState(() {
                                    _page = currentPage + 1;
                                  });
                                },
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Page ${currentPage + 1} of $totalPages',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AdminInfoBanner extends StatelessWidget {
  const _AdminInfoBanner({
    required this.message,
    this.isWarning = false,
  });

  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor =
        isWarning ? colorScheme.errorContainer : colorScheme.secondaryContainer;
    final foregroundColor = isWarning
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

IconData _sectionIcon(_AdminWorkspaceSection section) {
  switch (section) {
    case _AdminWorkspaceSection.overview:
      return Icons.space_dashboard_outlined;
    case _AdminWorkspaceSection.drivers:
      return Icons.manage_accounts_outlined;
    case _AdminWorkspaceSection.routeBuilder:
      return Icons.alt_route_outlined;
    case _AdminWorkspaceSection.routes:
      return Icons.place_outlined;
    case _AdminWorkspaceSection.fareSettings:
      return Icons.payments_outlined;
    case _AdminWorkspaceSection.support:
      return Icons.support_agent_rounded;
  }
}

String _sectionLabel(_AdminWorkspaceSection section) {
  switch (section) {
    case _AdminWorkspaceSection.overview:
      return 'Overview';
    case _AdminWorkspaceSection.drivers:
      return 'Drivers';
    case _AdminWorkspaceSection.routeBuilder:
      return 'Route Builder';
    case _AdminWorkspaceSection.routes:
      return 'Routes';
    case _AdminWorkspaceSection.fareSettings:
      return 'Fare Settings';
    case _AdminWorkspaceSection.support:
      return 'Support';
  }
}

Map<String, dynamic> _readDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

int _readCount(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

_PassengerFlowLocation? _parsePassengerFlowLocation(dynamic value) {
  final map = _readDynamicMap(value);
  if (map.isEmpty) {
    return null;
  }
  final location = _parseLatLngMap(map['location']);
  if (location == null) {
    return null;
  }
  return _PassengerFlowLocation(
    label: map['label']?.toString() ?? 'Unknown location',
    count: _readCount(map['count']),
    position: location,
  );
}

List<_PassengerFlowLocation> _parsePassengerFlowLocations(dynamic value) {
  if (value is! List) {
    return const <_PassengerFlowLocation>[];
  }
  return value
      .map((entry) {
        final map = _readDynamicMap(entry);
        final location = _parseLatLngMap(map['location']);
        if (location == null) {
          return null;
        }
        return _PassengerFlowLocation(
          label: map['label']?.toString() ?? 'Unknown location',
          count: _readCount(map['count']),
          position: location,
        );
      })
      .whereType<_PassengerFlowLocation>()
      .toList(growable: false);
}

List<_PassengerFlowDayPoint> _parsePassengerFlowSeries(dynamic value) {
  if (value is! List) {
    return const <_PassengerFlowDayPoint>[];
  }
  return value.map((entry) {
    final map = _readDynamicMap(entry);
    return _PassengerFlowDayPoint(
      label: map['label']?.toString() ?? '-',
      boarded: _readCount(map['boarded']),
      unloaded: _readCount(map['unloaded']),
    );
  }).toList(growable: false);
}

class _PassengerFlowLocation {
  const _PassengerFlowLocation({
    required this.label,
    required this.count,
    required this.position,
  });

  final String label;
  final int count;
  final LatLng position;
}

class _PassengerFlowDayPoint {
  const _PassengerFlowDayPoint({
    required this.label,
    required this.boarded,
    required this.unloaded,
  });

  final String label;
  final int boarded;
  final int unloaded;
}

LatLng? _parseLatLngMap(dynamic value) {
  final map = _readDynamicMap(value);
  final latitude = double.tryParse(map['latitude']?.toString() ?? '');
  final longitude = double.tryParse(map['longitude']?.toString() ?? '');
  if (latitude == null || longitude == null) {
    return null;
  }
  return LatLng(latitude, longitude);
}

LatLng _hotspotMapCenter(List<LatLng> points) {
  if (points.isEmpty) {
    return const LatLng(14.6091, 121.0223);
  }
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;

  for (final point in points.skip(1)) {
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLng) minLng = point.longitude;
    if (point.longitude > maxLng) maxLng = point.longitude;
  }

  return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
}

double _hotspotMapZoom(List<LatLng> points) {
  if (points.length < 2) {
    return 13.2;
  }

  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;

  for (final point in points.skip(1)) {
    if (point.latitude < minLat) minLat = point.latitude;
    if (point.latitude > maxLat) maxLat = point.latitude;
    if (point.longitude < minLng) minLng = point.longitude;
    if (point.longitude > maxLng) maxLng = point.longitude;
  }

  final span = math.max((maxLat - minLat).abs(), (maxLng - minLng).abs());
  if (span < 0.003) return 15.5;
  if (span < 0.008) return 14.5;
  if (span < 0.02) return 13.5;
  if (span < 0.05) return 12.5;
  if (span < 0.12) return 11.5;
  return 10.5;
}
