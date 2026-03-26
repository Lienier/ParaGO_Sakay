import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/parago_format.dart';
import '../../models/transport/route_summary.dart';
import '../../services/admin_service.dart';
import '../../services/realtime_socket_service.dart';
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
  StreamSubscription<Map<String, dynamic>>? _operationsSubscription;
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();

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
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _connectRealtimeSocket();
      await _load();
    });
  }

  @override
  void dispose() {
    _operationsSubscription?.cancel();
    _realtimeSocketService.dispose();
    super.dispose();
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
        'count': (_readIntMetric(rows[index]['count']) + delta).clamp(0, 1 << 30),
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
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
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
