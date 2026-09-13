import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/core/storage/token_storage.dart';
import 'package:parago_admin_web/screens/admin/admin_number_coding_screen.dart';
import 'package:parago_admin_web/services/session_controller.dart';
import 'package:parago_admin_web/theme/app_theme.dart';

class HolidayApi extends ApiClient {
  final mutations = <String>[];
  final items = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    expect(useCache, false);
    if (method != 'GET') {
      mutations.add('$method $path');
      if (method == 'PUT') {
        items.add({'date': path.split('/').last, 'name': body['name']});
      }
      if (method == 'DELETE') items.clear();
    }
    return {'data': List.of(items)};
  }
}

void main() {
  testWidgets(
      'validates dates, saves through existing endpoint and confirms removal',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = HolidayApi();
    final session = SessionController(apiClient: api, tokenStorage: TokenStorage());
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AdminNumberCodingScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Weekly restrictions'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '2026-02-30');
    await tester.enterText(find.byType(TextFormField).last, 'Sample holiday');
    await tester.tap(find.text('Save exemption'));
    await tester.pumpAndSettle();
    expect(api.mutations, isEmpty);
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '2026-12-25');
    await tester.tap(find.text('Save exemption'));
    await tester.pumpAndSettle();
    expect(api.mutations, ['PUT /admin/coding-holidays/2026-12-25']);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.mutations.length, 1);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(api.mutations.last, 'DELETE /admin/coding-holidays/2026-12-25');
    expect(find.text('No holiday exemptions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
