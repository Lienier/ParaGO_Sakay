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
    required this.requestReport,
    required this.boardingReport,
    required this.alertReport,
    required this.tripActivityReport,
    required this.routeDemandReport,
    required this.activity,
    required this.routes,
    required this.telemetry,
    required this.lastSyncedAt,
    required this.showingCachedSnapshot,
    required this.onRefresh,
    required this.onSelectDrivers,
    required this.onSelectBuilder,
    required this.onSelectRoutes,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final Map<String, dynamic>? requestReport;
  final Map<String, dynamic>? boardingReport;
  final Map<String, dynamic>? alertReport;
  final Map<String, dynamic>? tripActivityReport;
  final Map<String, dynamic>? routeDemandReport;
  final List<dynamic> activity;
  final List<RouteSummaryModel> routes;
  final List<TelemetryRollup> telemetry;
  final DateTime? lastSyncedAt;
  final bool showingCachedSnapshot;
  final Future<void> Function({bool silent}) onRefresh;
  final VoidCallback onSelectDrivers;
  final VoidCallback onSelectBuilder;
  final VoidCallback onSelectRoutes;

  @override
  Widget build(BuildContext context) {
    final metrics = dashboard ?? const <String, dynamic>{};
    final requestRows = parseStatusReportRows(requestReport?['byStatus']);
    final requestTotal = requestReport?['total']?.toString() ??
        totalStatusCount(requestRows).toString();
    final boardingRows = parseStatusReportRows(boardingReport?['byStatus']);
    final alertRows = parseStatusReportRows(alertReport?['byStatus']);
    final tripRows = parseStatusReportRows(tripActivityReport?['byStatus']);
    final routeDemandRows =
        routeDemandReport?['routes'] as List<dynamic>? ?? const <dynamic>[];

    return RefreshIndicator(
      onRefresh: () => onRefresh(silent: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        children: [
          const _AdminHero(
            title: 'Operations overview',
            subtitle:
                'Monitor active trips, pickup demand, landmark-ready routes, and operations activity from one browser workspace.',
          ),
          if (loading) ...[
            const SizedBox(height: 16),
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
                  ? 'Showing cached operational data from ${ParagoFormat.relative(lastSyncedAt!.toIso8601String())} while the connection stabilizes.'
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
                  label: 'Active alerts',
                  value: metrics['activeAlerts']?.toString() ?? '0',
                  icon: Icons.notifications_active_outlined,
                  accent: const Color(0xFF8A3B5D),
                  caption: 'Digital stop alerts still needing action',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickActionCard(
                icon: Icons.manage_accounts_outlined,
                title: 'Manage drivers',
                description:
                    'Create drivers, assign routes, and schedule trips from one workspace.',
                actionLabel: 'Open drivers',
                onPressed: onSelectDrivers,
              ),
              _QuickActionCard(
                icon: Icons.alt_route_outlined,
                title: 'Build route geometry',
                description:
                    'Map the live route shape and keep the offline snapshot aligned.',
                actionLabel: 'Open builder',
                onPressed: onSelectBuilder,
              ),
              _QuickActionCard(
                icon: Icons.place_outlined,
                title: 'Manage landmarks',
                description:
                    'Update drop-off landmarks and edit per-landmark fares for active routes.',
                actionLabel: 'Open routes',
                onPressed: onSelectRoutes,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Weekly pickup report',
            subtitle: 'Total requests in the last 7 days: $requestTotal',
            child: requestRows.isEmpty
                ? const Text('No request data available yet.')
                : _buildReportWrap(context, requestRows),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final cards = <Widget>[
                _MiniReportCard(
                  title: 'Boarding report',
                  subtitle:
                      'Ride-session states this week (${totalStatusCount(boardingRows)} total)',
                  body: boardingRows.isEmpty
                      ? const Text('No boarding activity yet.')
                      : _buildReportWrap(context, boardingRows),
                ),
                _MiniReportCard(
                  title: 'Alert report',
                  subtitle:
                      'Passenger stop-alert outcomes (${totalStatusCount(alertRows)} total)',
                  body: alertRows.isEmpty
                      ? const Text('No stop alerts recorded yet.')
                      : _buildReportWrap(context, alertRows),
                ),
                _MiniReportCard(
                  title: 'Trip activity',
                  subtitle:
                      'Trip lifecycle states (${totalStatusCount(tripRows)} total)',
                  body: tripRows.isEmpty
                      ? const Text('No trip activity recorded yet.')
                      : _buildReportWrap(context, tripRows),
                ),
              ];

              if (compact) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 18),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < cards.length; index += 1) ...[
                    Expanded(child: cards[index]),
                    if (index < cards.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Route demand analytics',
            subtitle:
                'Top-demand routes ranked by pickup requests to support dispatch and coverage decisions.',
            child: routeDemandRows.isEmpty
                ? const Text('No route-demand data available yet.')
                : Column(
                    children: routeDemandRows.take(5).map((entry) {
                      final item = _readDynamicMap(entry);
                      final routeId = item['_id']?.toString() ?? '';
                      final totalRequests =
                          item['totalRequests']?.toString() ?? '0';
                      final route = _findRouteById(routes, routeId);
                      final label = route?.label.isNotEmpty == true
                          ? route!.label
                          : 'Route $routeId';
                      final subtitle = route == null
                          ? 'Route metadata is unavailable in this snapshot.'
                          : '${route.stopPoints.length} landmarks · ${ParagoFormat.statusLabel(route.status)}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F8F5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.10),
                                foregroundColor:
                                    Theme.of(context).colorScheme.primary,
                                child: Text(
                                  '${routeDemandRows.indexOf(entry) + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subtitle),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '$totalRequests requests',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Managed routes',
            subtitle:
                '${routes.length} route${routes.length == 1 ? '' : 's'} currently available',
            child: routes.isEmpty
                ? const Text('No routes available yet.')
                : Column(
                    children: routes.take(5).map((route) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${ParagoFormat.statusLabel(route.status)} | ${route.stopPoints.length} landmarks',
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Client performance snapshot',
            subtitle:
                'Recent console request timings help document responsiveness during evaluation.',
            child: telemetry.isEmpty
                ? const Text(
                    'Telemetry will appear after the first API requests complete.',
                  )
                : Column(
                    children: telemetry.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F8F5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${entry.requestCount} requests · ${entry.failureCount} failures · ${entry.staleHits} cache fallbacks',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'avg ${entry.averageDurationMs} ms',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('max ${entry.maxDurationMs} ms'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Recent activity',
            subtitle: 'Latest operations and system events',
            child: activity.isEmpty
                ? const Text('No activity logs recorded yet.')
                : Column(
                    children: activity.take(8).map((entry) {
                      final item = _readDynamicMap(entry);
                      final action = item['action']?.toString() ??
                          item['event']?.toString() ??
                          'Activity';
                      final actor = item['actorName']?.toString() ??
                          item['actorId']?.toString() ??
                          'System';
                      final createdAt = item['createdAt']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withValues(alpha: 0.16),
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.history_toggle_off),
                          ),
                          title: Text(action),
                          subtitle: Text(
                            '$actor | ${ParagoFormat.relative(createdAt)}',
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportWrap(
    BuildContext context,
    List<StatusReportMetric> rows,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: rows.map((row) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            '${ParagoFormat.statusLabel(row.status)} | ${row.count}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F6A5F),
            Color(0xFF8A3B5D),
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
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Dedicated operations console',
              style: TextStyle(
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
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.45,
                ),
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(description),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.arrow_forward_outlined),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniReportCard extends StatelessWidget {
  const _MiniReportCard({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 14),
            body,
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

RouteSummaryModel? _findRouteById(
  List<RouteSummaryModel> routes,
  String routeId,
) {
  for (final route in routes) {
    if (route.id == routeId) {
      return route;
    }
  }
  return null;
}
