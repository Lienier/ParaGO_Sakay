import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_controller.dart';

class CodingHolidaysDialog extends StatefulWidget {
  const CodingHolidaysDialog({super.key});
  @override
  State<CodingHolidaysDialog> createState() => _CodingHolidaysDialogState();
}
class _CodingHolidaysDialogState extends State<CodingHolidaysDialog> {
  final _date = TextEditingController();
  final _name = TextEditingController();
  List<dynamic> _items = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  @override
  void dispose() { _date.dispose(); _name.dispose(); super.dispose(); }
  Future<void> _load({String? method, String? date}) async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = context.read<SessionController>().apiClient;
      if (method != null) {
        await api.request(method: method, path: '/admin/coding-holidays/${Uri.encodeComponent(date!)}',
          body: method == 'PUT' ? {'name': _name.text.trim()} : null, useCache: false);
      }
      final response = await api.request(method: 'GET', path: '/admin/coding-holidays', useCache: false);
      if (mounted) setState(() { _items = response['data'] as List? ?? []; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to save or load holidays. Check the date and name, then retry.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Coding holidays'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('No coding on weekends or these Philippine calendar dates. Mon: 1–2; Tue: 3–4; Wed: 5–6; Thu: 7–8; Fri: 9–0.'),
      TextField(controller: _date, enabled: !_busy, decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
      TextField(controller: _name, enabled: !_busy, maxLength: 120, decoration: const InputDecoration(labelText: 'Holiday name')),
      FilledButton(onPressed: _busy ? null : () => _load(method: 'PUT', date: _date.text.trim()), child: const Text('Save holiday')),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      for (final item in _items) ListTile(title: Text('${item['date']} — ${item['name']}'),
        trailing: TextButton(onPressed: _busy ? null : () => _load(method: 'DELETE', date: item['date'].toString()), child: const Text('Remove'))),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}
