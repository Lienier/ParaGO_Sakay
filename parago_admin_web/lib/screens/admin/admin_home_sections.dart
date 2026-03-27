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
    required this.activity,
    required this.routes,
    required this.onRefresh,
    required this.onSelectDrivers,
    required this.onSelectBuilder,
    required this.onSelectRoutes,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final Map<String, dynamic>? requestReport;
  final List<dynamic> activity;
  final List<RouteSummaryModel> routes;
  final Future<void> Function({bool silent}) onRefresh;
  final VoidCallback onSelectDrivers;
  final VoidCallback onSelectBuilder;
  final VoidCallback onSelectRoutes;

  @override
  Widget build(BuildContext context) {
    final metrics = dashboard ?? const <String, dynamic>{};
    final requestRows = requestReport?['byStatus'] as List<dynamic>? ?? [];
    final requestTotal = requestReport?['total']?.toString() ?? '0';

    return RefreshIndicator(
      onRefresh: () => onRefresh(silent: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        children: [
          _AdminHero(
            title: 'Operations overview',
            subtitle:
                'Monitor active trips, pickup demand, landmark-ready routes, and admin activity from one browser workspace.',
          ),
          if (loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            _AdminInfoBanner(message: error!),
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
                    'Create drivers, assign routes, and schedule trips from one admin panel.',
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
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: requestRows.map((row) {
                      final data = _readDynamicMap(row);
                      final status = data['_id']?.toString() ?? 'unknown';
                      final count = data['count']?.toString() ?? '0';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          '${ParagoFormat.statusLabel(status)} | $count',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
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
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Recent activity',
            subtitle: 'Latest admin and system events',
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
                    }).toList(),
                  ),
          ),
        ],
      ),
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
              'Dedicated admin web console',
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
  const _AdminInfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
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
