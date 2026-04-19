part of 'admin_driver_management_screen.dart';

extension _AdminDriverManagementForms on _AdminDriverManagementScreenState {
  Future<void> _openCreateSheet() async {
    _resetCreateForm();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Form(
              key: _createFormKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createEmail = value,
                    validator: (value) =>
                        _textOf(value).isEmpty ? 'Email is required' : null,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
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
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createFullName = value,
                    validator: (value) =>
                        _textOf(value).isEmpty ? 'Full name is required' : null,
                  ),
                  TextFormField(
                    controller: _createLicenseCtrl,
                    decoration:
                        const InputDecoration(labelText: 'License number'),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createLicense = value,
                  ),
                  TextFormField(
                    controller: _createEmployeeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Employee number'),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createEmployee = value,
                  ),
                  TextFormField(
                    controller: _createPhoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
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
                    decoration:
                        const InputDecoration(labelText: 'Plate number'),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createJeepneyPlateNumber = value,
                    validator: (value) => _textOf(value).isEmpty
                        ? 'Plate number is required'
                        : null,
                  ),
                  TextFormField(
                    controller: _createJeepneyCapacityCtrl,
                    decoration: const InputDecoration(labelText: 'Capacity'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
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
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No route'),
                      ),
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
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspended'),
                      ),
                      DropdownMenuItem(
                        value: 'deactivated',
                        child: Text('Deactivated'),
                      ),
                    ],
                    onChanged: (value) => _createStatus = value ?? 'active',
                  ),
                  SwitchListTile(
                    value: _createVerified,
                    onChanged: (value) =>
                        modalSetState(() => _createVerified = value),
                    title: const Text('Verified'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed:
                        _saving ? null : () => _createDriver(sheetContext),
                    child: const Text('Create driver'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditSheet(Map<String, dynamic> driver) async {
    final assignedJeepney =
        driver['assignedJeepneyId'] as Map<String, dynamic>?;
    _editLicenseCtrl.text = driver['licenseNumber']?.toString() ?? '';
    _editEmployeeCtrl.text = driver['employeeNumber']?.toString() ?? '';
    _editPhoneCtrl.text = driver['phone']?.toString() ?? '';
    _editJeepneyPlateCtrl.text =
        assignedJeepney?['plateNumber']?.toString() ?? '';
    _editJeepneyCapacityCtrl.text =
        assignedJeepney?['capacity']?.toString() ?? '';

    final selectedRouteId = _nullableIdOf(driver['assignedRouteId']);
    _routeSelection.value = _hasRoute(selectedRouteId) ? selectedRouteId : null;
    final accountStatus = _accountStatusOf(driver);
    _statusSelection.value = switch (accountStatus) {
      'suspended' => 'suspended',
      'deactivated' => 'deactivated',
      _ => 'active',
    };
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              shrinkWrap: true,
              children: [
                Text(
                  'Update driver profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _editLicenseCtrl,
                  decoration:
                      const InputDecoration(labelText: 'License number'),
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                TextFormField(
                  controller: _editEmployeeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Employee number'),
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                TextFormField(
                  controller: _editPhoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
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
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  validator: (value) => _textOf(value).isEmpty
                      ? 'Plate number is required'
                      : null,
                ),
                TextFormField(
                  controller: _editJeepneyCapacityCtrl,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
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
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No route'),
                      ),
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
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspended'),
                      ),
                      DropdownMenuItem(
                        value: 'deactivated',
                        child: Text('Deactivated'),
                      ),
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
