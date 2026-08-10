import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_breakpoints.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../core/utils/parago_format.dart';
import '../../services/admin_service.dart';
import '../../services/realtime_socket_service.dart';
import '../../services/session_controller.dart';
import '../../widgets/metric_card.dart';
import 'admin_driver_management_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_route_builder_screen.dart';
import 'admin_route_fare_settings_screen.dart';
import 'admin_route_management_screen.dart';
import 'admin_support_inbox_screen.dart';

part 'admin_home_sections.dart';

enum _AdminWorkspaceSection {
  overview,
  drivers,
  routeBuilder,
  routes,
  fareSettings,
  announcements,
  support,
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

  Future<void> _confirmAdminLogout(SessionController session) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Are you sure you want to log out of the admin application?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await session.logout();
    }
  }

  Future<void> _showMoreNavigation() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More workspace tools', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              for (final section in const [
                _AdminWorkspaceSection.routeBuilder,
                _AdminWorkspaceSection.fareSettings,
                _AdminWorkspaceSection.announcements,
                _AdminWorkspaceSection.support,
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_sectionIcon(section)),
                  title: Text(_sectionLabel(section)),
                  selected: _selectedSection == section,
                  selectedTileColor: AppColors.primaryContainer,
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.medium),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _selectedSection = section);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

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
      'terminalQueueTrips': _readIntMetric(current?['terminalQueueTrips']),
      'routeModeTrips': _readIntMetric(current?['routeModeTrips']),
      'terminalRequests': _readIntMetric(current?['terminalRequests']),
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

  Future<void> _reorderTerminalQueueTrip(
    String tripId,
    String direction,
  ) async {
    try {
      final session = context.read<SessionController>();
      final board = await AdminService(session.apiClient)
          .reorderTerminalQueueTrip(tripId: tripId, direction: direction);
      if (!mounted) return;
      setState(() {
        _hybridDispatchBoard = board;
        _lastSyncedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue update failed: $error')),
      );
    }
  }

  Future<void> _setTerminalQueueSkipped(
    String tripId,
    bool skipped,
  ) async {
    try {
      final session = context.read<SessionController>();
      final board = await AdminService(session.apiClient)
          .setTerminalQueueSkipped(tripId: tripId, skipped: skipped);
      if (!mounted) return;
      setState(() {
        _hybridDispatchBoard = board;
        _lastSyncedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue update failed: $error')),
      );
    }
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
          onReorderTerminalTrip: _reorderTerminalQueueTrip,
          onSetTerminalTripSkipped: _setTerminalQueueSkipped,
          onSetTerminalTripStatus: _setTerminalQueueStatus,
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
      case _AdminWorkspaceSection.announcements:
        return AdminAnnouncementsScreen(
          realtimeSocketService: _realtimeSocketService,
        );
      case _AdminWorkspaceSection.support:
        return AdminSupportInboxScreen(
          realtimeSocketService: _realtimeSocketService,
        );
    }
  }

  Future<void> _setTerminalQueueStatus(
    String tripId,
    String terminalQueueStatus,
  ) async {
    try {
      final session = context.read<SessionController>();
      final board =
          await AdminService(session.apiClient).setTerminalQueueStatus(
        tripId: tripId,
        terminalQueueStatus: terminalQueueStatus,
      );
      if (!mounted) return;
      setState(() {
        _hybridDispatchBoard = board;
        _lastSyncedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue update failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final userName = session.user?.fullName ?? 'Administrator';
    final compactHeader = MediaQuery.sizeOf(context).width < 900;
    final mobile = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 18,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        title: _AdminHeaderBrand(userName: userName, compact: mobile),
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
                    onPressed: () => _confirmAdminLogout(session),
                    tooltip: 'Log out',
                    icon: const Icon(Icons.logout),
                  )
                : TextButton.icon(
                    onPressed: () => _confirmAdminLogout(session),
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
                    backgroundColor: AppColors.surface,
                    minWidth: 224,
                    groupAlignment: -0.85,
                    useIndicator: true,
                    indicatorColor: AppColors.primaryContainer,
                    selectedIconTheme: const IconThemeData(color: AppColors.primaryDark),
                    selectedLabelTextStyle: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
                    unselectedLabelTextStyle: const TextStyle(color: AppColors.textSecondary),
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
                    destinations: [
                      for (final section in _AdminWorkspaceSection.values)
                        NavigationRailDestination(
                          icon: Icon(_sectionIcon(section)),
                          label: Text(_sectionLabel(section)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
                      child: content,
                    ),
                  ),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: mobile
                  ? content
                  : Column(
                      children: [
                        _AdminCompactNav(
                          selectedSection: _selectedSection,
                          onSelect: (section) => setState(() => _selectedSection = section),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(child: content),
                      ],
                    ),
            );
          },
        ),
      ),
      bottomNavigationBar: mobile
          ? SafeArea(
              top: false,
              child: NavigationBar(
                selectedIndex: _mobileNavigationIndex,
                onDestinationSelected: (index) {
                  if (index == 3) {
                    _showMoreNavigation();
                    return;
                  }
                  setState(() {
                    _selectedSection = const [
                      _AdminWorkspaceSection.overview,
                      _AdminWorkspaceSection.drivers,
                      _AdminWorkspaceSection.routes,
                    ][index];
                  });
                },
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Overview'),
                  NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: 'Drivers'),
                  NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: 'Routes'),
                  NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
                ],
              ),
            )
          : null,
    );
  }

  int get _mobileNavigationIndex {
    switch (_selectedSection) {
      case _AdminWorkspaceSection.overview:
        return 0;
      case _AdminWorkspaceSection.drivers:
        return 1;
      case _AdminWorkspaceSection.routes:
        return 2;
      default:
        return 3;
    }
  }
}

class _AdminHeaderBrand extends StatelessWidget {
  const _AdminHeaderBrand({required this.userName, this.compact = false});

  final String userName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: AppRadius.medium,
          child: Image.asset(
            'assets/images/SakayLogo.png',
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: compact ? 34 : 40,
              height: compact ? 34 : 40,
              color: AppColors.primaryContainer,
              child: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                compact ? 'SAKAY!' : 'SAKAY! Admin',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  'Signed in as $userName',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
