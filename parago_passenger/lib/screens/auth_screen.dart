import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/utils/action_feedback.dart';
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
    final session = context.read<SessionController>();
    final auth = AuthService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ActionFeedback.run<dynamic>(
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
                  fullName: _nameCtrl.text.isEmpty
                      ? _emailCtrl.text
                      : _nameCtrl.text,
                  role: _passengerRole,
                )
              : await auth.loginEmail(
                  email: _emailCtrl.text,
                  password: _passwordCtrl.text,
                  role: _passengerRole,
                );
          if (result.user.role != UserRole.passenger) {
            throw Exception('Invalid email/password');
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
      final response = await ActionFeedback.run<dynamic>(
        context: context,
        loadingMessage: 'Connecting with Google...',
        showSuccess: false,
        action: () async {
          final firebaseIdToken = await firebaseAuthService.signInWithGoogle();
          if (firebaseIdToken == null) {
            return null;
          }

          final result = await authService.firebaseGoogleLogin(
            idToken: firebaseIdToken,
            role: _passengerRole,
          );
          if (result.user.role != UserRole.passenger) {
            throw Exception('Invalid email/password');
          }
          return result;
        },
        onError: (error) async {
          if (!mounted) return;
          if (error is PlatformException &&
              error.code == 'sign_in_failed' &&
              (error.message?.contains('ApiException: 10') ?? false)) {
            setState(() => _error = _androidGoogleSetupMessage);
            return;
          }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -16,
                    top: -12,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 28,
                    bottom: -10,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.09),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ParaGO Passenger',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A practical jeepney companion app for booking pickups, tracking trips, and sending digital stop alerts.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _BenefitChip(label: 'Pickup requests'),
                          _BenefitChip(label: 'Boarding validation'),
                          _BenefitChip(label: 'Digital para alerts'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: const [
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.route_outlined,
                    title: 'Passenger requests',
                    description:
                        'Fast pickup requests and low-friction boarding confirmation.',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.notifications_active_outlined,
                    title: 'Trip updates',
                    description:
                        'Receive alerts for boarding, ride progress, and drop-off timing.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRegisterMode ? 'Create account' : 'Sign in',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegisterMode
                          ? 'Create a passenger account for pickup coordination and trip updates.'
                          : 'Use your passenger account to continue to your trip home screen.',
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Passenger app',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isRegisterMode) ...[
                      TextField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.next,
                        onTapOutside: (_) => _dismissKeyboard(),
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onTapOutside: (_) => _dismissKeyboard(),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.alternate_email),
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
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: Icon(
                          _isRegisterMode ? Icons.person_add_alt : Icons.login),
                      label: Text(
                        _isRegisterMode
                            ? 'Create ParaGO! account'
                            : 'Continue to home',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _isRegisterMode = !_isRegisterMode;
                              }),
                      child: Text(
                        _isRegisterMode
                            ? 'Already registered? Sign in instead'
                            : 'Need a test account? Register instead',
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _socialGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Google sign-in uses Firebase Auth on Android and then opens a normal passenger session from the backend.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Email and Google sign-in are available in this passenger app.',
                      ),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  const _BenefitChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description),
          ],
        ),
      ),
    );
  }
}
