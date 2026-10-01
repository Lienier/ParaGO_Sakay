import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/core/storage/token_storage.dart';
import 'package:parago_admin_web/services/session_controller.dart';
import 'package:parago_admin_web/screens/admin/admin_driver_management_screen.dart';

class FormApi extends ApiClient {
  Map<String, dynamic>? submitted;
  bool failSubmission = false;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    if (method == 'POST' && path == '/admin/drivers') {
      final form = body as FormData;
      submitted =
          jsonDecode(form.fields.singleWhere((f) => f.key == 'payload').value)
              as Map<String, dynamic>;
      if (form.files.length != 2) throw StateError('Both images required');
      if (failSubmission) throw StateError('Test storage unavailable');
      return {
        'success': true,
        'data': <String, dynamic>{'driver': <String, dynamic>{}}
      };
    }
    return {'success': true, 'data': <dynamic>[]};
  }
}

void main() {
  testWidgets(
      'creation form retains fields and values after scrolling to submit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session =
        SessionController(apiClient: FormApi(), tokenStorage: TokenStorage());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: AdminDriverManagementScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create driver').first);
    await tester.pumpAndSettle();
    final email = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Email *');
    await tester.enterText(email, 'driver@example.test');
    await tester.drag(find.byType(Dialog).last, const Offset(0, -2200));
    await tester.pumpAndSettle();
    expect(email, findsOneWidget,
        reason: 'Form.save must retain offscreen fields');
    expect(find.text('driver@example.test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  for (final fail in [false, true]) {
    testWidgets(
        'filled form preserves submitted fields and images; failure=$fail',
        (tester) async {
      late Directory directory;
      late File file;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('parago-form-test-');
        file = File('${directory.path}/license.png');
        await file.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAIAAAACUFjqAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAEUlEQVQYlWP4jxcwjEr/xwIA+h4q5HxTIAQAAAAASUVORK5CYII='));
      });
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => file.path);
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await file.delete();
        await directory.delete();
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FormApi()..failSubmission = fail;
      final session =
          SessionController(apiClient: api, tokenStorage: TokenStorage());
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: session,
          child: const MaterialApp(home: AdminDriverManagementScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create driver').first);
      await tester.pumpAndSettle();
      for (final entry in {
        'Email *': 'driver@example.test',
        'Password *': 'Local-Test-2026!',
        'Full name *': 'Test Driver',
        'Cooperative / driver reference *': 'TEST-LICENSE',
        'CP number *': '09000000000',
        'Plate number *': 'TEST1234',
        'Capacity *': '20',
      }.entries) {
        final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
        await tester.pump();
      }
      FocusManager.instance.primaryFocus?.unfocus();
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('Choose image').first);
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose image').first);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }
      await tester
          .ensureVisible(find.widgetWithText(FilledButton, 'Create driver'));
      await tester.tap(find.widgetWithText(FilledButton, 'Create driver'));
      if (fail) {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('Test storage unavailable'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('driver@example.test'), findsOneWidget);
      } else {
        await tester.pumpAndSettle();
      }
      expect(api.submitted?['email'], 'driver@example.test');
      expect(api.submitted?['fullName'], 'Test Driver');
      expect(api.submitted?['jeepney'],
          {'plateNumber': 'TEST1234', 'capacity': 20});
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
}
