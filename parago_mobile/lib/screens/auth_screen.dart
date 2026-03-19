import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  static const _androidGoogleSetupMessage =
      'Firebase Google login still needs Android setup in Firebase. '
      'Make sure package com.example.parago_mobile has SHA-1 '
      '56:E2:09:88:11:D7:AA:A7:9C:CA:6B:3E:4F:61:02:97:3D:31:61:EB, '
      'Google Sign-In is enabled in Firebase Authentication, and rerun '
      'FlutterFire configure if Firebase settings change.';

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  UserRole _selectedRole = UserRole.passenger;
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

  Future<void> _submit() async {
    final session = context.read<SessionController>();
    final auth = AuthService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = _isRegisterMode
          ? await auth.registerEmail(
              email: _emailCtrl.text,
              password: _passwordCtrl.text,
              fullName:
                  _nameCtrl.text.isEmpty ? _emailCtrl.text : _nameCtrl.text,
              role: _selectedRole.label,
            )
          : await auth.loginEmail(
              email: _emailCtrl.text,
              password: _passwordCtrl.text,
            );
      await session.saveAuth(response);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _socialGoogle() async {
    final session = context.read<SessionController>();
    final authService = AuthService(session.apiClient);
    final firebaseAuthService = FirebaseAuthService();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final firebaseIdToken = await firebaseAuthService.signInWithGoogle();
      if (firebaseIdToken == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final response = await authService.firebaseGoogleLogin(
        idToken: firebaseIdToken,
        role: _selectedRole.label,
      );
      await session.saveAuth(response);
    } on PlatformException catch (error) {
      if (error.code == 'sign_in_failed' &&
          (error.message?.contains('ApiException: 10') ?? false)) {
        setState(() => _error = _androidGoogleSetupMessage);
      } else {
        setState(() => _error = error.toString());
      }
    } catch (error) {
      setState(() => _error = error.toString());
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
                        'ParaGO!',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A practical jeepney communication app for pickup coordination, boarding verification, and digital stop alerts.',
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
                    title: 'Passenger-first',
                    description:
                        'Fast request sending and low-friction boarding confirmation.',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.directions_bus_filled_outlined,
                    title: 'Driver-aware',
                    description:
                        'Minimal-distraction trip controls and alert handling.',
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
                          ? 'Passenger accounts are self-registrable. Driver/admin accounts are created from admin controls.'
                          : 'Use your ParaGO! account to continue to the role-based dashboard.',
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<UserRole>(
                      segments: _isRegisterMode
                          ? const [
                              ButtonSegment(
                                value: UserRole.passenger,
                                label: Text('Passenger'),
                                icon: Icon(Icons.person_outline),
                              ),
                            ]
                          : const [
                              ButtonSegment(
                                value: UserRole.passenger,
                                label: Text('Passenger'),
                                icon: Icon(Icons.person_outline),
                              ),
                              ButtonSegment(
                                value: UserRole.driver,
                                label: Text('Driver'),
                                icon: Icon(Icons.badge_outlined),
                              ),
                              ButtonSegment(
                                value: UserRole.admin,
                                label: Text('Admin'),
                                icon: Icon(Icons.admin_panel_settings_outlined),
                              ),
                            ],
                      selected: {_selectedRole},
                      onSelectionChanged: (roles) {
                        setState(() => _selectedRole = roles.first);
                      },
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
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
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
                            : 'Continue to dashboard',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _isRegisterMode = !_isRegisterMode;
                                if (_isRegisterMode) {
                                  _selectedRole = UserRole.passenger;
                                }
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
                        'Google sign-in now uses Firebase Auth on Android and '
                        'then opens a normal ParaGO session from the backend.',
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
                        'Facebook sign-in is currently hidden until the Android SDK configuration is finalized.',
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
