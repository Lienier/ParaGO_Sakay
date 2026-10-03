import '../../widgets/legal_pages.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/driver_service.dart';
import '../../services/session_controller.dart';
import '../../core/utils/driver_error_message.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _documents = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service =
          DriverService(context.read<SessionController>().apiClient);
      final results = await Future.wait([
        service.getProfile(useCache: false),
        service.getLicenseDocuments(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0];
        _documents = results[1];
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = DriverErrorMessage.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  Widget _detail(String label, dynamic value) {
    final text = _text(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(text.isEmpty ? 'Not provided' : text),
        ],
      ),
    );
  }

  Widget _document(String side) {
    final data = _documents[side];
    final map = data is Map<String, dynamic> ? data : null;
    final url = _text(map?['url']);
    final label = side == 'front' ? 'License front' : 'License back';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          if (url.isEmpty)
            const SizedBox(
              height: 120,
              child: Center(child: Text('Document not available')),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                width: double.infinity,
                height: 220,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 120,
                  child: Center(
                      child: Text('Image link expired. Refresh to retry.')),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _profile['userId'];
    final userMap = user is Map<String, dynamic> ? user : <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('Account',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _detail('Full name', userMap['fullName']),
                  _detail('Email', userMap['email']),
                  _detail('Phone', _profile['phone'] ?? userMap['phone']),
                  _detail('License number', _profile['licenseNumber']),
                  _detail('Employee number', _profile['employeeNumber']),
                  const SizedBox(height: 8),
                  Text(
                    'Driver license documents',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _document('front'),
                  const SizedBox(height: 12),
                  _document('back'),
                  const SizedBox(height: 16),
                  const LegalLinks(),
                ],
              ),
            ),
    );
  }
}
