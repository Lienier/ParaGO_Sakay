part of 'admin_home_screen.dart';

List<dynamic> _readDynamicList(dynamic value) =>
    value is List ? value : const [];

class _AdminOperationsPage extends StatelessWidget {
  const _AdminOperationsPage(
      {required this.section,
      required this.dashboard,
      required this.board,
      required this.report,
      required this.errors,
      required this.times,
      required this.loading,
      required this.onRetry,
      required this.onSelect,
      required this.route,
      required this.onRoute,
      required this.reportRange,
      required this.onReportRange,
      required this.onReorder,
      required this.onSkip,
      required this.onDepart});
  final _AdminWorkspaceSection section;
  final Map<String, dynamic>? dashboard, board, report;
  final Map<String, String> errors;
  final Map<String, DateTime> times;
  final Set<String> loading;
  final Future<void> Function(String) onRetry;
  final void Function(_AdminWorkspaceSection) onSelect;
  final String? route;
  final void Function(String?) onRoute;
  final DateTimeRange reportRange;
  final VoidCallback onReportRange;
  final Future<void> Function(String, String) onReorder, onDepart;
  final Future<void> Function(String, bool) onSkip;

  Widget _state(String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (loading.contains(key)) const LinearProgressIndicator(minHeight: 2),
        if (errors.containsKey(key))
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(
                times.containsKey(key)
                    ? 'Refresh failed. Showing previous data.'
                    : 'This section is unavailable.',
                style: const TextStyle(color: AppColors.warning)),
            TextButton(
                onPressed: () => onRetry(key), child: const Text('Retry')),
          ]),
        if (times[key] != null)
          Text(
              'Last successful update: ${times[key]!.toLocal().toString().split('.')[0]}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
      ]));

  List<dynamic> get _queue => _readDynamicList(board?['terminalQueue']);
  String _routeKey(dynamic trip) {
    final r = _readDynamicMap(_readDynamicMap(trip)['routeId']);
    return r['_id']?.toString() ?? r['name']?.toString() ?? 'unassigned';
  }

  Widget _metrics(BuildContext context) =>
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 900
            ? 4
            : box.maxWidth >= 500
                ? 2
                : 1;
        final entries = {
          'Active trips': 'activeTrips',
          'Pending pickups': 'pendingRequests',
          'Onboard passengers': 'onboardRides',
          'Terminal trips': 'terminalQueueTrips'
        };
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final entry in entries.entries)
            SizedBox(
                width: (box.maxWidth - 12 * (columns - 1)) / columns,
                child: MetricCard(
                    label: entry.key,
                    value: dashboard?[entry.value]?.toString() ??
                        (loading.contains('activity')
                            ? 'Loading'
                            : 'Unavailable'),
                    icon: Icons.circle,
                    caption: dashboard == null
                        ? (loading.contains('activity')
                            ? 'Fetching current activity'
                            : 'No activity data available')
                        : errors.containsKey('activity')
                            ? 'Last available snapshot'
                            : 'Current activity',
                    accent: AppColors.primary))
        ]);
      });

  Widget _overview(BuildContext context) {
    final warnings = _queue
        .where((t) =>
            _readDynamicMap(
                _readDynamicMap(t)['terminalSummary'])['gpsWarning'] ==
            true)
        .length;
    final pending = dashboard?['pendingRequests'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OperationsPanel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 38, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Needs attention',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: const Color(0xFF142C46))),
                const Text('Review pickups and terminal location warnings.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ])),
        ]),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1)),
        if (pending == null)
          const Text('Pickup status is not available yet.')
        else
          Text('$pending pickup requests awaiting resolution'),
        if (board == null)
          const Text('Terminal location status is not available yet.')
        else
          Text('$warnings terminal jeeps with old or missing GPS'),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => onSelect(_AdminWorkspaceSection.dispatch),
            child: const Text('Review dispatch')),
      ])),
      const SizedBox(height: 24),
      Text('Current activity', style: Theme.of(context).textTheme.titleLarge),
      _state('activity'),
      _metrics(context),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(
            child: Text('Terminal activity',
                style: Theme.of(context).textTheme.titleLarge)),
        TextButton(
            onPressed: () => onSelect(_AdminWorkspaceSection.dispatch),
            child: const Text('Open dispatch'))
      ]),
      _state('dispatch'),
      if (board != null)
        OperationsPanel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (_queue.isEmpty)
                const AppEmptyState(
                    title: 'No terminal trips',
                    message: 'Checked successfully. The queue is empty.'),
              for (final trip in _queue.take(3))
                ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(_dispatchTripLabel(trip)),
                    subtitle: Text(
                        'Position ${trip['terminalQueueNumber'] ?? '-'} - ${trip['terminalQueueStatus'] ?? 'Unknown'}'),
                    trailing: TextButton(
                        onPressed: () =>
                            onSelect(_AdminWorkspaceSection.dispatch),
                        child: const Text('View'))),
            ])),
    ]);
  }

  Widget _dispatch(BuildContext context) {
    final allTrips = [..._queue, ..._readDynamicList(board?['routeDrivers'])];
    final routes = <String, String>{
      for (final t in allTrips)
        _routeKey(t): _readDynamicMap(_readDynamicMap(t)['routeId'])['name']
                ?.toString() ??
            'Unassigned route'
    };
    final selected = routes.containsKey(route) ? route : null;
    final trips = _queue
        .where((t) => selected == null || _routeKey(t) == selected)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OperationsPanel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
            key: ValueKey(selected),
            initialValue: selected ?? '',
            decoration: const InputDecoration(labelText: 'Route / direction'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All routes')),
              for (final r in routes.entries)
                DropdownMenuItem(value: r.key, child: Text(r.value))
            ],
            onChanged: (value) => onRoute(value == '' ? null : value)),
        _state('dispatch'),
      ])),
      if (board != null) ...[
        for (final status in ['loading', 'waiting', 'skipped']) ...[
          const SizedBox(height: 20),
          Row(children: [
            Text(ParagoFormat.statusLabel(status),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: const Color(0xFF142C46))),
            const SizedBox(width: 10),
            Text(
                '${trips.where((t) => t['terminalQueueStatus'] == status).length}',
                style: const TextStyle(color: AppColors.textSecondary)),
          ]),
          Text(
              status == 'loading'
                  ? 'Boarding now · departure requires confirmation'
                  : status == 'waiting'
                      ? 'Next in line · ordered separately for each route'
                      : 'Out of rotation · restore to the back of the queue',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          if (!trips.any((t) => t['terminalQueueStatus'] == status))
            OperationsPanel(
                child: Text('No $status jeeps.',
                    style: const TextStyle(color: AppColors.textSecondary))),
          for (final trip
              in trips.where((t) => t['terminalQueueStatus'] == status))
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TerminalDispatchRow(
                  trip: _readDynamicMap(trip),
                  actions: errors.containsKey('dispatch') ||
                          loading.contains('dispatch')
                      ? const []
                      : _terminalQueueActions(trip,
                          index: trips
                              .where((t) =>
                                  t['terminalQueueStatus'] == 'waiting' &&
                                  _routeKey(t) == _routeKey(trip))
                              .toList()
                              .indexOf(trip),
                          total: trips
                              .where((t) =>
                                  t['terminalQueueStatus'] == 'waiting' &&
                                  _routeKey(t) == _routeKey(trip))
                              .length,
                          onReorder: onReorder,
                          onSkippedChanged: onSkip,
                          onStatusChanged: onDepart),
                )),
        ],
        const SizedBox(height: 28),
        Text('On the road', style: Theme.of(context).textTheme.titleLarge),
        for (final trip in _readDynamicList(board?['routeDrivers'])
            .where((t) => selected == null || _routeKey(t) == selected))
          ListTile(
              title: Text(_dispatchTripLabel(trip)),
              subtitle: Text(
                  'Departed terminal · Route operation · ${trip['occupancyCount'] ?? '-'} onboard')),
      ],
    ]);
  }

  Widget _reports(BuildContext context) {
    final summary = _readDynamicMap(report?['summary']);
    final daily = _parsePassengerFlowSeries(report?['daily']);
    final boarding =
        _parsePassengerFlowLocations(report?['topBoardingLocations']);
    final unloading =
        _parsePassengerFlowLocations(report?['topUnloadLocations']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            Text(
                '${reportRange.start.toString().split(' ')[0]} to ${reportRange.end.toString().split(' ')[0]}'),
            OutlinedButton(
                onPressed: onReportRange, child: const Text('Change dates')),
            const Text('Maximum 366 days'),
          ]),
      _state('reports'),
      if (report != null) ...[
        Wrap(spacing: 24, runSpacing: 12, children: [
          _PassengerFlowStatTile(
              label: 'Total boarded',
              value: summary['totalBoarded']?.toString() ?? 'Unavailable',
              accent: AppColors.primary),
          _PassengerFlowStatTile(
              label: 'Total unloaded',
              value: summary['totalUnloaded']?.toString() ?? 'Unavailable',
              accent: AppColors.textSecondary),
        ]),
        const SizedBox(height: 24),
        if (daily.isEmpty)
          const Text('No passenger movement recorded in this period.')
        else
          _PassengerFlowChart(series: daily),
        const SizedBox(height: 24),
        if (boarding.isNotEmpty || unloading.isNotEmpty)
          _PassengerFlowHotspotMap(
              boardingLocations: boarding, unloadLocations: unloading),
        const SizedBox(height: 24),
        _PassengerFlowTopStopsCard(
            title: 'Most boarded locations',
            emptyLabel: 'No boarding locations in this period.',
            stops: boarding,
            accent: AppColors.primary),
        const SizedBox(height: 16),
        _PassengerFlowTopStopsCard(
            title: 'Most unloaded locations',
            emptyLabel: 'No unload locations in this period.',
            stops: unloading,
            accent: AppColors.textSecondary),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xFFEDF1F5),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        AppPageHeader(
            title: section == _AdminWorkspaceSection.overview
                ? 'Operations overview'
                : _sectionLabel(section),
            subtitle: section == _AdminWorkspaceSection.overview
                ? 'What needs your attention today.'
                : section == _AdminWorkspaceSection.dispatch
                    ? 'Manage loading, queue order, and departures.'
                    : 'Passenger movement over your selected period.'),
        const SizedBox(height: 24),
        if (section == _AdminWorkspaceSection.overview)
          _overview(context)
        else if (section == _AdminWorkspaceSection.dispatch)
          _dispatch(context)
        else
          _reports(context),
      ]));
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
  required Future<void> Function(String tripId, bool skipped) onSkippedChanged,
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
  final waiting = status == 'waiting';

  return [
    IconButton.outlined(
      onPressed: !waiting || index <= 0 ? null : () => onReorder(tripId, 'up'),
      tooltip: 'Move up',
      icon: const Icon(Icons.keyboard_arrow_up),
    ),
    IconButton.outlined(
      onPressed: !waiting || index >= total - 1
          ? null
          : () => onReorder(tripId, 'down'),
      tooltip: 'Move down',
      icon: const Icon(Icons.keyboard_arrow_down),
    ),
    TextButton(
        onPressed: () => onSkippedChanged(tripId, !skipped),
        child: Text(skipped ? 'Restore' : 'Skip')),
    TextButton(
        onPressed: loading ? () => onStatusChanged(tripId, 'departed') : null,
        child: const Text('Depart terminal')),
  ];
}

