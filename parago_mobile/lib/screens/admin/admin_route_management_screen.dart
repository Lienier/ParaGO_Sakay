import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

class AdminRouteManagementScreen extends StatefulWidget {
  const AdminRouteManagementScreen({super.key});

  @override
  State<AdminRouteManagementScreen> createState() =>
      _AdminRouteManagementScreenState();
}

class _AdminRouteManagementScreenState
    extends State<AdminRouteManagementScreen> {
  List<RouteSummaryModel> _routes = [];
  bool _loading = false;
  String? _error;
  String? _busyRouteId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final routes = await routeService.getRoutes(useCache: false);
      if (!mounted) return;
      setState(() => _routes = routes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deactivateRoute(RouteSummaryModel route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate route'),
        content: Text(
          'Remove ${route.label} from active route choices for now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);

    setState(() => _busyRouteId = route.id);
    try {
      await ActionFeedback.run<void>(
        context: context,
        loadingMessage: 'Deactivating route...',
        successMessage: '${route.code} deactivated.',
        action: () => routeService.deactivateRoute(route.id),
        onSuccess: (_) async {
          if (!mounted) return;
          await _load();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busyRouteId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRoutes = _routes
        .where((route) => route.status == 'active')
        .toList(growable: false);
    final inactiveRoutes = _routes
        .where((route) => route.status != 'active')
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Routes'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            _RouteSection(
              title: 'Active routes',
              emptyMessage: 'No active routes.',
              routes: activeRoutes,
              busyRouteId: _busyRouteId,
              onDeactivate: _deactivateRoute,
            ),
            const SizedBox(height: 18),
            _RouteSection(
              title: 'Inactive routes',
              emptyMessage: 'No inactive routes.',
              routes: inactiveRoutes,
              busyRouteId: _busyRouteId,
              onDeactivate: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSection extends StatelessWidget {
  const _RouteSection({
    required this.title,
    required this.emptyMessage,
    required this.routes,
    required this.busyRouteId,
    required this.onDeactivate,
  });

  final String title;
  final String emptyMessage;
  final List<RouteSummaryModel> routes;
  final String? busyRouteId;
  final ValueChanged<RouteSummaryModel>? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (routes.isEmpty)
              Text(emptyMessage)
            else
              Column(
                children: [
                  for (var index = 0; index < routes.length; index += 1) ...[
                    _RouteRow(
                      route: routes[index],
                      busy: busyRouteId == routes[index].id,
                      onDeactivate: onDeactivate,
                    ),
                    if (index < routes.length - 1) const Divider(),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.route,
    required this.busy,
    required this.onDeactivate,
  });

  final RouteSummaryModel route;
  final bool busy;
  final ValueChanged<RouteSummaryModel>? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            route.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${ParagoFormat.statusLabel(route.status)} | '
            '${route.pathPoints.length} path pts | '
            '${route.waypointPoints.length} waypoints',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            ParagoFormat.statusLabel(route.direction),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onDeactivate != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: busy ? null : () => onDeactivate!(route),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
