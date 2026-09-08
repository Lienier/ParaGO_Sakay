import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/core/storage/token_storage.dart';
import 'package:parago_admin_web/screens/admin/admin_home_screen.dart';
import 'package:parago_admin_web/services/session_controller.dart';
import 'package:parago_admin_web/services/admin_service.dart';
import 'package:parago_admin_web/theme/app_theme.dart';

class OperationsApi extends ApiClient {
  bool failDispatch = true;
  bool failReports = false;
  int reports = 0;
  @override Future<Map<String, dynamic>> request({required String method, required String path,
    Map<String, dynamic>? queryParameters, dynamic body, bool useCache = true, Duration? cacheTtl}) async {
    expect(useCache, false);
    if (path == '/admin/hybrid-dispatch') {
      if (failDispatch) throw Exception('offline');
      return {'data': {'terminalQueue': [], 'waitingTerminalPassengers': [], 'routeDrivers': []}};
    }
    if (path == '/reports/passenger-flow') {
      reports++;
      if (failReports) throw Exception('offline');
      return {'data': {'summary': {'totalBoarded': 15, 'totalUnloaded': 12}, 'daily': []}};
    }
    return {'data': {'activeTrips': 12, 'pendingRequests': 8, 'onboardRides': 46, 'terminalQueueTrips': 3}};
  }
}
void main() {
  testWidgets('dispatch failure preserves activity; reports are lazy and preserve stale data', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final api = OperationsApi();
    final session = SessionController(apiClient: api, tokenStorage: TokenStorage());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: session, child: MaterialApp(theme: AppTheme.light(), home: const AdminHomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('46'), findsOneWidget);
    expect(find.text('This section is unavailable.'), findsOneWidget);
    expect(find.text('No terminal trips'), findsNothing);
    expect(api.reports, 0);
    await tester.tap(find.text('Reports').first); await tester.pumpAndSettle();
    expect(api.reports, 1); expect(find.text('15'), findsOneWidget);
    api.failReports = true;
    await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);
    expect(find.text('Refresh failed. Showing previous data.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); session.dispose();
  });
  test('invalid report range is rejected before requesting data', () async {
    final api = OperationsApi();
    await expectLater(AdminService(api).reportPassengerFlow(fromIso: '2025-01-01', toIso: '2026-02-01'), throwsArgumentError);
    expect(api.reports, 0);
  });
}
