import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transport/route_summary.dart';
import '../../services/admin_service.dart';
import '../../services/route_service.dart';
import '../../services/session_controller.dart';

class AdminDriverManagementScreen extends StatefulWidget {
  const AdminDriverManagementScreen({super.key});

  @override
  State<AdminDriverManagementScreen> createState() =>
      _AdminDriverManagementScreenState();
}

class _AdminDriverManagementScreenState
    extends State<AdminDriverManagementScreen> {
  final _createFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();

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

  bool _loading = false;
  bool _saving = false;
  String? _error;

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

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final admin = AdminService(session.apiClient);
    final routeService = RouteService(session.apiClient);

    setState(() => _loading = true);

    try {
      final results = await Future.wait<dynamic>([
        admin.getDrivers(),
        routeService.getRoutes(),
      ]);

      if (!mounted) return;
      setState(() {
        _drivers = results[0] as List<dynamic>;
        _routes = results[1] as List<RouteSummaryModel>;
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
      await admin.createDriverAccount(
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
      );
      if (!mounted) return;
      Navigator.of(sheetContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver and jeepney created')),
      );
      _resetCreateForm();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
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
      await admin.updateDriver(
        driverId: driverId,
        licenseNumber: _nullableText(_editLicenseCtrl.text),
        employeeNumber: _nullableText(_editEmployeeCtrl.text),
        phone: _nullableText(_editPhoneCtrl.text),
        isVerified: _verifiedSelection.value,
        assignedRouteId: _routeSelection.value,
        status: _statusSelection.value,
        jeepneyPlateNumber: _editJeepneyPlateCtrl.text.trim(),
        jeepneyCapacity: int.tryParse(_editJeepneyCapacityCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver profile updated')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openCreateSheet() async {
    _resetCreateForm();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Form(
            key: _createFormKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Create driver account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  onSaved: (value) => _createEmail = value,
                  validator: (value) =>
                      _textOf(value).isEmpty ? 'Email is required' : null,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  onSaved: (value) => _createPassword = value,
                  validator: (value) {
                    if (_textOf(value).length < 8) {
                      return 'Password must be at least 8 chars';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Full name'),
                  onSaved: (value) => _createFullName = value,
                  validator: (value) =>
                      _textOf(value).isEmpty ? 'Full name is required' : null,
                ),
                TextFormField(
                  controller: _createLicenseCtrl,
                  decoration: const InputDecoration(labelText: 'License number'),
                  onSaved: (value) => _createLicense = value,
                ),
                TextFormField(
                  controller: _createEmployeeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Employee number'),
                  onSaved: (value) => _createEmployee = value,
                ),
                TextFormField(
                  controller: _createPhoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  onSaved: (value) => _createPhone = value,
                ),
                const SizedBox(height: 16),
                Text(
                  'Jeepney details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _createJeepneyPlateCtrl,
                  decoration: const InputDecoration(labelText: 'Plate number'),
                  onSaved: (value) => _createJeepneyPlateNumber = value,
                  validator: (value) => _textOf(value).isEmpty
                      ? 'Plate number is required'
                      : null,
                ),
                TextFormField(
                  controller: _createJeepneyCapacityCtrl,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  onSaved: (value) => _createJeepneyCapacity = value,
                  validator: (value) {
                    final parsed = int.tryParse(_textOf(value));
                    if (parsed == null || parsed < 1) {
                      return 'Capacity must be a positive whole number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _createRouteId,
                  decoration:
                      const InputDecoration(labelText: 'Assigned route'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No route')),
                    ..._routes.map(
                      (route) => DropdownMenuItem(
                        value: route.id,
                        child: Text('${route.code} - ${route.name}'),
                      ),
                    ),
                  ],
                  onChanged: (value) => _createRouteId = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _createStatus,
                  decoration:
                      const InputDecoration(labelText: 'Account status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (value) => _createStatus = value ?? 'active',
                ),
                SwitchListTile(
                  value: _createVerified,
                  onChanged: (value) => setState(() => _createVerified = value),
                  title: const Text('Verified'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saving ? null : () => _createDriver(sheetContext),
                  child: const Text('Create driver'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditSheet(Map<String, dynamic> driver) async {
    final assignedJeepney = driver['assignedJeepneyId'] as Map<String, dynamic>?;
    _editLicenseCtrl.text = driver['licenseNumber']?.toString() ?? '';
    _editEmployeeCtrl.text = driver['employeeNumber']?.toString() ?? '';
    _editPhoneCtrl.text = driver['phone']?.toString() ?? '';
    _editJeepneyPlateCtrl.text =
        assignedJeepney?['plateNumber']?.toString() ?? '';
    _editJeepneyCapacityCtrl.text =
        assignedJeepney?['capacity']?.toString() ?? '';

    final selectedRouteId = _nullableIdOf(driver['assignedRouteId']);
    _routeSelection.value =
        _hasRoute(selectedRouteId) ? selectedRouteId : null;
    _statusSelection.value =
        _textOf(driver['status']).toLowerCase() == 'inactive'
            ? 'inactive'
            : 'active';
    _verifiedSelection.value = driver['isVerified'] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Form(
            key: _editFormKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Update driver profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _editLicenseCtrl,
                  decoration: const InputDecoration(labelText: 'License number'),
                ),
                TextFormField(
                  controller: _editEmployeeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Employee number'),
                ),
                TextFormField(
                  controller: _editPhoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                Text(
                  'Jeepney details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _editJeepneyPlateCtrl,
                  decoration: const InputDecoration(labelText: 'Plate number'),
                  validator: (value) => _textOf(value).isEmpty
                      ? 'Plate number is required'
                      : null,
                ),
                TextFormField(
                  controller: _editJeepneyCapacityCtrl,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(_textOf(value));
                    if (parsed == null || parsed < 1) {
                      return 'Capacity must be a positive whole number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<String?>(
                  valueListenable: _routeSelection,
                  builder: (_, selectedRoute, __) =>
                      DropdownButtonFormField<String?>(
                    initialValue: selectedRoute,
                    decoration:
                        const InputDecoration(labelText: 'Assigned route'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No route')),
                      ..._routes.map(
                        (route) => DropdownMenuItem(
                          value: route.id,
                          child: Text('${route.code} - ${route.name}'),
                        ),
                      ),
                    ],
                    onChanged: (value) => _routeSelection.value = value,
                  ),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: _statusSelection,
                  builder: (_, status, __) => DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration:
                        const InputDecoration(labelText: 'Account status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (value) =>
                        _statusSelection.value = value ?? 'active',
                  ),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<bool>(
                  valueListenable: _verifiedSelection,
                  builder: (_, isChecked, __) => SwitchListTile(
                    value: isChecked,
                    onChanged: (value) => _verifiedSelection.value = value,
                    title: const Text('Verified'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : () => _updateDriver(driver),
                  child: const Text('Save changes'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final drivers = _drivers;

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
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          children: [
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
                child: const Text(
                  'No drivers found yet. Use the "Create driver" button below to add the first driver account.',
                ),
              )
            else
              ...drivers.map((entry) {
                if (entry is! Map<String, dynamic>) {
                  return const SizedBox.shrink();
                }

                final driver = entry;
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
                final jeepney =
                    driver['assignedJeepneyId'] as Map<String, dynamic>?;
                final jeepneyPlate =
                    jeepney?['plateNumber']?.toString() ?? 'No jeepney assigned';
                final jeepneyCapacity = jeepney?['capacity']?.toString() ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName.isEmpty ? 'Driver account' : userName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (userEmail.isNotEmpty)
                          Text(userEmail, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _Badge(
                              label: 'status: ${_statusLabel(status)}',
                              color: status == 'active'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            _Badge(
                              label: isVerified ? 'verified' : 'not verified',
                              color: isVerified ? Colors.blue : Colors.grey,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (license.isNotEmpty) Text('License: $license'),
                        if (employee.isNotEmpty) Text('Employee: $employee'),
                        if (phone.isNotEmpty) Text('Phone: $phone'),
                        Text('Route: $routeText'),
                        Text('Jeepney plate: $jeepneyPlate'),
                        if (jeepneyCapacity.isNotEmpty)
                          Text('Capacity: $jeepneyCapacity'),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _openEditSheet(driver),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit driver'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
