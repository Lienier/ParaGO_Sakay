import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parago_mobile/widgets/app_update_gate.dart';
import 'package:parago_mobile/core/config/app_build_info.dart';
import 'package:parago_mobile/core/network/api_client.dart';
import 'package:parago_mobile/core/storage/token_storage.dart';
import 'package:parago_mobile/models/auth/auth_models.dart';
import 'package:parago_mobile/models/user_role.dart';
import 'package:parago_mobile/services/session_controller.dart';

class UpdateApi extends ApiClient {
  bool requiredUpdate = false, deferred = false, offline = false;
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    if (offline) throw StateError('offline');
    return {
      'data': {
        'latest': {'build': 11},
        'required': requiredUpdate,
        'deferred': deferred
      }
    };
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppBuildInfo.build = 10;
  });
  testWidgets(
      'optional notice dismisses; major update defers for a journey and can recover',
      (tester) async {
    final api = UpdateApi();
    final session =
        SessionController(apiClient: api, tokenStorage: TokenStorage());
    session.applySession(const AuthSession(
        accessToken: 'test',
        refreshToken: 'test',
        user: UserProfile(
            userId: 'test-user',
            fullName: 'Test',
            email: 'test@example.test',
            role: UserRole.driver)));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
            builder: (context, child) => AppUpdateGate(child: child!),
            home: const Scaffold(body: Text('Journey controls')))));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    api.requiredUpdate = true;
    api.deferred = true;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    // The earlier dismissal may hide a deferred notice, but never blocks the journey.
    expect(find.text('Journey controls'), findsOneWidget);
    api.deferred = false;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Please update SakayGaray before starting a new journey.'),
        findsOneWidget);
    expect(find.text('Later'), findsNothing);
    api.requiredUpdate = false;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Please update SakayGaray before starting a new journey.'),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
  testWidgets('unavailable update endpoint leaves normal use available',
      (tester) async {
    final api = UpdateApi()..offline = true;
    final session =
        SessionController(apiClient: api, tokenStorage: TokenStorage());
    session.applySession(const AuthSession(
        accessToken: 'test',
        refreshToken: 'test',
        user: UserProfile(
            userId: 'test-user',
            fullName: 'Test',
            email: 'test@example.test',
            role: UserRole.driver)));
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
            builder: (context, child) => AppUpdateGate(child: child!),
            home: const Scaffold(body: Text('Journey controls')))));
    await tester.pumpAndSettle();
    expect(find.text('Journey controls'), findsOneWidget);
    expect(find.text('Download update'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
