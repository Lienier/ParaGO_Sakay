import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import 'admin_route_builder_screen.dart';
import 'admin_route_landmark_editor_screen.dart';

class AdminRouteManagementScreen extends StatefulWidget {
  const AdminRouteManagementScreen({
    super.key,
    this.embedded = false,
    this.onChanged,
  });

  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<AdminRouteManagementScreen> createState() =>
      _AdminRouteManagementScreenState();
}

class _AdminRouteManagementScreenState
    extends State<AdminRouteManagementScreen> {
  final _searchCtrl = TextEditingController();
  List<RouteSummaryModel> _routes = [];
  bool _loading = false;
  String? _error;
  String? _busyRouteId;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busyRouteId = null);
      }
    }
  }

  Future<void> _reactivateRoute(RouteSummaryModel route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reactivate route'),
        content: Text(
          'Make ${route.label} available again in active route choices?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reactivate'),
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
        loadingMessage: 'Reactivating route...',
        successMessage: '${route.code} reactivated.',
        action: () => routeService.reactivateRoute(route.id),
        onSuccess: (_) async {
          if (!mounted) return;
          await _load();
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busyRouteId = null);
      }
    }
  }

  Future<void> _openLandmarkEditor(RouteSummaryModel route) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminRouteLandmarkEditorScreen(route: route),
      ),
    );
    if (!mounted) {
      return;
    }
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _openRouteBuilder(RouteSummaryModel route) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdminRouteBuilderScreen(
          initialRoute: route,
        ),
      ),
    );
    if (!mounted || updated != true) {
      return;
    }
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final visibleRoutes = _routes.where((route) {
      final matchesStatus = switch (_statusFilter) {
        'active' => route.status == 'active',
        'inactive' => route.status != 'active',
        'with_landmarks' => route.stopPoints.isNotEmpty,
        _ => true,
      };
      if (!matchesStatus) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack = [
        route.name,
        route.code,
        route.description ?? '',
        for (final stop in route.stopPoints) stop.name,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
    final activeRoutes = visibleRoutes
        .where((route) => route.status == 'active')
        .toList(growable: false);
    final inactiveRoutes = visibleRoutes
        .where((route) => route.status != 'active')
        .toList(growable: false);
    final totalLandmarks = _routes.fold<int>(
      0,
      (sum, route) => sum + route.stopPoints.length,
    );

    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _RouteMetricChip(
                        label: 'Routes',
                        value: _routes.length.toString(),
                      ),
                      _RouteMetricChip(
                        label: 'Active',
                        value: _routes
                            .where((route) => route.status == 'active')
                            .length
                            .toString(),
                      ),
                      _RouteMetricChip(
                        label: 'Inactive',
                        value: _routes
                            .where((route) => route.status != 'active')
                            .length
                            .toString(),
                      ),
                      _RouteMetricChip(
                        label: 'Landmarks',
                        value: totalLandmarks.toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 760;
                      final searchField = TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Search route code, name, or landmark',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                      final filterField = DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filter',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All routes'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active only'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive only'),
                          ),
                          DropdownMenuItem(
                            value: 'with_landmarks',
                            child: Text('With landmarks'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _statusFilter = value ?? 'all');
                        },
                      );

                      if (stacked) {
                        return Column(
                          children: [
                            searchField,
                            const SizedBox(height: 12),
                            filterField,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          SizedBox(width: 220, child: filterField),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
          if (!_loading && visibleRoutes.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _routes.isEmpty
                    ? 'No routes available yet.'
                    : 'No routes match the current search or filter.',
              ),
            ),
            const SizedBox(height: 16),
          ],
          _RouteSection(
            title: 'Active routes',
            emptyMessage: 'No active routes.',
            routes: activeRoutes,
            busyRouteId: _busyRouteId,
            onEditRoute: _openRouteBuilder,
            onEditLandmarks: _openLandmarkEditor,
            onDeactivate: _deactivateRoute,
            onActivate: null,
          ),
          const SizedBox(height: 18),
          _RouteSection(
            title: 'Inactive routes',
            emptyMessage: 'No inactive routes.',
            routes: inactiveRoutes,
            busyRouteId: _busyRouteId,
            onEditRoute: _openRouteBuilder,
            onEditLandmarks: _openLandmarkEditor,
            onDeactivate: null,
            onActivate: _reactivateRoute,
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Routes'),
      ),
      body: body,
    );
  }
}

