import 'dart:async';
import 'package:flutter/material.dart';

class TerminalLoadingClock extends StatefulWidget {
  const TerminalLoadingClock({super.key, required this.summary});
  final Map<String, dynamic>? summary;
  @override
  State<TerminalLoadingClock> createState() => _TerminalLoadingClockState();
}

class _TerminalLoadingClockState extends State<TerminalLoadingClock> {
  Timer? _timer;
  final Stopwatch _elapsed = Stopwatch();
  int _initial = 0;
  void _sync() {
    _initial = (widget.summary?['remainingSeconds'] as num?)?.toInt() ?? 0;
    _elapsed
      ..reset()
      ..start();
  }

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TerminalLoadingClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary?['serverTime'] != widget.summary?['serverTime']) {
      _sync();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary?['loadingDeadline'] == null &&
        widget.summary?['departureRequired'] != true) {
      return const SizedBox.shrink();
    }
    final remaining = (_initial - _elapsed.elapsed.inSeconds).clamp(0, 600);
    final text = remaining == 0
        ? 'Loading closed'
        : 'Loading: ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: remaining <= 120
                    ? Theme.of(context).colorScheme.error
                    : null)));
  }
}
