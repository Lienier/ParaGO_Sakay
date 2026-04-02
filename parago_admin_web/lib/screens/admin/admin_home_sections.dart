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
    required this.lastSyncedAt,
    required this.showingCachedSnapshot,
    required this.onRefresh,
  });

  final bool loading;
  final String? error;
  final Map<String, dynamic>? dashboard;
  final Map<String, dynamic>? passengerFlowReport;
  final DateTime? lastSyncedAt;
  final bool showingCachedSnapshot;
  final Future<void> Function({bool silent}) onRefresh;

  @override
  Widget build(BuildContext context) {
    final metrics = dashboard ?? const <String, dynamic>{};
    final passengerFlow = passengerFlowReport ?? const <String, dynamic>{};
    final summary = _readDynamicMap(passengerFlow['summary']);
    final dailyFlow = _parsePassengerFlowSeries(passengerFlow['daily']);
    final topBoardingStops = _parsePassengerFlowStops(
      passengerFlow['topBoardingStops'],
    );
    final topUnloadStops = _parsePassengerFlowStops(
      passengerFlow['topUnloadStops'],
    );
    final topBoardingStop = _parsePassengerFlowStop(summary['topBoardingStop']);
    final topUnloadStop = _parsePassengerFlowStop(summary['topUnloadStop']);

    return RefreshIndicator(
      onRefresh: () => onRefresh(silent: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        children: [
          const _AdminHero(
            title: 'Operations overview',
            subtitle:
                'See the live trip counts, pending pickups, onboard rides, and a focused passenger flow report from one place.',
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
            ],
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Passenger boarding and unload report',
            subtitle:
                'Shows where passengers most often get on and unload, plus the day-by-day boarding and unload trend for the last 7 days.',
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
                      label: 'Top boarding stop',
                      value: topBoardingStop?.label ?? 'No data yet',
                      caption: topBoardingStop == null
                          ? null
                          : '${topBoardingStop.count} passengers',
                      accent: const Color(0xFF2157A5),
                    ),
                    _PassengerFlowStatTile(
                      label: 'Top unload stop',
                      value: topUnloadStop?.label ?? 'No data yet',
                      caption: topUnloadStop == null
                          ? null
                          : '${topUnloadStop.count} passengers',
                      accent: const Color(0xFF8A3B5D),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (dailyFlow.isEmpty)
                  const Text('No passenger flow data available yet.')
                else
                  _PassengerFlowChart(series: dailyFlow),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 900;
                    final boardingCard = _PassengerFlowTopStopsCard(
                      title: 'Most boarded stops',
                      emptyLabel: 'No boarding-stop data yet.',
                      stops: topBoardingStops,
                      accent: const Color(0xFF0F6A5F),
                    );
                    final unloadCard = _PassengerFlowTopStopsCard(
                      title: 'Most unloaded stops',
                      emptyLabel: 'No unload-stop data yet.',
                      stops: topUnloadStops,
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

class _PassengerFlowTopStopsCard extends StatelessWidget {
  const _PassengerFlowTopStopsCard({
    required this.title,
    required this.emptyLabel,
    required this.stops,
    required this.accent,
  });

  final String title;
  final String emptyLabel;
  final List<_PassengerFlowStop> stops;
  final Color accent;

  @override
  Widget build(BuildContext context) {
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
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (stops.isEmpty)
            Text(emptyLabel)
          else
            Column(
              children: [
                for (var index = 0; index < stops.length; index += 1) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: accent.withValues(alpha: 0.12),
                        foregroundColor: accent,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          stops[index].label,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${stops[index].count}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  if (index < stops.length - 1) const SizedBox(height: 10),
                ],
              ],
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

int _readCount(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

_PassengerFlowStop? _parsePassengerFlowStop(dynamic value) {
  final map = _readDynamicMap(value);
  if (map.isEmpty) {
    return null;
  }
  return _PassengerFlowStop(
    label: map['label']?.toString() ?? 'Unknown stop',
    count: _readCount(map['count']),
  );
}

List<_PassengerFlowStop> _parsePassengerFlowStops(dynamic value) {
  if (value is! List) {
    return const <_PassengerFlowStop>[];
  }
  return value.map((entry) {
    final map = _readDynamicMap(entry);
    return _PassengerFlowStop(
      label: map['label']?.toString() ?? 'Unknown stop',
      count: _readCount(map['count']),
    );
  }).toList(growable: false);
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

class _PassengerFlowStop {
  const _PassengerFlowStop({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;
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
