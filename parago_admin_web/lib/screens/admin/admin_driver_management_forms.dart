part of 'admin_driver_management_screen.dart';

extension _AdminDriverManagementForms on _AdminDriverManagementScreenState {
  Future<void> _openCreateSheet() async {
    _resetCreateForm();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var dialogSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final narrow = MediaQuery.sizeOf(context).width < 600;
            final form = Form(
              key: _createFormKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Create driver account',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: dialogSaving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    'Fields marked * are required.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Email *'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createEmail = value,
                    validator: (value) =>
                        _textOf(value).isEmpty ? 'Email is required' : null,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password *'),
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
                    decoration: const InputDecoration(labelText: 'Full name *'),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createFullName = value,
                    validator: (value) =>
                        _textOf(value).isEmpty ? 'Full name is required' : null,
                  ),
                  TextFormField(
                    controller: _createLicenseCtrl,
                    decoration: const InputDecoration(
                      labelText: 'License number *',
                    ),
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createLicense = value,
                    validator: (value) => _textOf(value).isEmpty
                        ? 'License number is required'
                        : null,
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
                    decoration: const InputDecoration(labelText: 'Phone *'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onSaved: (value) => _createPhone = value,
                    validator: (value) =>
                        _textOf(value).isEmpty ? 'Phone is required' : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Driver license',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload clear JPEG or PNG images up to 5 MB each.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  FormField<_SelectedLicenseImage>(
                    validator: (value) => value == null
                        ? 'License front image is required'
                        : null,
                    builder: (field) => _LicenseImageField(
                      label: 'License front *',
                      image: _createLicenseFront,
                      errorText: field.errorText,
                      onSelect: () async {
                        final selected = await _pickLicenseImage();
                        if (selected == null || !dialogContext.mounted) return;
                        setDialogState(() {
                          _createLicenseFront = selected;
                          field.didChange(selected);
                        });
                      },
                      onRemove: _createLicenseFront == null
                          ? null
                          : () => setDialogState(() {
                                _createLicenseFront = null;
                                field.didChange(null);
                              }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FormField<_SelectedLicenseImage>(
                    validator: (value) =>
                        value == null ? 'License back image is required' : null,
                    builder: (field) => _LicenseImageField(
                      label: 'License back *',
                      image: _createLicenseBack,
                      errorText: field.errorText,
                      onSelect: () async {
                        final selected = await _pickLicenseImage();
                        if (selected == null || !dialogContext.mounted) return;
                        setDialogState(() {
                          _createLicenseBack = selected;
                          field.didChange(selected);
                        });
                      },
                      onRemove: _createLicenseBack == null
                          ? null
                          : () => setDialogState(() {
                                _createLicenseBack = null;
                                field.didChange(null);
                              }),
                    ),
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
                        const InputDecoration(labelText: 'Plate number *'),
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
                    decoration: const InputDecoration(labelText: 'Capacity *'),
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
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: dialogSaving
                        ? null
                        : () async {
                            if (!(_createFormKey.currentState?.validate() ??
                                false)) {
                              return;
                            }
                            setDialogState(() => dialogSaving = true);
                            await _createDriver(dialogContext);
                            if (dialogContext.mounted) {
                              setDialogState(() => dialogSaving = false);
                            }
                          },
                    child: dialogSaving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Uploading...'),
                            ],
                          )
                        : const Text('Create driver'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
            if (narrow) {
              return Dialog.fullscreen(child: SafeArea(child: form));
            }
            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.9,
                ),
                child: form,
              ),
            );
          },
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
    final driverId = driver['_id']?.toString() ?? '';
    final admin = AdminService(context.read<SessionController>().apiClient);
    _statusSelection.value = switch (accountStatus) {
      'suspended' => 'suspended',
      'deactivated' => 'deactivated',
      _ => 'active',
    };

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
                _StoredLicenseDocumentsPanel(
                  driverId: driverId,
                  admin: admin,
                  pickImage: _pickLicenseImage,
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

class _LicenseImageField extends StatelessWidget {
  const _LicenseImageField({
    required this.label,
    required this.image,
    required this.onSelect,
    this.onRemove,
    this.errorText,
  });

  final String label;
  final _SelectedLicenseImage? image;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final borderColor = errorText == null
        ? Theme.of(context).colorScheme.outlineVariant
        : Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              if (image == null)
                OutlinedButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose image'),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    image!.bytes,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  image!.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Replace'),
                    ),
                    IconButton(
                      tooltip: 'Remove image',
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StoredLicenseDocumentsPanel extends StatefulWidget {
  const _StoredLicenseDocumentsPanel({
    required this.driverId,
    required this.admin,
    required this.pickImage,
  });

  final String driverId;
  final AdminService admin;
  final Future<_SelectedLicenseImage?> Function() pickImage;

  @override
  State<_StoredLicenseDocumentsPanel> createState() =>
      _StoredLicenseDocumentsPanelState();
}

class _StoredLicenseDocumentsPanelState
    extends State<_StoredLicenseDocumentsPanel> {
  late Future<Map<String, dynamic>> _documents;
  String? _replacingSide;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _documents = widget.admin.getDriverLicenseDocuments(widget.driverId);
  }

  Future<void> _replace(String side) async {
    final selected = await widget.pickImage();
    if (selected == null || !mounted) return;
    setState(() => _replacingSide = side);
    try {
      await ActionFeedback.run<Map<String, dynamic>>(
        context: context,
        loadingMessage: 'Uploading license $side image...',
        successMessage: 'License $side image updated.',
        action: () => widget.admin.replaceDriverLicenseDocument(
          driverId: widget.driverId,
          side: side,
          image: selected.toUpload(),
        ),
        onSuccess: (_) async {
          if (!mounted) return;
          setState(_refresh);
        },
      );
    } finally {
      if (mounted) setState(() => _replacingSide = null);
    }
  }

  Widget _sideCard(String side, dynamic value) {
    final data = value is Map<String, dynamic> ? value : null;
    final url = data?['url']?.toString() ?? '';
    final title = side == 'front' ? 'License front' : 'License back';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (url.isEmpty)
            const SizedBox(
              height: 110,
              child: Center(child: Text('Document missing')),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                width: double.infinity,
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 110,
                  child: Center(
                      child: Text('Image link expired. Refresh to retry.')),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _replacingSide == null ? () => _replace(side) : null,
            icon: _replacingSide == side
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text(url.isEmpty ? 'Upload' : 'Replace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Driver license documents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh document links',
              onPressed: () => setState(_refresh),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _documents,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('Documents unavailable: ${snapshot.error}');
            }
            final documents = snapshot.data ?? <String, dynamic>{};
            return LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _sideCard('front', documents['front']),
                  _sideCard('back', documents['back']),
                ];
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [cards[0], const SizedBox(height: 10), cards[1]],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 10),
                    Expanded(child: cards[1]),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
