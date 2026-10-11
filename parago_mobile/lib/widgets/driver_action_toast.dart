import 'glass_surface.dart';
import 'package:flutter/material.dart';

class DriverToastAction {
  const DriverToastAction(
      {required this.id,
      required this.title,
      required this.detail,
      required this.label,
      required this.run});
  final String id, title, detail, label;
  final Future<void> Function() run;
}

/// A persistent actionable toast. Refreshes never change the selected action
/// under a driver's finger; unresolved actions remain available when minimized.
class DriverActionToast extends StatefulWidget {
  const DriverActionToast({super.key, required this.actions});
  final List<DriverToastAction> actions;
  @override
  State<DriverActionToast> createState() => _DriverActionToastState();
}

class _DriverActionToastState extends State<DriverActionToast> {
  String? _selected, _error;
  bool _busy = false, _collapsed = false;

  @override
  void didUpdateWidget(covariant DriverActionToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.actions
        .any((a) => !oldWidget.actions.any((b) => b.id == a.id))) {
      _collapsed = false;
    }
    if (!widget.actions.any((a) => a.id == _selected)) {
      _selected = null;
      _error = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return const SizedBox.shrink();
    final index = widget.actions.indexWhere((a) => a.id == _selected);
    final action = widget.actions[index < 0 ? 0 : index];
    _selected = action.id;
    return GlassSurface(
      child: Builder(
          builder: (context) => Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                '${widget.actions.length} driver actions',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))),
                        IconButton(
                            tooltip: _collapsed
                                ? 'Show actions'
                                : 'Minimize actions',
                            onPressed: _busy
                                ? null
                                : () =>
                                    setState(() => _collapsed = !_collapsed),
                            icon: Icon(_collapsed
                                ? Icons.expand_more
                                : Icons.expand_less)),
                      ]),
                      if (!_collapsed) ...[
                        Text(action.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(action.detail,
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        if (_error != null)
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        Wrap(spacing: 8, children: [
                          FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      setState(() {
                                        _busy = true;
                                        _error = null;
                                      });
                                      try {
                                        await action.run();
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                              () => _error = error.toString());
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _busy = false);
                                        }
                                      }
                                    },
                              child: Text(_busy ? 'Working...' : action.label)),
                          if (widget.actions.length > 1)
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _selected = widget
                                              .actions[
                                                  ((index < 0 ? 0 : index) +
                                                          1) %
                                                      widget.actions.length]
                                              .id;
                                          _error = null;
                                        }),
                                child: const Text('Next action')),
                        ]),
                      ],
                    ]),
              )),
    );
  }
}