class _RouteSection extends StatelessWidget {
  const _RouteSection({
    required this.title,
    required this.emptyMessage,
    required this.routes,
    required this.busyRouteId,
    this.onEditRoute,
    required this.onEditLandmarks,
    required this.onDeactivate,
    required this.onActivate,
  });

  final String title;
  final String emptyMessage;
  final List<RouteSummaryModel> routes;
  final String? busyRouteId;
  final ValueChanged<RouteSummaryModel>? onEditRoute;
  final ValueChanged<RouteSummaryModel> onEditLandmarks;
  final ValueChanged<RouteSummaryModel>? onDeactivate;
  final ValueChanged<RouteSummaryModel>? onActivate;

  int _gridColumns(double maxWidth) {
    final columns = (maxWidth / 300).floor();
    return columns.clamp(1, 5);
  }

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
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final columns = _gridColumns(constraints.maxWidth);
                  final cardWidth = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final route in routes)
                        SizedBox(
                          width: cardWidth,
                          child: _RouteRow(
                            route: route,
                            busy: busyRouteId == route.id,
                            onEditRoute: onEditRoute,
                            onEditLandmarks: onEditLandmarks,
                            onDeactivate: onDeactivate,
                            onActivate: onActivate,
                          ),
                        ),
                    ],
                  );
                },
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
    this.onEditRoute,
    required this.onEditLandmarks,
    required this.onDeactivate,
    required this.onActivate,
  });

  final RouteSummaryModel route;
  final bool busy;
  final ValueChanged<RouteSummaryModel>? onEditRoute;
  final ValueChanged<RouteSummaryModel> onEditLandmarks;
  final ValueChanged<RouteSummaryModel>? onDeactivate;
  final ValueChanged<RouteSummaryModel>? onActivate;

  @override
  Widget build(BuildContext context) {
    final compactFilledStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final compactOutlinedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    Widget stopChip(String label, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            route.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${ParagoFormat.statusLabel(route.status)} | '
            '${route.pathPoints.length} path pts | '
            '${route.stopPoints.length} landmarks',
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            ParagoFormat.statusLabel(route.direction),
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _formatFareRule(route.fareConfig),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (route.stopPoints.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stop in route.stopPoints.take(3))
                  stopChip(
                    stop.name,
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                  ),
                if (route.stopPoints.length > 3)
                  stopChip(
                    '+${route.stopPoints.length - 3} more',
                    Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.12),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onEditRoute != null)
                FilledButton.icon(
                  onPressed: () => onEditRoute!(route),
                  style: compactFilledStyle,
                  icon: const Icon(Icons.edit_road_outlined),
                  label: const Text('Edit route'),
                ),
              OutlinedButton.icon(
                onPressed: () => onEditLandmarks(route),
                style: compactOutlinedStyle,
                icon: const Icon(Icons.place_outlined),
                label: const Text('Edit landmarks'),
              ),
              if (onDeactivate != null)
                FilledButton.tonal(
                  onPressed: busy ? null : () => onDeactivate!(route),
                  style: compactFilledStyle,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Deactivate'),
                ),
              if (onActivate != null)
                FilledButton.tonal(
                  onPressed: busy ? null : () => onActivate!(route),
                  style: compactFilledStyle,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reactivate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatRouteFare(double value) {
  final decimals = value == value.truncateToDouble() ? 0 : 2;
  return 'PHP ${value.toStringAsFixed(decimals)}';
}

String _formatFareRule(RouteFareConfig config) {
  return 'Fare: ${_formatRouteFare(config.baseAmount)} for first ${_formatDistanceKm(config.baseDistanceKm)}, then ${_formatRouteFare(config.additionalAmountPerKm)}/km';
}

String _formatDistanceKm(double value) {
  final decimals = value == value.truncateToDouble() ? 0 : 2;
  return '${value.toStringAsFixed(decimals)} km';
}

class _RouteMetricChip extends StatelessWidget {
  const _RouteMetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
