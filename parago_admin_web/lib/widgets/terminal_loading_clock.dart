import 'dart:async';
import 'package:flutter/material.dart';

int terminalSecondsRemaining(Map<String, dynamic>? summary, DateTime now) {
  final reported = (summary?['remainingSeconds'] as num?)?.toInt();
  final server = DateTime.tryParse(summary?['serverTime']?.toString() ?? '');
  final deadline =
      DateTime.tryParse(summary?['loadingDeadline']?.toString() ?? '');
  if (reported != null && server != null) {
    final age = now.difference(server).inSeconds.clamp(0, 86400);
    return (reported - age).clamp(0, 600);
  }
  if (deadline != null) return deadline.difference(now).inSeconds.clamp(0, 600);
  return (reported ?? 0).clamp(0, 600);
}

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
    _initial = terminalSecondsRemaining(widget.summary, DateTime.now());
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
    if (oldWidget.summary?['serverTime'] != widget.summary?['serverTime'] ||
        oldWidget.summary?['remainingSeconds'] !=
            widget.summary?['remainingSeconds'] ||
        oldWidget.summary?['loadingDeadline'] !=
            widget.summary?['loadingDeadline']) {
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
        ? 'Departure required — new terminal reservations are closed. Await departure confirmation.'
        : 'Loading: ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')} remaining${remaining <= 120 ? ' — prepare for departure' : ''}';
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
