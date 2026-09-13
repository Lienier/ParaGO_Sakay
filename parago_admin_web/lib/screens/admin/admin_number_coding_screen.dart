import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/session_controller.dart';
import '../../widgets/app_card.dart';
import '../../widgets/operations_panel.dart';

class AdminNumberCodingScreen extends StatefulWidget {
  const AdminNumberCodingScreen({super.key});
  @override
  State<AdminNumberCodingScreen> createState() =>
      _AdminNumberCodingScreenState();
}

class _AdminNumberCodingScreenState extends State<AdminNumberCodingScreen> {
  final _date = TextEditingController();
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<dynamic> _items = [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load({String? method, String? date}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    bool changed = false;
    try {
      final api = context.read<SessionController>().apiClient;
      if (method != null) {
        await api.request(
            method: method,
            path: '/admin/coding-holidays/${Uri.encodeComponent(date!)}',
            body: method == 'PUT' ? {'name': _name.text.trim()} : null,
            useCache: false);
        changed = true;
      }
      final response = await api.request(
          method: 'GET', path: '/admin/coding-holidays', useCache: false);
      if (!mounted) return;
      setState(() {
        _items = response['data'] as List? ?? [];
        _loaded = true;
        if (changed) {
          _notice = method == 'PUT'
              ? 'Holiday exemption saved.'
              : 'Holiday exemption removed.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = changed
              ? 'The change was saved, but the list could not be refreshed. Refresh to see the latest exemptions.'
              : method == null
                  ? 'Holiday exemptions could not be loaded. Please retry.'
                  : 'The change could not be confirmed. Refresh the list before trying again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Remove holiday exemption?'),
              content: Text(
                  '${item['name']} (${item['date']}) will no longer be exempt from weekday number coding.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove')),
              ],
            ));
    if (confirmed == true && mounted) {
      await _load(method: 'DELETE', date: item['date'].toString());
    }
  }

  String? _validateDate(String? value) {
    final text = (value ?? '').trim();
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != text) {
      return 'Enter a valid date as YYYY-MM-DD.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const AppPageHeader(
              title: 'Number Coding',
              subtitle:
                  'Review plate restrictions and manage holiday exemptions.'),
          const SizedBox(height: 24),
          OperationsPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const AppSectionHeader(
                    title: 'Weekly restrictions',
                    subtitle:
                        'Restricted plate endings by weekday. Philippine local dates apply.'),
                const SizedBox(height: 16),
                for (final entry in const {
                  'Monday': '1 and 2',
                  'Tuesday': '3 and 4',
                  'Wednesday': '5 and 6',
                  'Thursday': '7 and 8',
                  'Friday': '9 and 0'
                }.entries)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(child: Text(entry.key)),
                        Text(entry.value,
                            style: Theme.of(context).textTheme.titleSmall),
                      ])),
                const Divider(height: 24),
                const Text(
                    'No number coding on weekends or the holiday dates listed below.'),
              ])),
          const SizedBox(height: 20),
          OperationsPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const AppSectionHeader(
                    title: 'Holiday exemptions',
                    subtitle:
                        'Add a holiday date when weekday restrictions do not apply.'),
                const SizedBox(height: 20),
                Form(
                    key: _form,
                    child: Column(children: [
                      TextFormField(
                          controller: _date,
                          enabled: !_busy,
                          validator: _validateDate,
                          decoration: const InputDecoration(
                              labelText: 'Date (YYYY-MM-DD)',
                              hintText: '2026-12-25')),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          maxLength: 120,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter the holiday name.'
                              : null,
                          decoration:
                              const InputDecoration(labelText: 'Holiday name')),
                    ])),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (_form.currentState!.validate()) {
                                _load(method: 'PUT', date: _date.text.trim());
                              }
                            },
                      child: const Text('Save exemption')),
                  OutlinedButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Refresh exemptions')),
                ]),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  AppInfoBanner(message: _error!, warning: true),
                if (_notice != null) Text(_notice!, semanticsLabel: _notice),
                if (!_busy && _loaded && _items.isEmpty)
                  const AppEmptyState(
                      title: 'No holiday exemptions',
                      message:
                          'Weekday restrictions apply unless a holiday is added.'),
                for (final item in _items) ...[
                  const Divider(height: 24),
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${item['name']}',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text('${item['date']}'),
                        ])),
                    TextButton(
                        onPressed: _busy ? null : () => _remove(item as Map),
                        child: const Text('Remove')),
                  ]),
                ],
              ])),
        ],
      );
}