class _TerminalDispatchRow extends StatelessWidget {
  const _TerminalDispatchRow({required this.trip, required this.actions});
  final Map<String, dynamic> trip;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final summary = _readDynamicMap(trip['terminalSummary']);
    final driver = _readDynamicMap(_readDynamicMap(trip['driverId'])['userId']);
    final vehicle = _readDynamicMap(trip['jeepneyId']);
    final route = _readDynamicMap(trip['routeId']);
    Widget field(String label, String value, {Color? color}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color ?? const Color(0xFF142C46))),
        ]);
    final identity =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(vehicle['plateNumber']?.toString() ?? 'Jeep unavailable',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF142C46))),
      const SizedBox(height: 4),
      Text(driver['fullName']?.toString() ?? 'Driver unavailable',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ]);
    final seats = Wrap(spacing: 18, runSpacing: 10, children: [
      field('Onboard',
          '${summary['onboardSeats'] ?? trip['occupancyCount'] ?? '—'}'),
      field('Reserved', '${summary['reservedSeats'] ?? '—'}'),
      if (summary['reservationPartySizes'] is List && (summary['reservationPartySizes'] as List).isNotEmpty)
        field('People per booking', (summary['reservationPartySizes'] as List).join(' + ')),
      field('Free', '${summary['availableSeats'] ?? '—'}',
          color: AppColors.primary),
    ]);
    final gps = field(
        'GPS',
        summary.isEmpty
            ? 'Unavailable'
            : summary['gpsWarning'] == true
                ? 'Old / missing'
                : 'Recent',
        color: summary['gpsWarning'] == true
            ? AppColors.warning
            : AppColors.textPrimary);
    final routeField = field('Route / terminal',
        '${route['name'] ?? 'Unassigned route'}\n${_dispatchTerminalLabel(trip)}');
    return OperationsPanel(
        child: LayoutBuilder(
            builder: (context, constraints) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (constraints.maxWidth >= 780)
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 62,
                                  child: field('Position',
                                      '${summary['queuePosition'] ?? trip['terminalQueueNumber'] ?? '—'}')),
                              Expanded(flex: 3, child: identity),
                              const SizedBox(width: 16),
                              Expanded(flex: 3, child: routeField),
                              const SizedBox(width: 16),
                              Expanded(flex: 3, child: seats),
                              SizedBox(width: 110, child: gps),
                            ])
                      else ...[
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: identity),
                              const SizedBox(width: 12),
                              field('Position',
                                  '${summary['queuePosition'] ?? trip['terminalQueueNumber'] ?? '—'}')
                            ]),
                        const SizedBox(height: 16),
                        routeField,
                        const SizedBox(height: 16),
                        Wrap(
                            spacing: 28,
                            runSpacing: 16,
                            children: [seats, gps]),
                      ],
                      if (trip['terminalQueueStatus'] == 'loading')
                        TerminalLoadingClock(
                            key: ValueKey(trip['_id']), summary: summary),
                      if (actions.isNotEmpty) ...[
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1)),
                        Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: actions),
                      ],
                    ])));
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EB)),
        borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EB)),
        borderRadius: BorderRadius.circular(8),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EB)),
        borderRadius: BorderRadius.circular(8),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth =
                    math.max(constraints.maxWidth, series.length * 72.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final point in series)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _FlowBar(
                                            value: point.boarded,
                                            maxValue: maxValue,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          _FlowBar(
                                            value: point.unloaded,
                                            maxValue: maxValue,
                                            color: AppColors.warning,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    point.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
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

class _PassengerFlowTopStopsCardState
    extends State<_PassengerFlowTopStopsCard> {
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
    final currentPage =
        widget.stops.isEmpty ? 0 : _page.clamp(0, totalPages - 1).toInt();
    final start = currentPage * _itemsPerPage;
    final visibleStops =
        widget.stops.skip(start).take(_itemsPerPage).toList(growable: false);
    final end = widget.stops.isEmpty ? 0 : start + visibleStops.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EB)),
        borderRadius: BorderRadius.circular(8),
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
                for (var index = 0;
                    index < visibleStops.length;
                    index += 1) ...[
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
                  if (index < visibleStops.length - 1)
                    const SizedBox(height: 10),
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

String _sectionLabel(_AdminWorkspaceSection section) {
  switch (section) {
    case _AdminWorkspaceSection.overview:
      return 'Overview';
    case _AdminWorkspaceSection.dispatch:
      return 'Terminal dispatch';
    case _AdminWorkspaceSection.reports:
      return 'Reports';
    case _AdminWorkspaceSection.drivers:
      return 'Drivers';
    case _AdminWorkspaceSection.routeBuilder:
      return 'Route Builder';
    case _AdminWorkspaceSection.routes:
      return 'Routes';
    case _AdminWorkspaceSection.fareSettings:
      return 'Fare Settings';
    case _AdminWorkspaceSection.announcements:
      return 'Announcements';
    case _AdminWorkspaceSection.numberCoding:
      return 'Number Coding';
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
