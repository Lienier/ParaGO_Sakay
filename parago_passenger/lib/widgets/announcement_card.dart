import 'package:flutter/material.dart';

import '../core/utils/parago_format.dart';
import '../models/operations/announcement.dart';

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onDismiss,
    this.compact = false,
  });

  final AnnouncementModel announcement;
  final VoidCallback onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = switch (announcement.severity) {
      'critical' => (const Color(0xFFFFE4E1), const Color(0xFF9B1C14)),
      'warning' => (const Color(0xFFFFF1CE), const Color(0xFF8A4B08)),
      _ => (const Color(0xFFE1F4F1), const Color(0xFF08665E)),
    };
    final published = announcement.publishedAt ?? announcement.startsAt;
    return Semantics(
      label: '${announcement.severity} announcement: ${announcement.title}',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.$2.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign_rounded, color: colors.$2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement.category.replaceAll('_', ' ').toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.$2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    announcement.title,
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.$2,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    announcement.body,
                    softWrap: true,
                    maxLines: compact ? 4 : null,
                    overflow:
                        compact ? TextOverflow.ellipsis : TextOverflow.visible,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${ParagoFormat.relative(published.toIso8601String())}'
                    '${announcement.expiresAt == null ? '' : '  |  Expires ${ParagoFormat.dateTime(announcement.expiresAt!.toIso8601String())}'}',
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss announcement',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
              color: colors.$2,
            ),
          ],
        ),
      ),
    );
  }
}
