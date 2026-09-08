import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_controller.dart';

class ForgotPasswordLink extends StatelessWidget {
  const ForgotPasswordLink({super.key, this.foregroundColor});
  final Color? foregroundColor;
  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(foregroundColor: foregroundColor),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const _ForgotPasswordPage())),
        child: const Text('Forgot password?'),
      );
}

class _ForgotPasswordPage extends StatefulWidget {
  const _ForgotPasswordPage();
  @override
  State<_ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<_ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await context.read<SessionController>().apiClient.request(
          method: 'POST',
          path: '/auth/forgot-password',
          body: {'email': _email.text.trim()},
          useCache: false);
      if (mounted) {
        setState(() => _message =
            'If this email belongs to an eligible account, a reset link has been sent. Check your inbox and spam folder.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                        'Enter your account email to request a password-reset link.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _busy ? null : _send,
                        child: const Text('Send reset link')),
                    if (_message != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_message!)),
                  ]),
            ))),
      );
}
