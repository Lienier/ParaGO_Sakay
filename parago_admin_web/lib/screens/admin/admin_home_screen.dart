import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
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
  dispatch,
  reports,
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
  bool _reloadRequested = false;
  int _dispatchRevision = 0;
  final Map<String, String> _sectionErrors = {};
  final Map<String, DateTime> _sectionTimes = {};
  final Set<String> _sectionLoading = {};
  DateTimeRange _reportRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now());
  int _reportGeneration = 0;
  String? _dispatchRoute;

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

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    setState(() => _loading = true);
    final admin = AdminService(context.read<SessionController>().apiClient);
    Future<void> fetch(
        String key,
        Future<Map<String, dynamic>> Function() request,
        void Function(Map<String, dynamic>) assign) async {
      final revision = _dispatchRevision;
      setState(() => _sectionLoading.add(key));
      try {
        final data = await request();
        if (!mounted || (key == 'dispatch' && revision != _dispatchRevision))
          return;
        setState(() {
          assign(data);
          _sectionErrors.remove(key);
          _sectionTimes[key] = DateTime.now();
        });
      } catch (_) {
        if (mounted) {
          setState(() => _sectionErrors[key] =
              'Unable to refresh this section. Please retry.');
        }
      } finally {
        if (mounted) setState(() => _sectionLoading.remove(key));
      }
    }

    await Future.wait([
      fetch('activity', () => admin.dashboard(useCache: false),
          (data) => _dashboard = data),
      fetch('dispatch', () => admin.hybridDispatchBoard(useCache: false),
          (data) => _hybridDispatchBoard = data),
    ]);
    if (mounted) {
      setState(() => _loading = false);
      if (_reloadRequested) {
        _reloadRequested = false;
        unawaited(_load(silent: true));
      }
    }
  }

  Future<void> _loadReport() async {
    final generation = ++_reportGeneration;
    final range = _reportRange;
    setState(() => _sectionLoading.add('reports'));
    try {
      final data =
          await AdminService(context.read<SessionController>().apiClient)
              .reportPassengerFlow(
                  fromIso: range.start.toUtc().toIso8601String(),
                  toIso: range.end.toUtc().toIso8601String(),
                  useCache: false);
      if (!mounted || generation != _reportGeneration) return;
      setState(() {
        _passengerFlowReport = data;
        _sectionErrors.remove('reports');
        _sectionTimes['reports'] = DateTime.now();
      });
    } catch (_) {
      if (mounted && generation == _reportGeneration) {
        setState(() => _sectionErrors['reports'] =
            'Unable to refresh this report. Please retry.');
      }
    } finally {
      if (mounted && generation == _reportGeneration) {
        setState(() => _sectionLoading.remove('reports'));
      }
    }
  }

  void _selectSection(_AdminWorkspaceSection section) {
    setState(() => _selectedSection = section);
    if (section == _AdminWorkspaceSection.reports &&
        _passengerFlowReport == null &&
        !_sectionLoading.contains('reports')) {
      _loadReport();
    }
  }

  Future<void> _pickReportRange() async {
    final selected = await showDateRangePicker(
        context: context,
        initialDateRange: _reportRange,
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (selected == null || !mounted) return;
    final inclusiveEnd = selected.end
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    if (inclusiveEnd.difference(selected.start) > const Duration(days: 366)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose a date range of no more than 366 days.')));
      return;
    }
    setState(() {
      _reportRange = DateTimeRange(start: selected.start, end: inclusiveEnd);
      _passengerFlowReport = null;
      _sectionTimes.remove('reports');
      _sectionErrors.remove('reports');
    });
    await _loadReport();
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

  SessionController? _securitySession;
  String? _securitySocketToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionController>();
    if (!identical(session, _securitySession)) {
      _securitySession?.removeListener(_handleSecuritySession);
      _securitySession = session;
      _securitySocketToken = session.token;
      session.addListener(_handleSecuritySession);
    }
  }

  void _handleSecuritySession() {
    final session = _securitySession;
    if (!mounted || session == null || session.token == _securitySocketToken) {
      return;
    }
    _securitySocketToken = session.token;
    if (session.token == null) {
      _realtimeSocketService.disconnect();
      return;
    }
    _connectRealtimeSocket();
  }

  @override
  void dispose() {
    _securitySession?.removeListener(_handleSecuritySession);
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

    unawaited(_load(silent: true));
  }

  Future<String?> _terminalReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Reason for terminal change'),
                content: TextField(
                    controller: controller,
                    maxLength: 500,
                    decoration:
                        const InputDecoration(labelText: 'Required reason')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                      child: const Text('Confirm'))
                ]));
    controller.dispose();
    return result;
  }

  Future<void> _reorderTerminalQueueTrip(
    String tripId,
    String direction,
  ) async {
    final reason = await _terminalReason();
    if (reason == null || !mounted) return;
    try {
      final session = context.read<SessionController>();
      final board = await AdminService(session.apiClient)
          .reorderTerminalQueueTrip(
              tripId: tripId, direction: direction, reason: reason);
      if (!mounted) return;
      setState(() {
        _dispatchRevision++;
        _hybridDispatchBoard = board;
        _sectionTimes['dispatch'] = DateTime.now();
        _sectionErrors.remove('dispatch');
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
    final reason = await _terminalReason();
    if (reason == null || !mounted) return;
    try {
      final session = context.read<SessionController>();
      final board = await AdminService(session.apiClient)
          .setTerminalQueueSkipped(
              tripId: tripId, skipped: skipped, reason: reason);
      if (!mounted) return;
      setState(() {
        _dispatchRevision++;
        _hybridDispatchBoard = board;
        _sectionTimes['dispatch'] = DateTime.now();
        _sectionErrors.remove('dispatch');
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue update failed: $error')),
      );
    }
  }

  Widget _buildWorkspaceContent() {
    switch (_selectedSection) {
      case _AdminWorkspaceSection.overview:
      case _AdminWorkspaceSection.dispatch:
      case _AdminWorkspaceSection.reports:
        return _AdminOperationsPage(
          section: _selectedSection,
          dashboard: _dashboard,
          board: _hybridDispatchBoard,
          report: _passengerFlowReport,
          errors: _sectionErrors,
          times: _sectionTimes,
          loading: _sectionLoading,
          onRetry: (key) => key == 'reports' ? _loadReport() : _load(),
          onSelect: _selectSection,
          route: _dispatchRoute,
          onRoute: (value) => setState(() => _dispatchRoute = value),
          reportRange: _reportRange,
          onReportRange: _pickReportRange,
          onReorder: _reorderTerminalQueueTrip,
          onSkip: _setTerminalQueueSkipped,
          onDepart: _setTerminalQueueStatus,
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
        return Column(children: [
          Align(
              alignment: Alignment.centerRight,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                      onPressed: () =>
                          _selectSection(_AdminWorkspaceSection.routeBuilder),
                      child: const Text('Create route')))),
          Expanded(
              child: AdminRouteManagementScreen(
            embedded: true,
            onChanged: () => _load(silent: true),
          ))
        ]);
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
    final matches = _readDynamicList(_hybridDispatchBoard?['terminalQueue'])
        .where((t) => t['_id']?.toString() == tripId);
    if (matches.isEmpty) return;
    final trip = matches.first;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Depart terminal?'),
                content: Text(
                    '${trip['occupancyCount'] ?? 0} onboard passengers stay on this trip. ${trip['terminalSummary']?['reservedSeats'] ?? 0} unboarded reserved seats will be released and affected bookings offered a transfer. This does not end the trip.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Continue'))
                ]));
    if (confirmed != true || !mounted) return;
    final reason = await _terminalReason();
    if (reason == null || !mounted) return;
    try {
      final session = context.read<SessionController>();
      final board =
          await AdminService(session.apiClient).setTerminalQueueStatus(
        tripId: tripId,
        terminalQueueStatus: terminalQueueStatus,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _dispatchRevision++;
        _hybridDispatchBoard = board;
        _sectionTimes['dispatch'] = DateTime.now();
        _sectionErrors.remove('dispatch');
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue update failed: $error')),
      );
    }
  }

  Widget _navigation({bool drawer = false}) => Container(
        width: 224,
        color: AppColors.surface,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Text('SakayGaray',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('WORKSPACE',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: AppColors.textSecondary))),
          const SizedBox(height: 12),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                for (final section in const [
                  _AdminWorkspaceSection.overview,
                  _AdminWorkspaceSection.dispatch,
                  _AdminWorkspaceSection.drivers,
                  _AdminWorkspaceSection.routes,
                  _AdminWorkspaceSection.fareSettings,
                  _AdminWorkspaceSection.announcements,
                  _AdminWorkspaceSection.support,
                  _AdminWorkspaceSection.reports
                ]) ...[
                  if ([
                    _AdminWorkspaceSection.overview,
                    _AdminWorkspaceSection.drivers,
                    _AdminWorkspaceSection.announcements,
                    _AdminWorkspaceSection.reports
                  ].contains(section))
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                        child: Text(
                            section == _AdminWorkspaceSection.overview
                                ? 'Operations'
                                : section == _AdminWorkspaceSection.drivers
                                    ? 'Management'
                                    : section ==
                                            _AdminWorkspaceSection.announcements
                                        ? 'Communication'
                                        : 'Reporting',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary))),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        minTileHeight: 44,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.medium),
                        selected: _selectedSection == section,
                        selectedColor: AppColors.primaryDark,
                        selectedTileColor: const Color(0xFFF0F6F5),
                        title: Text(_sectionLabel(section)),
                        onTap: () {
                          _selectSection(section);
                          if (drawer) Navigator.pop(context);
                        },
                      )),
                ],
              ])),
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Administration',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final desktop = MediaQuery.sizeOf(context).width >= 1100;
    final workspace = Column(children: [
      Container(
          height: 64,
          decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            if (!desktop)
              Builder(
                  builder: (context) => IconButton(
                      tooltip: 'Open navigation',
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer())),
            Expanded(
                child: Text(_sectionLabel(_selectedSection),
                    style: Theme.of(context).textTheme.titleMedium)),
            TextButton(
                onPressed: () =>
                    _selectedSection == _AdminWorkspaceSection.reports
                        ? _loadReport()
                        : _load(),
                child: const Text('Refresh')),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
                tooltip: 'Account menu',
                onSelected: (_) => _confirmAdminLogout(session),
                itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'logout', child: Text('Log out'))
                    ],
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(session.user?.fullName ?? 'Administrator'))),
          ])),
      Expanded(child: _buildWorkspaceContent()),
    ]);
    return Scaffold(
      drawer: desktop
          ? null
          : Drawer(child: SafeArea(child: _navigation(drawer: true))),
      body: SafeArea(
          child: Row(children: [
        if (desktop) ...[_navigation(), const VerticalDivider(width: 1)],
        Expanded(child: workspace),
      ])),
    );
  }
}
