import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/core/storage/token_storage.dart';
import 'package:parago_passenger/models/auth/auth_models.dart';
import 'package:parago_passenger/models/user_role.dart';
import 'package:parago_passenger/services/session_controller.dart';
import 'package:parago_passenger/widgets/forgot_password_link.dart';

String tokenWithExpiry(int seconds) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds,
        })))}.signature';

class FakeApi extends ApiClient {
  int refreshCalls = 0;
  String? lastPath;
  dynamic lastBody;
  final refresh = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    lastPath = path;
    lastBody = body;
    if (path == '/auth/refresh') {
      refreshCalls++;
      return refresh.future;
    }
    return {
      'success': true,
      'data': {'delivered': true}
    };
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'concurrent requests share one refresh and cannot restore cleared session',
      () async {
    final api = FakeApi();
    final session =
        SessionController(apiClient: api, tokenStorage: TokenStorage());
    addTearDown(session.dispose);
    await session.saveAuth(AuthSession(
        accessToken: tokenWithExpiry(-1),
        refreshToken: 'old',
        user: const UserProfile(
            fullName: 'Test',
            email: 'test@example.test',
            role: UserRole.passenger)));
    final first = session.ensureFreshSession();
    final second = session.ensureFreshSession();
    expect(api.refreshCalls, 1);
    await session.clear();
    api.refresh.complete({
      'success': true,
      'data': {
        'token': tokenWithExpiry(900),
        'refreshToken': 'new',
        'user': {
          'fullName': 'Test',
          'email': 'test@example.test',
          'role': 'PASSENGER'
        }
      }
    });
    await Future.wait([first, second]);
    expect(session.isAuthenticated, isFalse);
    expect((await TokenStorage().loadTokens())['refreshToken'], isNull);
  });

  testWidgets(
      'forgot password is available without signing in and sends only email',
      (tester) async {
    final api = FakeApi();
    final session =
        SessionController(apiClient: api, tokenStorage: TokenStorage());
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => session,
        child: const MaterialApp(home: Scaffold(body: ForgotPasswordLink()))));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test@example.test');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(api.lastPath, '/auth/forgot-password');
    expect(api.lastBody, {'email': 'test@example.test'});
    expect(find.textContaining('If this email belongs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
