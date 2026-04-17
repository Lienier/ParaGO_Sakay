import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/parago_format.dart';
import '../../services/admin_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../widgets/metric_card.dart';
import 'admin_driver_management_screen.dart';
import 'admin_route_builder_screen.dart';
import 'admin_route_fare_settings_screen.dart';
import 'admin_route_management_screen.dart';

part 'admin_home_sections.dart';

enum _AdminWorkspaceSection {
  overview,
  drivers,
  routeBuilder,
  routes,
  fareSettings,
}

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _passengerFlowReport;
  Map<String, dynamic>? _hybridDispatchBoard;
  bool _loading = false;
  String? _error;
  DateTime? _lastSyncedAt;
  bool _showingCachedSnapshot = false;
  Timer? _pollingTimer;
  StreamSubscription<Map<String, dynamic>>? _operationsSubscription;
  final RealtimeSocketService _realtimeSocketService = RealtimeSocketService();
  _AdminWorkspaceSection _selectedSection = _AdminWorkspaceSection.overview;

  Future<void> _load({bool silent = false}) async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final requestStartedAt = DateTime.now();

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final now = DateTime.now().toUtc();
      final from = now.subtract(const Duration(days: 7));
      final results = await Future.wait<dynamic>([
        admin.dashboard(),
        admin.reportPassengerFlow(
          fromIso: from.toIso8601String(),
          toIso: now.toIso8601String(),
        ),
        admin.hybridDispatchBoard(),
      ]);

      final usedStaleCache = session.apiClient.recentTelemetry.any(
        (entry) =>
            entry.occurredAt.isAfter(requestStartedAt) && entry.usedStaleCache,
      );

      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Map<String, dynamic>;
        _passengerFlowReport = results[1] as Map<String, dynamic>;
        _hybridDispatchBoard = results[2] as Map<String, dynamic>;
        _error = null;
        _lastSyncedAt = DateTime.now();
        _showingCachedSnapshot = usedStaleCache;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _dashboard == null ? error.toString() : null;
        if (_dashboard != null) {
          _showingCachedSnapshot = true;
        }
      });
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

    setState(() {
      _dashboard = _applyDashboardRealtimeEvent(
        _dashboard,
        notificationType: notificationType,
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
      case _AdminWorkspaceSection.fareSettings:
        return 'Fare Settings';
    }
  }

  String _sectionSubtitle(_AdminWorkspaceSection section) {
    switch (section) {
      case _AdminWorkspaceSection.overview:
        return 'Live operations metrics with a focused passenger boarding and unload report.';
      case _AdminWorkspaceSection.drivers:
        return 'Create driver accounts, assign jeepneys, and schedule trips from one workspace.';
      case _AdminWorkspaceSection.routeBuilder:
        return 'Create or update route geometry directly on the map with offline-ready snapshots.';
      case _AdminWorkspaceSection.routes:
        return 'Edit active routes, landmark drop-off points, and per-landmark fares.';
      case _AdminWorkspaceSection.fareSettings:
        return 'Configure base fares, distance rates, and fare rules for your routes.';
    }
  }

  Widget _buildWorkspaceContent() {
    switch (_selectedSection) {
      case _AdminWorkspaceSection.overview:
        return _AdminOverviewPage(
          loading: _loading,
          error: _error,
          dashboard: _dashboard,
          passengerFlowReport: _passengerFlowReport,
          hybridDispatchBoard: _hybridDispatchBoard,
          lastSyncedAt: _lastSyncedAt,
          showingCachedSnapshot: _showingCachedSnapshot,
          onRefresh: _load,
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
      case _AdminWorkspaceSection.fareSettings:
        return AdminRouteFareSettingsScreen(
          embedded: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final userName = session.user?.fullName ?? 'Administrator';
    final compactHeader = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F1E8),
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 18,
        title: _AdminHeaderBrand(userName: userName),
        actions: [
          if (!compactHeader) ...[
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      await session.apiClient.clearCache();
                      await _load();
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: compactHeader
                ? IconButton.filledTonal(
                    onPressed: session.logout,
                    tooltip: 'Log out',
                    icon: const Icon(Icons.logout),
                  )
                : TextButton.icon(
                    onPressed: session.logout,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
          ),
          if (compactHeader)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: _loading
                    ? null
                    : () async {
                        await session.apiClient.clearCache();
                        await _load();
                      },
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
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
                            'Console',
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
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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

class _AdminHeaderBrand extends StatelessWidget {
  const _AdminHeaderBrand({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F2EF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.admin_panel_settings_outlined,
            color: Color(0xFF0F6A5F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ParaGO! Admin',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Signed in as $userName',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
