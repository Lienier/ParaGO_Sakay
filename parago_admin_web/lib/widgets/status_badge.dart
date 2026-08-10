import 'package:flutter/material.dart';

import '../core/utils/parago_format.dart';
import '../core/theme/app_colors.dart';

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
        return const _StatusColors(Color(0xFFDCFCE7), AppColors.success);
      case 'pending':
      case 'waiting':
      case 'scheduled':
      case 'seen':
        return const _StatusColors(Color(0xFFFFF1CC), AppColors.warning);
      case 'completed':
      case 'acknowledged_done':
        return const _StatusColors(Color(0xFFDBEAFE), AppColors.info);
      case 'cancelled':
      case 'expired':
      case 'dismissed':
      case 'inactive':
      case 'suspended':
      case 'deactivated':
        return const _StatusColors(Color(0xFFFEE4E2), AppColors.error);
      default:
        return const _StatusColors(Color(0xFFF1F5F9), AppColors.textSecondary);
    }
  }
}

class _StatusColors {
  const _StatusColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}
