import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/admin_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';
import '../../widgets/metric_card.dart';
import 'admin_driver_management_screen.dart';
import 'admin_route_builder_screen.dart';
import 'admin_route_management_screen.dart';

part 'admin_home_sections.dart';

enum _AdminWorkspaceSection {
  overview,
  drivers,
  routeBuilder,
  routes,
}

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
  Timer? _pollingTimer;
  StreamSubscription<Map<String, dynamic>>? _operationsSubscription;
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  _AdminWorkspaceSection _selectedSection = _AdminWorkspaceSection.overview;

  Future<void> _load({bool silent = false}) async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    if (!silent) {
      setState(() => _loading = true);
    }

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
        routeService.getRoutes(useCache: false),
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
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (AppConfig.enableRealtime) {
        _connectRealtimeSocket();
      } else {
        _startPolling();
      }
      await _load();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _operationsSubscription?.cancel();
    _realtimeSocketService.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _loading) {
        return;
      }
      await _load(silent: true);
    });
  }

  void _connectRealtimeSocket() {
    final session = context.read<SessionController>();
    final token = session.token?.trim() ?? '';
    if (token.isEmpty) {
      return;
    }

    _operationsSubscription?.cancel();
    _operationsSubscription =
        _realtimeSocketService.operationsChangedStream.listen(
      _handleOperationsEvent,
    );
    _realtimeSocketService.connect(
      apiBaseUrl: session.apiClient.baseUrl,
      token: token,
    );
  }

  void _handleOperationsEvent(Map<String, dynamic> event) {
    if (!mounted) {
      return;
    }

    final notificationType = event['notificationType']?.toString() ?? '';
    if (notificationType.isEmpty) {
      return;
    }

    final payload = _normalizeRealtimePayload(event['payload']);
    final title = event['title']?.toString() ?? 'Operations update';
    final body = event['body']?.toString() ?? '';
    final createdAt = event['createdAt']?.toString();

    setState(() {
      _dashboard = _applyDashboardRealtimeEvent(
        _dashboard,
        notificationType: notificationType,
        payload: payload,
      );
      _requestReport = _applyRequestReportRealtimeEvent(
        _requestReport,
        notificationType: notificationType,
        payload: payload,
      );
      _activity = _prependRealtimeActivity(
        _activity,
        notificationType: notificationType,
        title: title,
        body: body,
        createdAt: createdAt,
        payload: payload,
      );
    });
  }

  Map<String, dynamic> _applyDashboardRealtimeEvent(
    Map<String, dynamic>? current, {
    required String notificationType,
    required Map<String, dynamic> payload,
  }) {
    final next = <String, dynamic>{
      'activeTrips': _readIntMetric(current?['activeTrips']),
      'pendingRequests': _readIntMetric(current?['pendingRequests']),
      'onboardRides': _readIntMetric(current?['onboardRides']),
      'activeAlerts': _readIntMetric(current?['activeAlerts']),
    };

    switch (notificationType) {
      case 'pickup_request_created':
        next['pendingRequests'] = _readIntMetric(next['pendingRequests']) + 1;
        break;
      case 'pickup_request_acknowledged':
      case 'pickup_request_completed':
        final previousStatus = payload['previousStatus']?.toString() ?? '';
        if (previousStatus == 'pending') {
          next['pendingRequests'] =
              (_readIntMetric(next['pendingRequests']) - 1).clamp(0, 1 << 30);
        }
        final ridePreviousStatus =
            payload['ridePreviousStatus']?.toString() ?? '';
        if (ridePreviousStatus == 'onboard') {
          next['onboardRides'] =
              (_readIntMetric(next['onboardRides']) - 1).clamp(0, 1 << 30);
        }
        break;
      case 'stop_alert_created':
        next['activeAlerts'] = _readIntMetric(next['activeAlerts']) + 1;
        break;
      case 'stop_alert_acknowledged':
        final previousStatus = payload['previousStatus']?.toString() ?? '';
        if (previousStatus == 'sent' || previousStatus == 'seen') {
          next['activeAlerts'] =
              (_readIntMetric(next['activeAlerts']) - 1).clamp(0, 1 << 30);
        }
        break;
      case 'ride_completed':
        final previousStatus = payload['previousStatus']?.toString() ?? '';
        if (previousStatus == 'onboard') {
          next['onboardRides'] =
              (_readIntMetric(next['onboardRides']) - 1).clamp(0, 1 << 30);
        }
        break;
    }

    return next;
  }

  Map<String, dynamic> _applyRequestReportRealtimeEvent(
    Map<String, dynamic>? current, {
    required String notificationType,
    required Map<String, dynamic> payload,
  }) {
    final request = _normalizeRealtimePayload(payload['request']);
    if (request.isEmpty) {
      return current ?? <String, dynamic>{'total': 0, 'byStatus': <dynamic>[]};
    }

    final currentStatus = request['status']?.toString() ?? '';
    if (currentStatus.isEmpty) {
      return current ?? <String, dynamic>{'total': 0, 'byStatus': <dynamic>[]};
    }

    final rows = List<Map<String, dynamic>>.from(
      (current?['byStatus'] as List<dynamic>? ?? const <dynamic>[])
          .map((entry) => Map<String, dynamic>.from(entry as Map)),
    );
    var total = _readIntMetric(current?['total']);

    if (notificationType == 'pickup_request_created') {
      total += 1;
      _adjustStatusCount(rows, currentStatus, 1);
    } else {
      final previousStatus = payload['previousStatus']?.toString() ?? '';
      if (previousStatus.isNotEmpty && previousStatus != currentStatus) {
        _adjustStatusCount(rows, previousStatus, -1);
        _adjustStatusCount(rows, currentStatus, 1);
      }
    }

    rows.removeWhere((row) => _readIntMetric(row['count']) <= 0);
    return <String, dynamic>{'total': total, 'byStatus': rows};
  }

  void _adjustStatusCount(
    List<Map<String, dynamic>> rows,
    String status,
    int delta,
  ) {
    final index = rows.indexWhere((row) => row['_id']?.toString() == status);
    if (index >= 0) {
      rows[index] = <String, dynamic>{
        ...rows[index],
        'count':
            (_readIntMetric(rows[index]['count']) + delta).clamp(0, 1 << 30),
      };
      return;
    }

    if (delta > 0) {
      rows.add(<String, dynamic>{'_id': status, 'count': delta});
    }
  }

  List<dynamic> _prependRealtimeActivity(
    List<dynamic> current, {
    required String notificationType,
    required String title,
    required String body,
    required String? createdAt,
    required Map<String, dynamic> payload,
  }) {
    final next = List<dynamic>.from(current);
    next.insert(
      0,
      <String, dynamic>{
        'action': title,
        'entity': notificationType,
        'details': <String, dynamic>{
          'message': body,
          'notificationType': notificationType,
          ...payload,
        },
        'createdAt': createdAt ?? DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (next.length > 40) {
      next.removeRange(40, next.length);
    }
    return next;
  }

  int _readIntMetric(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _normalizeRealtimePayload(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }

  String _sectionTitle(_AdminWorkspaceSection section) {
    switch (section) {
      case _AdminWorkspaceSection.overview:
        return 'Operations Overview';
      case _AdminWorkspaceSection.drivers:
        return 'Driver Management';
      case _AdminWorkspaceSection.routeBuilder:
        return 'Route Builder';
      case _AdminWorkspaceSection.routes:
        return 'Route Management';
    }
  }

  String _sectionSubtitle(_AdminWorkspaceSection section) {
    switch (section) {
      case _AdminWorkspaceSection.overview:
        return 'Live admin metrics, recent activity, route health, and pickup behavior.';
      case _AdminWorkspaceSection.drivers:
        return 'Create driver accounts, assign jeepneys, and schedule trips from one workspace.';
      case _AdminWorkspaceSection.routeBuilder:
        return 'Create or update route geometry directly on the map with offline-ready snapshots.';
      case _AdminWorkspaceSection.routes:
        return 'Edit active routes, landmark drop-off points, and per-landmark fares.';
    }
  }

  Widget _buildWorkspaceContent() {
    switch (_selectedSection) {
      case _AdminWorkspaceSection.overview:
        return _AdminOverviewPage(
          loading: _loading,
          error: _error,
          dashboard: _dashboard,
          requestReport: _requestReport,
          activity: _activity,
          routes: _routes,
          onRefresh: _load,
          onSelectDrivers: () =>
              setState(() => _selectedSection = _AdminWorkspaceSection.drivers),
          onSelectBuilder: () => setState(
            () => _selectedSection = _AdminWorkspaceSection.routeBuilder,
          ),
          onSelectRoutes: () =>
              setState(() => _selectedSection = _AdminWorkspaceSection.routes),
        );
      case _AdminWorkspaceSection.drivers:
        return AdminDriverManagementScreen(
          embedded: true,
          onChanged: () => _load(silent: true),
        );
      case _AdminWorkspaceSection.routeBuilder:
        return AdminRouteBuilderScreen(
          embedded: true,
          onSaved: () => _load(silent: true),
        );
      case _AdminWorkspaceSection.routes:
        return AdminRouteManagementScreen(
          embedded: true,
          onChanged: () => _load(silent: true),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final userName = session.user?.fullName ?? 'Administrator';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F1E8),
      appBar: AppBar(
        title: const Text('ParaGO! Admin'),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    userName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.tonalIcon(
              onPressed: session.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 980;
            final content = _buildWorkspaceContent();

            if (desktop) {
              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: _AdminWorkspaceSection.values.indexOf(
                      _selectedSection,
                    ),
                    onDestinationSelected: (index) {
                      setState(
                        () => _selectedSection =
                            _AdminWorkspaceSection.values[index],
                      );
                    },
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 24,
                            child: Icon(Icons.alt_route_outlined),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Admin',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    destinations: [
                      for (final section in _AdminWorkspaceSection.values)
                        NavigationRailDestination(
                          icon: Icon(_sectionIcon(section)),
                          label: Text(_sectionLabel(section)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _sectionTitle(_selectedSection),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _sectionSubtitle(_selectedSection),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: ColoredBox(
                                color: Colors.white.withValues(alpha: 0.72),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _AdminCompactNav(
                    selectedSection: _selectedSection,
                    onSelect: (section) {
                      setState(() => _selectedSection = section);
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sectionTitle(_selectedSection),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(_sectionSubtitle(_selectedSection)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.72),
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
