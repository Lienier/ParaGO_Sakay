import 'dart:math' as math;
import 'package:flutter/material.dart';

class WalkInControls extends StatelessWidget {
  const WalkInControls(
      {super.key,
      required this.enabled,
      required this.manualCount,
      required this.displayedOnboard,
      required this.capacity,
      required this.onAdjust});
  final bool enabled;
  final int manualCount, displayedOnboard;
  final int? capacity;
  final void Function(int delta)? onAdjust;

  bool _canApply(int delta) =>
      enabled &&
      onAdjust != null &&
      manualCount + delta >= 0 &&
      (delta < 0 ||
          capacity == null ||
          capacity! <= 0 ||
          displayedOnboard + delta <= capacity!);

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final minimum = math.max(
            72.0, MediaQuery.textScalerOf(context).scale(16) * 2.4 + 16);
        final columns =
            ((constraints.maxWidth + 8) / (minimum + 8)).floor().clamp(1, 3);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        Widget buttons(List<int> deltas) =>
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final delta in deltas)
                SizedBox(
                    width: width,
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            textStyle: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                fontWeight: FontWeight.w600)),
                        onPressed:
                            _canApply(delta) ? () => onAdjust!(delta) : null,
                        child: Text(delta > 0 ? '+$delta' : '$delta',
                            semanticsLabel: delta > 0
                                ? 'Add $delta'
                                : 'Remove ${-delta}'))),
            ]);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Walk-ins'),
              const SizedBox(height: 8),
              Text('$manualCount',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              buttons(const [-1, -3, -5]),
              const SizedBox(height: 8),
              buttons(const [1, 3, 5]),
            ]);
      });
}
