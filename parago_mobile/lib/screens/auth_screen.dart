import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_role.dart';
import '../core/utils/action_feedback.dart';
import '../services/auth_service.dart';
import '../services/session_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  UserRole _selectedRole = UserRole.driver;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _isStaffRole(UserRole role) {
    return role == UserRole.driver || role == UserRole.admin;
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
        loadingMessage: 'Signing in to the dashboard...',
        showSuccess: false,
        action: () async {
          final result = await auth.loginEmail(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            role: _selectedRole.label,
          );
          if (!_isStaffRole(result.user.role)) {
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
                        'ParaGO!',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Staff access for live trip coordination, rider verification, and operations monitoring.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _BenefitChip(label: 'Trip controls'),
                          _BenefitChip(label: 'Boarding oversight'),
                          _BenefitChip(label: 'Operations tools'),
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
                    icon: Icons.badge_outlined,
                    title: 'Driver tools',
                    description:
                        'Route visibility, ride handling, and in-trip controls.',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Admin tools',
                    description:
                        'User management, dispatch oversight, and system status.',
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
                      'Staff sign in',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use the role-specific credentials assigned to you by ParaGO operations.',
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Access type',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<UserRole>(
                      segments: const [
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
                              () => _obscurePassword = !_obscurePassword,
                            );
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
                      icon: const Icon(Icons.login),
                      label: const Text('Continue to dashboard'),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'If your access was just created or updated, use the role that matches the credentials you were given.',
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
