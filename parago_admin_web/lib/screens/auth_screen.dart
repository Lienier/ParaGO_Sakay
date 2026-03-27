import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/auth/auth_models.dart';
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
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  AdminLoginChallenge? _challenge;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _awaitingCode => _challenge != null;

  Future<void> _submitCredentials() async {
    _dismissKeyboard();
    final session = context.read<SessionController>();
    final auth = AuthService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final challenge = await ActionFeedback.run<AdminLoginChallenge>(
        context: context,
        loadingMessage: 'Sending verification code...',
        showSuccess: false,
        action: () async {
          return auth.startAdminLogin(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            phone: _phoneCtrl.text,
          );
        },
        onError: (error) async {
          if (!mounted) return;
          setState(() => _error = ActionFeedback.messageOf(error));
        },
      );
      if (challenge == null || !mounted) {
        return;
      }
      setState(() {
        _challenge = challenge;
        _codeCtrl.clear();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    _dismissKeyboard();
    final challenge = _challenge;
    if (challenge == null) {
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
        loadingMessage: 'Verifying code...',
        showSuccess: false,
        action: () async {
          final result = await auth.verifyAdminLogin(
            challengeId: challenge.challengeId,
            code: _codeCtrl.text,
          );
          if (result.user.role != UserRole.admin) {
            throw Exception('Invalid verification result');
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

  Future<void> _submit() {
    return _awaitingCode ? _verifyCode() : _submitCredentials();
  }

  void _returnToCredentials() {
    setState(() {
      _challenge = null;
      _error = null;
      _codeCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 980;

    final loginCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin sign in',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the admin credentials assigned to you by ParaGO operations.',
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'This application is reserved for admin accounts only.',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
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
            if (!_awaitingCode) ...[
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
                textInputAction: TextInputAction.next,
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) {
                  if (!_loading) {
                    _submit();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '09XXXXXXXXX or +639XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Enter the mobile number only if this admin account is not linked to one yet. After the password is verified, we will text the one-time code there.',
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'We sent a one-time verification code to ${_challenge?.maskedPhone ?? 'your mobile number'}.',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if ((_challenge?.developmentCode ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Development OTP',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _challenge!.developmentCode!,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      if ((_challenge?.deliveryWarning ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _challenge!.deliveryWarning!,
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => _dismissKeyboard(),
                onSubmitted: (_) {
                  if (!_loading) {
                    _submit();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Codes expire in about 5 minutes. If you need to use a different number, go back and restart the admin login.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (_awaitingCode) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _returnToCredentials,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Verify code'),
                    ),
                  ),
                ],
              ),
            ] else
              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Send verification code'),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _awaitingCode
                    ? 'Password verification is already complete for this sign-in attempt. Enter the SMS code to finish the admin login.'
                    : 'If your access was just created or updated, sign in again here with your admin account so the latest permissions are loaded.',
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: wide
                    ? Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: _AdminIntroPanel(scheme: scheme),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 4,
                            child: Align(
                              alignment: Alignment.center,
                              child: loginCard,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          _AdminIntroPanel(scheme: scheme),
                          const SizedBox(height: 18),
                          loginCard,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminIntroPanel extends StatelessWidget {
  const _AdminIntroPanel({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            const Color(0xFF2157A5),
            scheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -14,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 36,
            bottom: -24,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Dedicated web control room',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'ParaGO! Admin',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 42,
                      height: 0.95,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Web access for route setup, landmark fares, driver management, dispatch oversight, and reporting.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _BenefitChip(label: 'Driver management'),
                  _BenefitChip(label: 'Route & landmark editing'),
                  _BenefitChip(label: 'Operations reporting'),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: const [
                  _IntroStat(
                    label: 'Workspace',
                    value: '4 admin sections',
                  ),
                  _IntroStat(
                    label: 'Landmark fares',
                    value: 'Editable by admins',
                  ),
                  _IntroStat(
                    label: 'Role scope',
                    value: 'Admin only',
                  ),
                ],
              ),
            ],
          ),
        ],
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

class _IntroStat extends StatelessWidget {
  const _IntroStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
