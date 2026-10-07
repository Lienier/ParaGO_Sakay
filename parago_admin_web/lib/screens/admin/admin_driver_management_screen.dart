import '../../widgets/operations_panel.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/utils/action_feedback.dart';
import '../../models/transport/route_summary.dart';
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
  static const Duration _presenceRefreshInterval = Duration(seconds: 30);
  static const int _driversPerPage = 10;

  final _createFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _licenseImagePicker = ImagePicker();

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

  List<dynamic> _drivers = [];
  List<RouteSummaryModel> _routes = [];

  Timer? _presenceRefreshTimer;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String _statusFilter = 'all';
  int _driverPageIndex = 0;

  String? _createEmail;
  String? _createPassword;
  String? _createFullName;
  String? _createLicense;
  String? _createEmployee;
  String? _createPhone;
  String? _createRouteId;
  String? _createJeepneyPlateNumber;
  String? _createJeepneyCapacity;
  String _createStatus = 'active';
  _SelectedLicenseImage? _createLicenseFront;
  _SelectedLicenseImage? _createLicenseBack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _startPresenceRefreshLoop();
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
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
    final accountStatus = _accountStatusOf(driver);
    final presenceStatus = _presenceStatusOf(driver);
    switch (_statusFilter) {
      case 'online':
        return presenceStatus == 'online';
      case 'offline':
        return presenceStatus == 'offline';
      case 'account_active':
        return accountStatus == 'active';
      case 'account_suspended':
        return accountStatus == 'suspended';
      case 'account_deactivated':
        return accountStatus == 'deactivated';
      case 'unassigned':
        return _nullableIdOf(driver['assignedRouteId']) == null;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filteredDrivers {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _drivers
        .whereType<Map<String, dynamic>>()
        .where((driver) =>
            _matchesStatusFilter(driver) && _matchesDriverSearch(driver, query))
        .toList(growable: false);
  }

  String _accountStatusOf(Map<String, dynamic> driver) {
    final direct = _textOf(driver['accountStatus']).toLowerCase();
    if (direct.isNotEmpty) return direct;
    final user = driver['userId'];
    if (user is Map<String, dynamic>) {
      final nested = _textOf(user['status']).toLowerCase();
      if (nested.isNotEmpty) return nested;
    }
    return 'unknown';
  }

  String _presenceStatusOf(Map<String, dynamic> driver) {
    final direct = _textOf(driver['presenceStatus']).toLowerCase();
    if (direct == 'online' || direct == 'offline') {
      return direct;
    }
    final legacy = _textOf(driver['status']).toLowerCase();
    if (legacy == 'active') return 'online';
    return 'offline';
  }

  void _startPresenceRefreshLoop() {
    _presenceRefreshTimer?.cancel();
    _presenceRefreshTimer = Timer.periodic(_presenceRefreshInterval, (_) {
      if (!mounted || _loading) {
        return;
      }
      _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait<dynamic>([
        admin.getDrivers(),
        routeService.getRoutes(),
      ]);

      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<dynamic>;
        _routes = results[1] as List<RouteSummaryModel>;
        final lastPage = (_filteredDrivers.length - 1) ~/ _driversPerPage;
        _driverPageIndex =
            _driverPageIndex.clamp(0, lastPage < 0 ? 0 : lastPage).toInt();
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
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
    _createStatus = 'active';
    _createLicenseFront = null;
    _createLicenseBack = null;
    _createLicenseCtrl.clear();
    _createEmployeeCtrl.clear();
    _createPhoneCtrl.clear();
    _createJeepneyPlateCtrl.clear();
    _createJeepneyCapacityCtrl.clear();
  }

  Future<_SelectedLicenseImage?> _pickLicenseImage() async {
    final file =
        await _licenseImagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Each credential image must be 5 MB or smaller.')),
        );
      }
      return null;
    }
    final lowerName = file.name.toLowerCase();
    final mimeType = file.mimeType ??
        (lowerName.endsWith('.png') ? 'image/png' : 'image/jpeg');
    if (mimeType != 'image/jpeg' && mimeType != 'image/png') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a JPEG or PNG image.')),
        );
      }
      return null;
    }
    return _SelectedLicenseImage(
      bytes: bytes,
      filename: file.name,
      mimeType: mimeType,
    );
  }

  Future<void> _createDriver(BuildContext sheetContext) async {
    if (_saving) return;
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
          licenseFront: _createLicenseFront!.toUpload(),
          licenseBack: _createLicenseBack!.toUpload(),
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

  Future<void> _addDriverToTerminal(Map<String, dynamic> driver) async {
    if (_saving) return;
    final driverId = driver['_id']?.toString();
    if (driverId == null || driverId.isEmpty) return;
    final jeepney = driver['assignedJeepneyId'];
    final jeepneyId = _nullableIdOf(jeepney);
    final routeId = _routeSelection.value ?? _nullableIdOf(driver['assignedRouteId']);
    if (jeepneyId == null || routeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assign an active route and jeepney first.')),
      );
      return;
    }
    final admin = AdminService(context.read<SessionController>().apiClient);
    setState(() => _saving = true);
    try {
      await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Adding driver to terminal arrival...',
        successMessage: 'Driver is now awaiting terminal arrival.',
        action: () => admin.createTerminalIntent(
          driverId: driverId,
          routeId: routeId,
          jeepneyId: jeepneyId,
        ),
        onSuccess: (_) async {
          if (!mounted) return;
          Navigator.of(context).pop();
          await _load();
          widget.onChanged?.call();
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drivers = _filteredDrivers;
    final pageCount = (drivers.length / _driversPerPage).ceil();
    final pageDrivers = drivers
        .skip(_driverPageIndex * _driversPerPage)
        .take(_driversPerPage)
        .toList(growable: false);
    final allDrivers = _drivers.whereType<Map<String, dynamic>>().toList();
    final onlineCount = allDrivers
        .where((driver) => _presenceStatusOf(driver) == 'online')
        .length;
    final activeAccountCount = allDrivers
        .where((driver) => _accountStatusOf(driver) == 'active')
        .length;
    final unassignedCount = allDrivers
        .where((driver) => _nullableIdOf(driver['assignedRouteId']) == null)
        .length;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          if (widget.embedded) ...[
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _loading ? null : _openCreateSheet,
                child: const Text('Create driver'),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                      _DriverMetricChip(
                        label: 'Total',
                        value: allDrivers.length.toString(),
                      ),
                      _DriverMetricChip(
                        label: 'Online',
                        value: onlineCount.toString(),
                      ),
                      _DriverMetricChip(
                        label: 'Active accounts',
                        value: activeAccountCount.toString(),
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
                        onChanged: (_) => setState(() => _driverPageIndex = 0),
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
                            value: 'online',
                            child: Text('Online only'),
                          ),
                          DropdownMenuItem(
                            value: 'offline',
                            child: Text('Offline only'),
                          ),
                          DropdownMenuItem(
                            value: 'account_active',
                            child: Text('Active accounts'),
                          ),
                          DropdownMenuItem(
                            value: 'account_deactivated',
                            child: Text('Deactivated accounts'),
                          ),
                          DropdownMenuItem(
                            value: 'unassigned',
                            child: Text('No route assigned'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value ?? 'all';
                            _driverPageIndex = 0;
                          });
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
          const SizedBox(height: 14),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
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
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDCE3EB)),
              borderRadius: BorderRadius.circular(8),
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
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                allDrivers.isEmpty
                    ? 'No drivers found yet. Use the "Create driver" button to add the first driver account.'
                    : 'No drivers match the current search or filter.',
              ),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowHeight: 44,
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 64,
                      columnSpacing: 28,
                      horizontalMargin: 16,
                      columns: const [
                        DataColumn(label: Text('Driver')),
                        DataColumn(label: Text('Route')),
                        DataColumn(label: Text('Jeepney')),
                        DataColumn(label: Text('Account')),
                        DataColumn(label: Text('Actions'))
                      ],
                      rows: [
                        for (final driver in pageDrivers)
                          DataRow(cells: [
                            DataCell(Text(_driverDisplayName(driver))),
                            DataCell(Text(
                                _driverRoute(driver)['name']?.toString() ??
                                    'Unassigned')),
                            DataCell(Text((driver['assignedJeepneyId'] as Map<
                                        String, dynamic>?)?['plateNumber']
                                    ?.toString() ??
                                'Unassigned')),
                            DataCell(
                                Text(_statusLabel(_accountStatusOf(driver)))),
                            DataCell(TextButton(
                                onPressed: () => _openEditSheet(driver),
                                child: const Text('View details'))),
                          ])
                      ],
                    )),
              );
            }),
          if (drivers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                    'Showing ${_driverPageIndex * _driversPerPage + 1}–${_driverPageIndex * _driversPerPage + pageDrivers.length} of ${drivers.length} drivers'),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _driverPageIndex > 0
                          ? () => setState(() => _driverPageIndex--)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Page ${_driverPageIndex + 1} of $pageCount'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _driverPageIndex + 1 < pageCount
                          ? () => setState(() => _driverPageIndex++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Management'),
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

class _SelectedLicenseImage {
  const _SelectedLicenseImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;

  LicenseImageUpload toUpload() => LicenseImageUpload(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
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
        color: const Color(0xFFF5F6F7),
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
