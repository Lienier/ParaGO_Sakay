import 'package:flutter/material.dart';
import '../services/waiting_movement_guard.dart';
import 'glass_surface.dart';

class WaitingCheckCard extends StatelessWidget {
  const WaitingCheckCard(
      {super.key,
      required this.reason,
      required this.onWaiting,
      required this.onCancel});
  final WaitingMovementReason reason;
  final VoidCallback? onWaiting, onCancel;
  @override
  Widget build(BuildContext context) => GlassSurface(
        child: Builder(
            builder: (context) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Still waiting?',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(reason == WaitingMovementReason.distance
                            ? 'You moved away.'
                            : 'You are moving quickly.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: onWaiting, child: const Text('Waiting')),
                        const SizedBox(height: 8),
                        OutlinedButton(
                            onPressed: onCancel, child: const Text('Cancel')),
                      ]),
                )),
      );
}
