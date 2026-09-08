import 'admin_email_otp_screen.dart';
import '../widgets/forgot_password_link.dart';
import '../widgets/legal_pages.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../models/auth/auth_models.dart';
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

  Future<void> _submitCredentials() async {
    _dismissKeyboard();
    final session = context.read<SessionController>();
    final auth = AuthService(session.apiClient);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final challenge = await auth.startAdminLogin(
          email: _emailCtrl.text, password: _passwordCtrl.text);
      if (!mounted) return;
      final response =
          await Navigator.of(context).push<AuthSession>(MaterialPageRoute(
        builder: (_) => AdminEmailOtpScreen(
            auth: auth,
            challenge: challenge,
            email: _emailCtrl.text,
            password: _passwordCtrl.text),
      ));
      if (response == null) {
        return;
      }
      await session.saveAuth(response);
    } catch (error) {
      if (mounted) setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() => _submitCredentials();

  bool get _showNetworkTroubleshooting {
    final message = (_error ?? '').toLowerCase();
    return message.contains('browser') ||
        message.contains('network') ||
        message.contains('timed out');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 980;
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

    final loginForm = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          if (_showNetworkTroubleshooting) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                'Troubleshooting:\n'
                '1. Current API target: ${AppConfig.apiBaseUrl}\n'
                '2. If you are developing locally, start the backend on port 5000 or point PARAGO_API_BASE_URL to your local API.\n'
                '3. If you are using the deployed backend, verify that the API server is reachable and the admin account is active.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onTapOutside: (_) => _dismissKeyboard(),
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
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
            prefixIcon: const Icon(Icons.alternate_email, color: fieldHint),
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
              borderSide: BorderSide(color: actionColor, width: 1.4),
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
            prefixIcon: const Icon(Icons.lock_outline, color: fieldHint),
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
              borderSide: BorderSide(color: actionColor, width: 1.4),
            ),
            suffixIcon: IconButton(
              onPressed: () {
                setState(
                  () => _obscurePassword = !_obscurePassword,
                );
              },
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: fieldHint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
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
          child: const Text('LOGIN'),
        ),
        const SizedBox(height: 16),
        Text(
          'Authorized admin access only',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                letterSpacing: 1.4,
              ),
        ),
        if (_loading) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              color: actionColor,
              backgroundColor: Color(0x40FFFFFF),
            ),
          ),
        ],
      ],
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
                    ? _SplitAuthShell(
                        panelBase: panelBase,
                        panelAccent: panelAccent,
                        child: Row(
                          children: [
                            const Expanded(
                              child: _BrandPane(),
                            ),
                            Container(
                              width: 1,
                              height: 460,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 48),
                              color: Colors.white.withValues(alpha: 0.48),
                            ),
                            Expanded(
                              child: _LoginPane(child: loginForm),
                            ),
                          ],
                        ),
                      )
                    : _SplitAuthShell(
                        panelBase: panelBase,
                        panelAccent: panelAccent,
                        child: ListView(
                          shrinkWrap: true,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          children: [
                            const _BrandPane(compact: true),
                            const SizedBox(height: 28),
                            Container(
                              height: 1,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              color: Colors.white.withValues(alpha: 0.34),
                            ),
                            const SizedBox(height: 28),
                            _LoginPane(child: loginForm),
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

class _SplitAuthShell extends StatelessWidget {
  const _SplitAuthShell({
    required this.panelBase,
    required this.panelAccent,
    required this.child,
  });

  final Color panelBase;
  final Color panelAccent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 42),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            panelBase,
            panelAccent,
          ],
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
            left: -40,
            bottom: -48,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -28,
            top: -32,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BrandPane extends StatelessWidget {
  const _BrandPane({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/sakay_logo.png',
          height: compact ? 170 : 230,
          fit: BoxFit.contain,
        ),
        SizedBox(height: compact ? 20 : 28),
        Text(
          'SAKAY Admin',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontSize: compact ? 30 : 40,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.8,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Operations dashboard for route setup, fare updates, and dispatch management.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                letterSpacing: 0.4,
                height: 1.6,
              ),
        ),
      ],
    );
  }
}

class _LoginPane extends StatelessWidget {
  const _LoginPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.8,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              'PLEASE LOGIN TO ADMIN DASHBOARD.',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 40),
            child,
            const ForgotPasswordLink(foregroundColor: Colors.white),
            const LegalLinks(foregroundColor: Colors.white),
          ],
        ),
      ),
    );
  }
}
