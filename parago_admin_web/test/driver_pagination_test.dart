import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/core/storage/token_storage.dart';
import 'package:parago_admin_web/screens/admin/admin_driver_management_screen.dart';
import 'package:parago_admin_web/services/session_controller.dart';

class DriverPageApi extends ApiClient {
  int count = 16;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    if (path == '/admin/drivers') {
      return {
        'data': List.generate(
            count,
            (index) => {
                  '_id': 'driver-$index',
                  'userId': {
                    '_id': 'user-$index',
                    'fullName': 'Driver ${index + 1}',
                    'email': 'driver${index + 1}@example.test',
                    'status': 'active'
                  },
                  'presenceStatus': index.isEven ? 'online' : 'offline',
                  'assignedRouteId': {
                    '_id': 'route-1',
                    'name': 'Garay-Fairview'
                  },
                  'assignedJeepneyId': {
                    '_id': 'vehicle-$index',
                    'plateNumber': 'TEST-$index'
                  },
                })
      };
    }
    return {'data': <dynamic>[]};
  }
}

void main() {
  Future<SessionController> mount(
      WidgetTester tester, DriverPageApi api) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session =
        SessionController(apiClient: api, tokenStorage: TokenStorage());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: AdminDriverManagementScreen())));
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('driver pages navigate and search/filter start at the first page',
      (tester) async {
    final session = await mount(tester, DriverPageApi());
    expect(find.text('Showing 1–10 of 16 drivers'), findsOneWidget);
    expect(find.text('Driver 10'), findsOneWidget);
    expect(find.text('Driver 11'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Previous'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11–16 of 16 drivers'), findsOneWidget);
    expect(find.text('Driver 1'), findsNothing);
    expect(find.text('Driver 16'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Driver 1'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.labelText == 'Search driver, email, route, or plate');
    await tester.enterText(search, 'Driver 16');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–1 of 1 drivers'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All drivers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online only').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–8 of 8 drivers'), findsOneWidget);
    expect(find.text('Driver 15'), findsOneWidget);
    expect(find.text('Driver 16'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('presence refresh clamps a page when the driver list shrinks',
      (tester) async {
    final api = DriverPageApi();
    final session = await mount(tester, api);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    api.count = 4;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–4 of 4 drivers'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Driver 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
