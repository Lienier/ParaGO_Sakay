import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/transport/route_summary.dart';
import '../../models/trip/trip_session.dart';
import '../../services/admin_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

part 'admin_driver_management_forms.dart';

class AdminDriverManagementScreen extends StatefulWidget {
  const AdminDriverManagementScreen({
    super.key,
    this.embedded = false,
    this.onChanged,
  });

  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<AdminDriverManagementScreen> createState() =>
      _AdminDriverManagementScreenState();
}

class _AdminDriverManagementScreenState
    extends State<AdminDriverManagementScreen> {
  final _createFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();

  final _createLicenseCtrl = TextEditingController();
  final _createEmployeeCtrl = TextEditingController();
  final _createPhoneCtrl = TextEditingController();
  final _createJeepneyPlateCtrl = TextEditingController();
  final _createJeepneyCapacityCtrl = TextEditingController();

  final _editLicenseCtrl = TextEditingController();
  final _editEmployeeCtrl = TextEditingController();
  final _editPhoneCtrl = TextEditingController();
  final _editJeepneyPlateCtrl = TextEditingController();
  final _editJeepneyCapacityCtrl = TextEditingController();

  final ValueNotifier<String?> _routeSelection = ValueNotifier<String?>(null);
  final ValueNotifier<String> _statusSelection =
      ValueNotifier<String>('active');
  final ValueNotifier<bool> _verifiedSelection = ValueNotifier<bool>(false);

  List<dynamic> _drivers = [];
  List<RouteSummaryModel> _routes = [];
  List<TripSession> _trips = [];

  bool _loading = false;
  bool _saving = false;
  String? _schedulingDriverId;
  String? _error;
  String _statusFilter = 'all';

  String? _createEmail;
  String? _createPassword;
  String? _createFullName;
  String? _createLicense;
  String? _createEmployee;
  String? _createPhone;
  String? _createRouteId;
  String? _createJeepneyPlateNumber;
  String? _createJeepneyCapacity;
  bool _createVerified = false;
  String _createStatus = 'active';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _createLicenseCtrl.dispose();
    _createEmployeeCtrl.dispose();
    _createPhoneCtrl.dispose();
    _createJeepneyPlateCtrl.dispose();
    _createJeepneyCapacityCtrl.dispose();
    _editLicenseCtrl.dispose();
    _editEmployeeCtrl.dispose();
    _editPhoneCtrl.dispose();
    _editJeepneyPlateCtrl.dispose();
    _editJeepneyCapacityCtrl.dispose();
    _routeSelection.dispose();
    _statusSelection.dispose();
    _verifiedSelection.dispose();
    super.dispose();
  }

  String _textOf(dynamic value) {
    return (value as String?)?.trim() ?? '';
  }

  String? _nullableText(String? value) {
    final text = _textOf(value);
    return text.isEmpty ? null : text;
  }

  String _statusLabel(String value) {
    if (value.isEmpty) return 'N/A';
    return value[0].toUpperCase() + value.substring(1);
  }

  String _idOf(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value['_id']?.toString() ?? '';
    }
    return value?.toString() ?? '';
  }

  String? _nullableIdOf(dynamic value) {
    final id = _idOf(value).trim();
    return id.isEmpty ? null : id;
  }

  bool _hasRoute(String? routeId) {
    if (routeId == null || routeId.isEmpty) return false;
    return _routes.any((route) => route.id == routeId);
  }

  Map<String, dynamic> _driverRoute(Map<String, dynamic> driver) {
    final route = driver['assignedRouteId'];
    if (route is Map<String, dynamic>) {
      return route;
    }
    if (route is String && route.isNotEmpty) {
      final match = _routes.firstWhere(
        (item) => item.id == route,
        orElse: () => const RouteSummaryModel(
          id: '',
          name: 'Unknown route',
          code: '',
          direction: 'circular',
          status: 'inactive',
        ),
      );
      return <String, dynamic>{
        '_id': match.id,
        'name': match.name,
        'code': match.code,
        'status': match.status,
      };
    }
    return <String, dynamic>{};
  }

  String _driverDisplayName(Map<String, dynamic> driver) {
    final user = driver['userId'];
    if (user is Map<String, dynamic>) {
      return _textOf(user['fullName']);
    }
    return _textOf(driver['fullName']);
  }

  String _driverEmail(Map<String, dynamic> driver) {
    final user = driver['userId'];
    if (user is Map<String, dynamic>) {
      return _textOf(user['email']);
    }
    return _textOf(driver['email']);
  }

  bool _matchesDriverSearch(Map<String, dynamic> driver, String query) {
    if (query.isEmpty) {
      return true;
    }
    final routeData = _driverRoute(driver);
    final jeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
    final haystack = [
      _driverDisplayName(driver),
      _driverEmail(driver),
      _textOf(driver['licenseNumber']),
      _textOf(driver['employeeNumber']),
      _textOf(driver['phone']),
      _textOf(routeData['code']),
      _textOf(routeData['name']),
      _textOf(jeepney?['plateNumber']),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  bool _matchesStatusFilter(Map<String, dynamic> driver) {
    final normalized = _textOf(driver['status']).toLowerCase();
    switch (_statusFilter) {
      case 'active':
        return normalized == 'active';
      case 'inactive':
        return normalized == 'inactive';
      case 'verified':
        return driver['isVerified'] == true;
      case 'unassigned':
        return _nullableIdOf(driver['assignedRouteId']) == null;
      default:
        return true;
    }
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    setState(() => _loading = true);

    try {
      final results = await Future.wait<dynamic>([
        admin.getDrivers(),
        routeService.getRoutes(),
        admin.getTrips(),
      ]);

      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<dynamic>;
        _routes = results[1] as List<RouteSummaryModel>;
        _trips = results[2] as List<TripSession>;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  TripSession? _openTripForDriver(String driverId) {
    if (driverId.isEmpty) return null;
    for (final trip in _trips) {
      if (trip.driverId == driverId &&
          (trip.status == 'scheduled' || trip.status == 'active')) {
        return trip;
      }
    }
    return null;
  }

  String? _scheduleTripBlockReason(Map<String, dynamic> driver) {
    final driverId = _idOf(driver['_id']);
    if (driverId.isEmpty) {
      return 'Driver profile is missing.';
    }

    final status = _textOf(driver['status']).toLowerCase();
    if (status != 'active') {
      return 'Driver account must be active.';
    }

    if (driver['isVerified'] != true) {
      return 'Driver must be verified first.';
    }

    final jeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
    final jeepneyId = _nullableIdOf(jeepney);
    if (jeepneyId == null) {
      return 'Assign a jeepney first.';
    }
    if (_textOf(jeepney?['status']).toLowerCase() != 'active') {
      return 'Assigned jeepney must be active.';
    }

    final route = _driverRoute(driver);
    final routeId = _nullableIdOf(route);
    if (routeId == null) {
      return 'Assign a route first.';
    }
    final routeStatus = _textOf(route['status']).toLowerCase();
    if (routeStatus.isNotEmpty && routeStatus != 'active') {
      return 'Assigned route must be active.';
    }

    final openTrip = _openTripForDriver(driverId);
    if (openTrip != null) {
      return 'Driver already has a ${openTrip.status} trip.';
    }

    return null;
  }

  Future<void> _scheduleTrip(Map<String, dynamic> driver) async {
    final blockReason = _scheduleTripBlockReason(driver);
    if (blockReason != null) {
      if (!mounted) return;
      await ActionFeedback.showInfoDialog(
        context,
        title: 'Trip cannot be scheduled',
        message: blockReason,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final route = _driverRoute(driver);
        final jeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
        return AlertDialog(
          title: const Text('Schedule trip'),
          content: Text(
            'Create a scheduled trip for ${_driverDisplayName(driver)} using '
            '${jeepney?['plateNumber'] ?? 'the assigned jeepney'} on '
            '${route['code'] ?? route['name'] ?? 'the assigned route'}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Schedule'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final driverId = _idOf(driver['_id']);
    final jeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
    final route = _driverRoute(driver);
    final jeepneyId = _nullableIdOf(jeepney)!;
    final routeId = _nullableIdOf(route)!;

    setState(() => _schedulingDriverId = driverId);
    try {
      await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Scheduling trip...',
        successMessage:
            'Trip scheduled for ${_driverDisplayName(driver)} (${route['code'] ?? route['name'] ?? 'assigned route'}).',
        action: () => admin.createTrip(
          driverId: driverId,
          jeepneyId: jeepneyId,
          routeId: routeId,
        ),
        onSuccess: (_) async {
          if (!mounted) return;
          await _load();
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _schedulingDriverId = null);
      }
    }
  }

  void _resetCreateForm() {
    _createEmail = null;
    _createPassword = null;
    _createFullName = null;
    _createLicense = null;
    _createEmployee = null;
    _createPhone = null;
    _createRouteId = null;
    _createJeepneyPlateNumber = null;
    _createJeepneyCapacity = null;
    _createVerified = false;
    _createStatus = 'active';
    _createLicenseCtrl.clear();
    _createEmployeeCtrl.clear();
    _createPhoneCtrl.clear();
    _createJeepneyPlateCtrl.clear();
    _createJeepneyCapacityCtrl.clear();
  }

  Future<void> _createDriver(BuildContext sheetContext) async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;
    _createFormKey.currentState?.save();

    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);

    setState(() => _saving = true);
    try {
      await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Creating driver account...',
        successMessage: 'Driver and jeepney created successfully.',
        action: () => admin.createDriverAccount(
          email: _createEmail!.trim(),
          password: _createPassword!.trim(),
          fullName: _createFullName!.trim(),
          licenseNumber: _createLicense,
          employeeNumber: _createEmployee,
          phone: _createPhone,
          routeId: _createRouteId,
          jeepneyPlateNumber: _createJeepneyPlateNumber!.trim(),
          jeepneyCapacity: int.parse(_createJeepneyCapacity!.trim()),
          isVerified: _createVerified,
          status: _createStatus,
        ),
        onSuccess: (_) async {
          if (!mounted || !sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
          _resetCreateForm();
          await _load();
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _updateDriver(Map<String, dynamic> driver) async {
    if (!(_editFormKey.currentState?.validate() ?? false)) return;

    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final driverId = driver['_id']?.toString();
    if (driverId == null || driverId.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Saving driver profile...',
        successMessage: 'Driver profile updated successfully.',
        action: () => admin.updateDriver(
          driverId: driverId,
          licenseNumber: _nullableText(_editLicenseCtrl.text),
          employeeNumber: _nullableText(_editEmployeeCtrl.text),
          phone: _nullableText(_editPhoneCtrl.text),
          isVerified: _verifiedSelection.value,
          assignedRouteId: _routeSelection.value,
          status: _statusSelection.value,
          jeepneyPlateNumber: _editJeepneyPlateCtrl.text.trim(),
          jeepneyCapacity: int.tryParse(_editJeepneyCapacityCtrl.text.trim()),
        ),
        onSuccess: (_) async {
          if (!mounted) return;
          Navigator.of(context).pop();
          await _load();
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  int _driverGridColumns(double maxWidth) {
    final columns = (maxWidth / 320).floor();
    return columns.clamp(1, 5);
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final userName = _driverDisplayName(driver);
    final userEmail = _driverEmail(driver);
    final status = _textOf(driver['status']).toLowerCase();
    final isVerified = driver['isVerified'] == true;
    final license = _textOf(driver['licenseNumber']);
    final employee = _textOf(driver['employeeNumber']);
    final phone = _textOf(driver['phone']);
    final routeData = _driverRoute(driver);
    final routeText = routeData.isEmpty
        ? 'Unassigned route'
        : '${routeData['code'] ?? ''} ${routeData['name']}'.trim();
    final jeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
    final driverId = _idOf(driver['_id']);
    final openTrip = _openTripForDriver(driverId);
    final scheduleBlockReason = _scheduleTripBlockReason(driver);
    final schedulingThisDriver = _schedulingDriverId == driverId;
    final jeepneyPlate =
        jeepney?['plateNumber']?.toString() ?? 'No jeepney assigned';
    final jeepneyCapacity = jeepney?['capacity']?.toString() ?? '';
    final compactButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final compactTextButtonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    Widget infoLine(String label, String value, {TextStyle? style}) {
      return Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              userName.isEmpty ? 'Driver account' : userName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (userEmail.isNotEmpty)
              Text(
                userEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(
                  label: 'status: ${_statusLabel(status)}',
                  color: status == 'active' ? Colors.green : Colors.orange,
                ),
                _Badge(
                  label: isVerified ? 'verified' : 'not verified',
                  color: isVerified ? Colors.blue : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (license.isNotEmpty) infoLine('License', license),
            if (employee.isNotEmpty) infoLine('Employee', employee),
            if (phone.isNotEmpty) infoLine('Phone', phone),
            infoLine('Route', routeText),
            infoLine('Jeepney plate', jeepneyPlate),
            if (jeepneyCapacity.isNotEmpty)
              infoLine('Capacity', jeepneyCapacity),
            const SizedBox(height: 6),
            infoLine(
              'Trip status',
              openTrip == null
                  ? 'No scheduled trip'
                  : _statusLabel(openTrip.status),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (scheduleBlockReason != null) ...[
              const SizedBox(height: 6),
              Text(
                scheduleBlockReason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: schedulingThisDriver || scheduleBlockReason != null
                      ? null
                      : () => _scheduleTrip(driver),
                  style: compactButtonStyle,
                  icon: schedulingThisDriver
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check_circle_outlined),
                  label: Text(
                    schedulingThisDriver
                        ? 'Scheduling...'
                        : openTrip == null
                            ? 'Schedule trip'
                            : 'Trip ready',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openEditSheet(driver),
                  style: compactTextButtonStyle,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit driver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchCtrl.text.trim().toLowerCase();
    final drivers = _drivers
        .whereType<Map<String, dynamic>>()
        .where(
          (driver) =>
              _matchesStatusFilter(driver) &&
              _matchesDriverSearch(driver, searchQuery),
        )
        .toList(growable: false);
    final allDrivers = _drivers.whereType<Map<String, dynamic>>().toList();
    final activeCount = allDrivers
        .where((driver) => _textOf(driver['status']).toLowerCase() == 'active')
        .length;
    final verifiedCount =
        allDrivers.where((driver) => driver['isVerified'] == true).length;
    final unassignedCount = allDrivers
        .where((driver) => _nullableIdOf(driver['assignedRouteId']) == null)
        .length;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        children: [
          if (widget.embedded) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _openCreateSheet,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create driver'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                      _DriverMetricChip(
                        label: 'Total',
                        value: allDrivers.length.toString(),
                      ),
                      _DriverMetricChip(
                        label: 'Active',
                        value: activeCount.toString(),
                      ),
                      _DriverMetricChip(
                        label: 'Verified',
                        value: verifiedCount.toString(),
                      ),
                      _DriverMetricChip(
                        label: 'Unassigned',
                        value: unassignedCount.toString(),
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
                          labelText: 'Search driver, email, route, or plate',
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
                            child: Text('All drivers'),
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
                            value: 'verified',
                            child: Text('Verified only'),
                          ),
                          DropdownMenuItem(
                            value: 'unassigned',
                            child: Text('No route assigned'),
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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F6A5F),
                  Color(0xFF2157A5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver Management',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Each driver owns one jeepney. Create both records together and update them from one admin screen.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver accounts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${drivers.length} registered driver${drivers.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.badge_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading && drivers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (drivers.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                allDrivers.isEmpty
                    ? 'No drivers found yet. Use the "Create driver" button below to add the first driver account.'
                    : 'No drivers match the current search or filter.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final columns = _driverGridColumns(constraints.maxWidth);
                final cardWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final driver in drivers)
                      SizedBox(
                        width: cardWidth,
                        child: _buildDriverCard(driver),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _openCreateSheet,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Create driver'),
      ),
      body: body,
    );
  }
}

class _DriverMetricChip extends StatelessWidget {
  const _DriverMetricChip({
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
