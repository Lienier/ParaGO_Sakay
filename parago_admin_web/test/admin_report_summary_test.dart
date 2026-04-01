import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/core/utils/admin_report_summary.dart';

void main() {
  test('parseStatusReportRows sorts valid rows and totals correctly', () {
    final rows = parseStatusReportRows([
      {'_id': 'acknowledged', 'count': 2},
      {'_id': 'pending', 'count': 5},
      'ignore me',
      {'_id': 'completed', 'count': '3'},
    ]);

    expect(rows.map((row) => row.status),
        ['pending', 'completed', 'acknowledged']);
    expect(totalStatusCount(rows), 10);
  });

  test('compactApiPath strips api prefixes and hides identifiers', () {
    expect(compactApiPath('/api/v1/routes/65f04d8d26f7a1234abc9999'),
        '/routes/:id');
    expect(
        compactApiPath('api/v1/reports/route-demand'), '/reports/route-demand');
    expect(compactApiPath(''), '/');
  });

  test('summarizeTelemetry groups requests and counts failures and stale hits',
      () {
    final summary = summarizeTelemetry([
      ApiRequestTelemetry(
        method: 'GET',
        path: '/api/v1/routes/65f04d8d26f7a1234abc9999',
        durationMs: 220,
        occurredAt: DateTime(2026, 3, 30, 10),
        success: true,
      ),
      ApiRequestTelemetry(
        method: 'GET',
        path: '/api/v1/routes/65f04d8d26f7a1234abc9999',
        durationMs: 180,
        occurredAt: DateTime(2026, 3, 30, 10, 1),
        success: false,
        usedStaleCache: true,
      ),
      ApiRequestTelemetry(
        method: 'GET',
        path: '/api/v1/reports/route-demand',
        durationMs: 90,
        occurredAt: DateTime(2026, 3, 30, 10, 2),
        success: true,
      ),
    ]);

    expect(summary, hasLength(2));
    expect(summary.first.label, '/routes/:id');
    expect(summary.first.requestCount, 2);
    expect(summary.first.averageDurationMs, 200);
    expect(summary.first.maxDurationMs, 220);
    expect(summary.first.failureCount, 1);
    expect(summary.first.staleHits, 1);
  });
}
