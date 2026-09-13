import '../../widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  Future<void> _openTerminalSettings(RouteSummaryModel route) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _TerminalSettingsDialog(route: route),
    );
    if (payload == null || !mounted) {
      return;
    }

    final session = context.read<SessionController>();
    final routeService = RouteService(session.apiClient);
    setState(() => _busyRouteId = route.id);
    try {
      await ActionFeedback.run<void>(
        context: context,
        loadingMessage: 'Saving terminal settings...',
        successMessage: payload['enabled'] == false
            ? 'Terminal queue disabled for ${route.code}.'
            : 'Terminal settings saved for ${route.code}.',
        action: () => routeService.updateRouteTerminal(route.id, payload),
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
        padding: const EdgeInsets.all(24),
        children: [
          OperationsCard(
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
                borderRadius: BorderRadius.circular(8),
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
            onEditTerminal: _openTerminalSettings,
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
            onEditTerminal: _openTerminalSettings,
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
    required this.onEditTerminal,
    required this.onDeactivate,
    required this.onActivate,
  });

  final String title;
  final String emptyMessage;
  final List<RouteSummaryModel> routes;
  final String? busyRouteId;
  final ValueChanged<RouteSummaryModel>? onEditRoute;
  final ValueChanged<RouteSummaryModel> onEditLandmarks;
  final ValueChanged<RouteSummaryModel> onEditTerminal;
  final ValueChanged<RouteSummaryModel>? onDeactivate;
  final ValueChanged<RouteSummaryModel>? onActivate;

  @override
  Widget build(BuildContext context) {
    return OperationsCard(
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
                  builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowHeight: 44,
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 64,
                              horizontalMargin: 12,
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(label: Text('Code')),
                                DataColumn(label: Text('Route')),
                                DataColumn(label: Text('Direction')),
                                DataColumn(label: Text('Stops'), numeric: true),
                                DataColumn(label: Text('Actions'))
                              ],
                              rows: [
                                for (final route in routes)
                                  DataRow(cells: [
                                    DataCell(Text(route.code)),
                                    DataCell(Text(route.name)),
                                    DataCell(Text(route.direction)),
                                    DataCell(Text('${route.stopsCount}')),
                                    DataCell(TextButton(
                                        onPressed: busyRouteId == route.id
                                            ? null
                                            : () => showDialog<void>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                            'Route details'),
                                                        content: SizedBox(
                                                            width: 560,
                                                            child: SingleChildScrollView(
                                                                child: _RouteRow(
                                                              route: route,
                                                              busy:
                                                                  busyRouteId ==
                                                                      route.id,
                                                              onEditRoute:
                                                                  onEditRoute ==
                                                                          null
                                                                      ? null
                                                                      : (r) {
                                                                          Navigator.pop(
                                                                              ctx);
                                                                          onEditRoute!(
                                                                              r);
                                                                        },
                                                              onEditLandmarks:
                                                                  (r) {
                                                                Navigator.pop(
                                                                    ctx);
                                                                onEditLandmarks(
                                                                    r);
                                                              },
                                                              onEditTerminal:
                                                                  (r) {
                                                                Navigator.pop(
                                                                    ctx);
                                                                onEditTerminal(
                                                                    r);
                                                              },
                                                              onDeactivate:
                                                                  onDeactivate ==
                                                                          null
                                                                      ? null
                                                                      : (r) {
                                                                          Navigator.pop(
                                                                              ctx);
                                                                          onDeactivate!(
                                                                              r);
                                                                        },
                                                              onActivate:
                                                                  onActivate ==
                                                                          null
                                                                      ? null
                                                                      : (r) {
                                                                          Navigator.pop(
                                                                              ctx);
                                                                          onActivate!(
                                                                              r);
                                                                        },
                                                            ))),
                                                        actions: [
                                                          TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx),
                                                              child: const Text(
                                                                  'Close'))
                                                        ])),
                                        child: const Text('View details'))),
                                  ])
                              ],
                            )),
                      )),
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
    required this.onEditTerminal,
    required this.onDeactivate,
    required this.onActivate,
  });

  final RouteSummaryModel route;
  final bool busy;
  final ValueChanged<RouteSummaryModel>? onEditRoute;
  final ValueChanged<RouteSummaryModel> onEditLandmarks;
  final ValueChanged<RouteSummaryModel> onEditTerminal;
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
    }

    final terminal = route.effectiveTerminal;
    final terminalLabel = terminal == null
        ? 'Terminal not configured'
        : '${terminal.label} (${terminal.radiusMeters} m)';
    final terminalSource = terminal == null
        ? 'Terminal queue unavailable'
        : terminal.isConfigured
            ? 'Configured terminal'
            : 'Fallback from first landmark';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .tertiary
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  terminal == null
                      ? Icons.location_off_outlined
                      : Icons.storefront_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        terminalLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        terminalSource,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
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
                FilledButton(
                  onPressed: () => onEditRoute!(route),
                  style: compactFilledStyle,
                  child: const Text('Edit route'),
                ),
              OutlinedButton(
                onPressed: () => onEditLandmarks(route),
                style: compactOutlinedStyle,
                child: const Text('Edit landmarks'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => onEditTerminal(route),
                style: compactOutlinedStyle,
                child: const Text('Terminal'),
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

class _TerminalSettingsDialog extends StatefulWidget {
  const _TerminalSettingsDialog({required this.route});

  final RouteSummaryModel route;

  @override
  State<_TerminalSettingsDialog> createState() =>
      _TerminalSettingsDialogState();
}

class _TerminalSettingsDialogState extends State<_TerminalSettingsDialog> {
  static const _defaultCenter = LatLng(14.6091, 121.0223);

  late bool _enabled;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _stopRefCtrl;
  late final TextEditingController _radiusCtrl;
  LatLng? _point;
  String? _message;

  @override
  void initState() {
    super.initState();
    final configured = widget.route.terminal;
    final effective = widget.route.effectiveTerminal;
    _enabled = configured?.enabled ?? effective != null;
    _point = configured?.position ?? effective?.position;
    _nameCtrl = TextEditingController(
      text: configured?.name?.trim().isNotEmpty == true
          ? configured!.name
          : effective?.label,
    );
    _stopRefCtrl = TextEditingController(
      text: configured?.stopRef?.trim().isNotEmpty == true
          ? configured!.stopRef
          : effective?.label,
    );
    _radiusCtrl = TextEditingController(
      text: (configured?.radiusMeters ?? effective?.radiusMeters ?? 75)
          .toString(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stopRefCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  LatLng get _mapCenter {
    final point = _point;
    if (point != null) return point;
    final bounds = widget.route.mapBounds;
    if (bounds != null) return bounds.center;
    final references = widget.route.referencePoints;
    if (references.isNotEmpty) return references.first;
    return _defaultCenter;
  }

  double get _mapZoom {
    if (_point != null) return 15.4;
    final bounds = widget.route.mapBounds;
    if (bounds == null) return 13.2;
    final span = ((bounds.north - bounds.south).abs() +
            (bounds.east - bounds.west).abs()) /
        2;
    if (span < 0.01) return 15.2;
    if (span < 0.04) return 13.8;
    return 12.6;
  }

  void _useStop(RouteStopPoint stop) {
    setState(() {
      _point = stop.position;
      if (_nameCtrl.text.trim().isEmpty ||
          _nameCtrl.text.trim() == 'Route terminal') {
        _nameCtrl.text = stop.name;
      }
      _stopRefCtrl.text = stop.name;
      _message = 'Terminal pin moved to ${stop.name}.';
    });
  }

  void _save() {
    if (!_enabled) {
      Navigator.of(context).pop(<String, dynamic>{'enabled': false});
      return;
    }

    final point = _point;
    if (point == null) {
      setState(() => _message = 'Choose the terminal location on the map.');
      return;
    }
    final radius = int.tryParse(_radiusCtrl.text.trim());
    if (radius == null || radius < 1) {
      setState(() => _message = 'Terminal radius must be at least 1 meter.');
      return;
    }

    final name = _nameCtrl.text.trim();
    final stopRef = _stopRefCtrl.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'enabled': true,
      'name': name.isEmpty ? 'Route terminal' : name,
      'stopRef': stopRef.isEmpty ? name : stopRef,
      'radiusMeters': radius,
      'location': {
        'type': 'Point',
        'coordinates': <double>[point.longitude, point.latitude],
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.route;
    final stops = route.stopPoints;
    final point = _point;

    return AlertDialog(
      title: Text('Terminal settings - ${route.code}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable terminal queue for this route'),
                value: _enabled,
                onChanged: (value) => setState(() {
                  _enabled = value;
                  _message = value
                      ? 'Terminal queue enabled. Confirm the location before saving.'
                      : 'Terminal queue will be disabled for this route.';
                }),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  final nameField = TextField(
                    controller: _nameCtrl,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      labelText: 'Terminal name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  );
                  final stopRefField = TextField(
                    controller: _stopRefCtrl,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      labelText: 'Terminal label',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  );
                  final radiusField = TextField(
                    controller: _radiusCtrl,
                    enabled: _enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Radius meters',
                      prefixIcon: Icon(Icons.radar_outlined),
                    ),
                  );

                  if (stacked) {
                    return Column(
                      children: [
                        nameField,
                        const SizedBox(height: 10),
                        stopRefField,
                        const SizedBox(height: 10),
                        radiusField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: nameField),
                      const SizedBox(width: 10),
                      Expanded(child: stopRefField),
                      const SizedBox(width: 10),
                      SizedBox(width: 170, child: radiusField),
                    ],
                  );
                },
              ),
              if (stops.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: null,
                  decoration: const InputDecoration(
                    labelText: 'Use route landmark as terminal',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  items: [
                    for (var index = 0; index < stops.length; index += 1)
                      DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          stops[index].name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: !_enabled
                      ? null
                      : (index) {
                          if (index != null) {
                            _useStop(stops[index]);
                          }
                        },
                ),
              ],
              const SizedBox(height: 12),
              Text(
                point == null
                    ? 'Terminal pin not set'
                    : 'Terminal pin: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: _mapZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: !_enabled
                          ? null
                          : (_, selectedPoint) {
                              setState(() {
                                _point = selectedPoint;
                                _message =
                                    'Terminal pin moved. Save to apply it.';
                              });
                            },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.parago.admin',
                      ),
                      if (route.mapPath.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: route.mapPath,
                              strokeWidth: 5,
                              color: const Color(0xFF0F6A5F),
                            ),
                          ],
                        ),
                      if (point != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: point,
                              radius: (double.tryParse(
                                            _radiusCtrl.text.trim(),
                                          ) ??
                                          75)
                                      .clamp(20, 250)
                                      .toDouble() /
                                  2,
                              color: const Color(0xFF8A3B5D)
                                  .withValues(alpha: 0.16),
                              borderColor: const Color(0xFF8A3B5D),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          for (final stop in stops.take(20))
                            Marker(
                              point: stop.position,
                              width: 118,
                              height: 58,
                              child: _TerminalMapMarker(
                                label: stop.name,
                                icon: Icons.place_outlined,
                                accent: const Color(0xFF2157A5),
                              ),
                            ),
                          if (point != null)
                            Marker(
                              point: point,
                              width: 132,
                              height: 64,
                              child: const _TerminalMapMarker(
                                label: 'Terminal',
                                icon: Icons.storefront,
                                accent: Color(0xFF8A3B5D),
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
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save terminal'),
        ),
      ],
    );
  }
}

class _TerminalMapMarker extends StatelessWidget {
  const _TerminalMapMarker({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 82),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Icon(Icons.arrow_drop_down, color: accent, size: 28),
      ],
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
        borderRadius: BorderRadius.circular(8),
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
