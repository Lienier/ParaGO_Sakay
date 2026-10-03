import '../widgets/forgot_password_link.dart';
import '../widgets/legal_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/utils/action_feedback.dart';
import '../core/exceptions/api_exception.dart';
import '../models/auth/auth_models.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/session_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _passengerRole = 'PASSENGER';
  static const _androidGoogleSetupMessage =
      'Firebase Google login still needs Android setup in Firebase. '
      'Make sure package com.parago.passenger has SHA-1 '
      '56:E2:09:88:11:D7:AA:A7:9C:CA:6B:3E:4F:61:02:97:3D:31:61:EB, '
      'Google Sign-In is enabled in Firebase Authentication, and rerun '
      'FlutterFire configure if Firebase settings change.';

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isRegisterMode = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _legalAccepted = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _submit() async {
    _dismissKeyboard();
    if (_isRegisterMode && !_legalAccepted) {
      setState(
          () => _error = 'Accept both policies before creating your account.');
      return;
    }
    final session = context.read<SessionController>();
    final auth = AuthService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ActionFeedback.run<AuthSession>(
        context: context,
        loadingMessage: _isRegisterMode
            ? 'Creating your passenger account...'
            : 'Signing you in...',
        showSuccess: false,
        action: () async {
          final result = _isRegisterMode
              ? await auth.registerEmail(
                  email: _emailCtrl.text,
                  password: _passwordCtrl.text,
                  fullName:
                      _nameCtrl.text.isEmpty ? _emailCtrl.text : _nameCtrl.text,
                  role: _passengerRole,
                )
              : await auth.loginEmail(
                  email: _emailCtrl.text,
                  password: _passwordCtrl.text,
                  role: _passengerRole,
                );
          if (result.user.role != UserRole.passenger) {
            throw Exception(
                'This account is not authorized for passenger access.');
          }
          return result;
        },
        onError: (error) async {
          if (!mounted) return;
          setState(() => _error = ActionFeedback.messageOf(error));
        },
      );
      if (response == null) {
        return;
      }
      await session.saveAuth(response);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _socialGoogle() async {
    _dismissKeyboard();
    final session = context.read<SessionController>();
    final authService = AuthService(session.apiClient);
    final firebaseAuthService = FirebaseAuthService();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tokens = await firebaseAuthService.signInWithGoogleTokens();
      if (tokens == null) {
        return;
      }

      AuthSession response;

      try {
        response = await authService.firebaseGoogleLogin(
          idToken: tokens.firebaseIdToken,
          role: _passengerRole,
        );
      } catch (error) {
        final isFirebaseTokenRejected =
            error is ApiException && error.statusCode == 401;

        if (!isFirebaseTokenRejected || tokens.googleIdToken.isEmpty) {
          rethrow;
        }

        response = await authService.socialLogin(
          provider: 'google',
          token: tokens.googleIdToken,
          role: _passengerRole,
        );
      }

      if (response.user.role != UserRole.passenger) {
        throw Exception('This account is not authorized for passenger access.');
      }
      await session.saveAuth(response);
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'sign_in_failed' &&
          (error.message?.contains('ApiException: 10') ?? false)) {
        setState(() => _error = _androidGoogleSetupMessage);
      } else {
        setState(() => _error = ActionFeedback.messageOf(error));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _showTroubleshooting {
    final message = (_error ?? '').toLowerCase();
    return message.contains('network') ||
        message.contains('timed out') ||
        message.contains('browser') ||
        message.contains('google');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final panelBase = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.36),
      scheme.primary,
    );
    final panelAccent = Color.alphaBlend(
      scheme.secondary.withValues(alpha: 0.12),
      panelBase,
    );
    final actionColor = scheme.secondary;
    const fieldSurface = Color(0xFFF7FAFA);
    const fieldText = Color(0xFF19363A);
    const fieldHint = Color(0xFF8B989C);
    final floatingLabelColor = Colors.white.withValues(alpha: 0.96);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF4F1E8),
              scheme.primary.withValues(alpha: 0.08),
              scheme.secondary.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [panelBase, panelAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 36,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: -36,
                        bottom: -42,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -18,
                        top: -18,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset(
                            'assets/images/sakay_logo.png',
                            height: 132,
                            fit: BoxFit.contain,
                          ),
                          Text(
                            'Login',
                            textAlign: TextAlign.left,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if ((_error ??
                                  context
                                      .watch<SessionController>()
                                      .signedOutMessage) !=
                              null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                (_error ??
                                    context
                                        .watch<SessionController>()
                                        .signedOutMessage)!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (_showTroubleshooting) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  'Troubleshooting:\n'
                                  '1. Check that the backend API is reachable.\n'
                                  '2. Confirm the passenger account is active.\n'
                                  '3. Verify your Google setup if you are using Google sign-in.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                          ],
                          if (_isRegisterMode) ...[
                            TextField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              onTapOutside: (_) => _dismissKeyboard(),
                              onSubmitted: (_) =>
                                  FocusScope.of(context).nextFocus(),
                              style: const TextStyle(
                                color: fieldText,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Full name',
                                labelStyle: const TextStyle(
                                  color: fieldHint,
                                  letterSpacing: 1.0,
                                ),
                                floatingLabelStyle: TextStyle(
                                  color: floatingLabelColor,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w600,
                                  backgroundColor: panelBase,
                                ),
                                filled: true,
                                fillColor: fieldSurface,
                                prefixIcon: const Icon(Icons.person_outline,
                                    color: fieldHint),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: actionColor,
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onTapOutside: (_) => _dismissKeyboard(),
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            style: const TextStyle(
                              color: fieldText,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Email address',
                              labelStyle: const TextStyle(
                                color: fieldHint,
                                letterSpacing: 1.0,
                              ),
                              floatingLabelStyle: TextStyle(
                                color: floatingLabelColor,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w600,
                                backgroundColor: panelBase,
                              ),
                              filled: true,
                              fillColor: fieldSurface,
                              prefixIcon: const Icon(Icons.alternate_email,
                                  color: fieldHint),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    BorderSide(color: actionColor, width: 1.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onTapOutside: (_) => _dismissKeyboard(),
                            onSubmitted: (_) {
                              if (!_loading) {
                                _submit();
                              }
                            },
                            style: const TextStyle(
                              color: fieldText,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(
                                color: fieldHint,
                                letterSpacing: 1.0,
                              ),
                              floatingLabelStyle: TextStyle(
                                color: floatingLabelColor,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w600,
                                backgroundColor: panelBase,
                              ),
                              filled: true,
                              fillColor: fieldSurface,
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: fieldHint),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    BorderSide(color: actionColor, width: 1.4),
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: fieldHint,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          if (_isRegisterMode) ...[
                            CheckboxListTile(
                              value: _legalAccepted,
                              onChanged: _loading
                                  ? null
                                  : (value) => setState(
                                      () => _legalAccepted = value == true),
                              title: const Text(
                                'I accept the Terms & Conditions and Privacy Policy.',
                                style: TextStyle(color: Colors.white),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              activeColor: actionColor,
                              checkColor: scheme.onSecondary,
                            ),
                            const SizedBox(height: 8),
                          ],
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: actionColor,
                              foregroundColor: scheme.onSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              _isRegisterMode
                                  ? 'CREATE PASSENGER ACCOUNT'
                                  : 'LOGIN',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _isRegisterMode = !_isRegisterMode;
                                      _legalAccepted = false;
                                    }),
                            child: Text(
                              _isRegisterMode
                                  ? 'Already registered? Sign in instead'
                                  : 'Need a passenger account? Register instead',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _socialGoogle,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.46),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            icon: const Icon(Icons.g_mobiledata),
                            label: const Text('Continue with Google'),
                          ),
                          const SizedBox(height: 12),
                          const ForgotPasswordLink(
                              foregroundColor: Colors.white),
                          const LegalLinks(foregroundColor: Colors.white),
                          if (_loading) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                color: actionColor,
                                backgroundColor: const Color(0x40FFFFFF),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
