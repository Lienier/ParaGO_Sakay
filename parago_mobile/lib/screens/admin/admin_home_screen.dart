import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/admin_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import 'admin_driver_management_screen.dart';
import 'admin_route_management_screen.dart';
import 'admin_route_builder_screen.dart';
import '../../widgets/metric_card.dart';

part 'admin_home_sections.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _requestReport;
  List<dynamic> _activity = [];
  List<RouteSummaryModel> _routes = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    setState(() => _loading = true);

    try {
      final now = DateTime.now().toUtc();
      final from = now.subtract(const Duration(days: 7));
      final results = await Future.wait<dynamic>([
        admin.dashboard(),
        admin.recentActivity(),
        admin.reportRequests(
          fromIso: from.toIso8601String(),
          toIso: now.toIso8601String(),
        ),
        routeService.getRoutes(),
      ]);

      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Map<String, dynamic>;
        _activity = results[1] as List<dynamic>;
        _requestReport = results[2] as Map<String, dynamic>;
        _routes = results[3] as List<RouteSummaryModel>;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final metrics = _dashboard ?? <String, dynamic>{};
    final requestRows = (_requestReport?['byStatus'] as List<dynamic>? ?? []);
    final requestTotal = _requestReport?['total']?.toString() ?? '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminDriverManagementScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.alt_route),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => const AdminRouteBuilderScreen(),
                ),
              );
              if (saved == true && mounted) {
                _load();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminRouteManagementScreen(),
                ),
              );
              if (mounted) {
                _load();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => session.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _AdminHero(name: session.user?.fullName ?? 'Administrator'),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _AdminInfoBanner(message: _error!),
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
                      label: 'Active trips',
                      value: metrics['activeTrips']?.toString() ?? '0',
                      icon: Icons.route_outlined,
                      accent: const Color(0xFF0F6A5F),
                      caption: 'Trips currently operating across the system',
                    ),
                    MetricCard(
                      label: 'Pending pickups',
                      value: metrics['pendingRequests']?.toString() ?? '0',
                      icon: Icons.near_me_outlined,
                      accent: const Color(0xFFE29B2D),
                      caption: 'Current pickup requests still in progress',
                    ),
                    MetricCard(
                      label: 'Onboard rides',
                      value: metrics['onboardRides']?.toString() ?? '0',
                      icon: Icons.groups_2_outlined,
                      accent: const Color(0xFF2157A5),
                      caption: 'Ride sessions with passengers already onboard',
                    ),
                    MetricCard(
                      label: 'Active alerts',
                      value: metrics['activeAlerts']?.toString() ?? '0',
                      icon: Icons.notifications_active_outlined,
                      accent: const Color(0xFF8A3B5D),
                      caption:
                          'Digital stop alerts still needing action or review',
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
                    Text('Weekly pickup report',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Total requests in the last 7 days: $requestTotal'),
                    const SizedBox(height: 16),
                    if (requestRows.isEmpty)
                      const Text('No request data available yet.')
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: requestRows.map((row) {
                          final data = row as Map<String, dynamic>;
                          final status = data['_id']?.toString() ?? 'unknown';
                          final count = data['count']?.toString() ?? '0';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              '${ParagoFormat.statusLabel(status)} · $count',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          );
                        }).toList(),
                      ),
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
                    Text('Managed routes',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const AdminRouteManagementScreen(),
                            ),
                          );
                          if (mounted) {
                            _load();
                          }
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Manage routes'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_routes.isEmpty)
                      const Text('No routes available.')
                    else
                      Column(
                        children: _routes.take(6).map((route) {
                          return Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(route.label),
                                subtitle: Text(
                                  '${ParagoFormat.statusLabel(route.status)} · ${route.stopsCount} stops',
                                ),
                                trailing: Text(
                                  ParagoFormat.statusLabel(route.direction),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const Divider(),
                            ],
                          );
                        }).toList(),
                      ),
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
                    Text('Recent activity',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_activity.isEmpty)
                      const Text('No activity logs recorded yet.')
                    else
                      Column(
                        children: _activity.take(8).map((entry) {
                          final item = entry as Map<String, dynamic>;
                          final action = item['action']?.toString() ??
                              item['event']?.toString() ??
                              'Activity';
                          final actor = item['actorName']?.toString() ??
                              item['actorId']?.toString() ??
                              'System';
                          final createdAt = item['createdAt']?.toString();
                          return Column(
                            children: [
                              ListTile(
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
                                  '$actor · ${ParagoFormat.relative(createdAt)}',
                                ),
                              ),
                              const Divider(),
                            ],
                          );
                        }).toList(),
                      ),
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
                    Text('System guardrails',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    const Text(
                      'ParaGO! remains a transportation support system, not a ride-hailing or seat reservation platform. Boarding stays QR-free and depends on trip activity, request history, and validation rules.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh admin snapshot'),
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
