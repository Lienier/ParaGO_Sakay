import '../network/api_client.dart';

class StatusReportMetric {
  const StatusReportMetric({
    required this.status,
    required this.count,
  });

  final String status;
  final int count;
}

class TelemetryRollup {
  const TelemetryRollup({
    required this.label,
    required this.requestCount,
    required this.averageDurationMs,
    required this.maxDurationMs,
    required this.failureCount,
    required this.staleHits,
  });

  final String label;
  final int requestCount;
  final int averageDurationMs;
  final int maxDurationMs;
  final int failureCount;
  final int staleHits;
}

List<StatusReportMetric> parseStatusReportRows(dynamic rows) {
  if (rows is! List) {
    return const <StatusReportMetric>[];
  }
  final parsed = rows
      .map((entry) {
        if (entry is! Map) {
          return null;
        }
        final status = entry['_id']?.toString() ?? 'unknown';
        final count = int.tryParse(entry['count']?.toString() ?? '') ?? 0;
        return StatusReportMetric(status: status, count: count);
      })
      .whereType<StatusReportMetric>()
      .toList(growable: false);
  parsed.sort((left, right) => right.count.compareTo(left.count));
  return parsed;
}

int totalStatusCount(Iterable<StatusReportMetric> rows) =>
    rows.fold<int>(0, (sum, row) => sum + row.count);

List<TelemetryRollup> summarizeTelemetry(
  List<ApiRequestTelemetry> telemetry, {
  int limit = 4,
}) {
  final buckets = <String, List<ApiRequestTelemetry>>{};
  for (final entry in telemetry) {
    final key = compactApiPath(entry.path);
    buckets.putIfAbsent(key, () => <ApiRequestTelemetry>[]).add(entry);
  }

  final summaries = buckets.entries.map((bucket) {
    final entries = bucket.value;
    final totalDuration = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationMs,
    );
    final maxDuration = entries.fold<int>(
      0,
      (max, entry) => entry.durationMs > max ? entry.durationMs : max,
    );
    final staleHits = entries.where((entry) => entry.usedStaleCache).length;
    final failures = entries.where((entry) => !entry.success).length;
    return TelemetryRollup(
      label: bucket.key,
      requestCount: entries.length,
      averageDurationMs: entries.isEmpty ? 0 : totalDuration ~/ entries.length,
      maxDurationMs: maxDuration,
      failureCount: failures,
      staleHits: staleHits,
    );
  }).toList(growable: false);

  summaries.sort((left, right) {
    final durationCompare =
        right.averageDurationMs.compareTo(left.averageDurationMs);
    if (durationCompare != 0) {
      return durationCompare;
    }
    return right.requestCount.compareTo(left.requestCount);
  });

  if (summaries.length <= limit) {
    return summaries;
  }
  return summaries.take(limit).toList(growable: false);
}

String compactApiPath(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) {
    return '/';
  }

  final withoutPrefix = normalized
      .replaceFirst(RegExp(r'^/api/v1'), '')
      .replaceFirst(RegExp(r'^api/v1/'), '')
      .replaceFirst(RegExp(r'^api/v1'), '');
  final prepared =
      withoutPrefix.startsWith('/') ? withoutPrefix : '/$withoutPrefix';
  final segments = prepared
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) {
    return '/';
  }

  final visible = segments.take(2).map((segment) {
    final looksLikeId =
        RegExp(r'^[a-f0-9]{8,}$', caseSensitive: false).hasMatch(segment);
    return looksLikeId ? ':id' : segment;
  }).toList(growable: false);
  return '/${visible.join('/')}';
}
