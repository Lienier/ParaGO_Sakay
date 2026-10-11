import 'glass_surface.dart';
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
      'critical' => (const Color(0xFF0D4E47), const Color(0xFFFFB4AB)),
      'warning' => (const Color(0xFF0D4E47), const Color(0xFFFFD77A)),
      _ => (const Color(0xFF0D4E47), const Color(0xFFB8EFE0)),
    };
    final published = announcement.publishedAt ?? announcement.startsAt;
    return Dismissible(
        key: ValueKey(
            'announcement-${announcement.id}-${announcement.revision}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (_) async {
          onDismiss();
          return false;
        },
        child: Semantics(
          label: '${announcement.severity} announcement: ${announcement.title}',
          child: GlassSurface(
            tint: colors.$1,
            padding: EdgeInsets.all(compact ? 14 : 18),
            child: Builder(
                builder: (context) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.campaign_rounded, color: colors.$2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                announcement.category
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.$2,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                announcement.title,
                                softWrap: true,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: colors.$2,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                announcement.body,
                                softWrap: true,
                                maxLines: compact ? 3 : null,
                                overflow: compact
                                    ? TextOverflow.ellipsis
                                    : TextOverflow.visible,
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
                    )),
          ),
        ));
  }
}
