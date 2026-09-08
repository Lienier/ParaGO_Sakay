import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/core/network/api_client.dart';
import 'package:parago_admin_web/models/auth/auth_models.dart';
import 'package:parago_admin_web/screens/admin_email_otp_screen.dart';
import 'package:parago_admin_web/services/auth_service.dart';

class RejectingAuth extends AuthService {
  RejectingAuth() : super(ApiClient());
  @override
  Future<AuthSession> verifyAdminLogin(
      {required String challengeId, required String code}) async {
    throw Exception('Invalid or expired verification code');
  }
}

void main() {
  testWidgets(
      'OTP uses masked email, delays resend and displays verification errors',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AdminEmailOtpScreen(
      auth: RejectingAuth(),
      challenge: AdminLoginChallenge(
          challengeId: 'test',
          maskedEmail: 'a***@example.test',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          expiresInSeconds: 300),
      email: 'admin@example.test',
      password: 'not-a-real-password',
    )));
    expect(find.textContaining('a***@example.test'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Resend in 60s'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify and sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid or expired'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
