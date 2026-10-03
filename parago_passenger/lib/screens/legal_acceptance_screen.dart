import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_controller.dart';
import '../widgets/legal_pages.dart';

class LegalAcceptanceScreen extends StatefulWidget {
  const LegalAcceptanceScreen({super.key});

  @override
  State<LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends State<LegalAcceptanceScreen> {
  bool _accepted = false;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    if (!_accepted) {
      setState(() => _error = 'Accept both policies to continue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().acceptLegalPolicies();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Policies could not be saved. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Review required')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.fact_check_outlined, size: 52),
          const SizedBox(height: 16),
          Text('Before you continue',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          const Text(
              'Please read and accept the Terms & Conditions and Privacy Policy once for this account.'),
          const SizedBox(height: 18),
          const LegalLinks(),
          CheckboxListTile(
            value: _accepted,
            onChanged: _saving
                ? null
                : (value) => setState(() => _accepted = value == true),
            title: const Text('I have read and accept both policies.'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: _saving ? null : _continue,
            child: Text(_saving ? 'Saving...' : 'Accept and continue'),
          ),
          TextButton(
              onPressed: _saving ? null : session.logout,
              child: const Text('Sign out')),
        ]),
      ),
    );
  }
}
