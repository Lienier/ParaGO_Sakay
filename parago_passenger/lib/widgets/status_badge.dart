import 'package:flutter/material.dart';

import '../core/utils/parago_format.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ParagoFormat.statusLabel(status),
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  _StatusColors _resolveColors(String value) {
    switch (value.toLowerCase()) {
      case 'active':
      case 'acknowledged':
      case 'onboard':
      case 'available':
      case 'ready':
      case 'sent':
      case 'on_road':
        return const _StatusColors(Color(0xFFD8F3E6), Color(0xFF13623E));
      case 'pending':
      case 'waiting':
      case 'scheduled':
      case 'seen':
        return const _StatusColors(Color(0xFFFFE7B5), Color(0xFF8C5A00));
      case 'completed':
      case 'acknowledged_done':
        return const _StatusColors(Color(0xFFDCEBFF), Color(0xFF2157A5));
      case 'cancelled':
      case 'expired':
      case 'dismissed':
      case 'inactive':
      case 'suspended':
      case 'deactivated':
        return const _StatusColors(Color(0xFFF2D8D8), Color(0xFF8A2E2E));
      default:
        return const _StatusColors(Color(0xFFE6E4E0), Color(0xFF5B5650));
    }
  }
}

class _StatusColors {
  const _StatusColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}
