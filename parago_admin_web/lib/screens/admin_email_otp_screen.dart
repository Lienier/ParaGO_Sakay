import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/action_feedback.dart';
import '../models/auth/auth_models.dart';
import '../services/auth_service.dart';

class AdminEmailOtpScreen extends StatefulWidget {
  const AdminEmailOtpScreen(
      {super.key,
      required this.auth,
      required this.challenge,
      required this.email,
      required this.password});
  final AuthService auth;
  final AdminLoginChallenge challenge;
  final String email;
  final String password;
  @override
  State<AdminEmailOtpScreen> createState() => _AdminEmailOtpScreenState();
}

class _AdminEmailOtpScreenState extends State<AdminEmailOtpScreen> {
  final _code = TextEditingController();
  late AdminLoginChallenge _challenge;
  Timer? _timer;
  int _wait = 60;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _wait > 0) setState(() => _wait--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit({bool resend = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (resend) {
        final challenge = await widget.auth
            .startAdminLogin(email: widget.email, password: widget.password);
        if (!mounted) return;
        setState(() {
          _challenge = challenge;
          _wait = 60;
          _code.clear();
        });
      } else {
        final session = await widget.auth.verifyAdminLogin(
            challengeId: _challenge.challengeId, code: _code.text);
        if (mounted) Navigator.of(context).pop(session);
      }
    } catch (error) {
      if (mounted) setState(() => _error = ActionFeedback.messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('SakayGaray'),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor),
        body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Check your email',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Text(
                          'Enter the six-digit code sent to ${_challenge.maskedEmail}. It expires in five minutes.'),
                      const SizedBox(height: 20),
                      TextField(
                          controller: _code,
                          enabled: !_busy,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_busy) _submit();
                          },
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                              labelText: 'Email verification code')),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      FilledButton(
                          onPressed: _busy ? null : () => _submit(),
                          child: const Text('Verify and sign in')),
                      TextButton(
                          onPressed: _busy || _wait > 0
                              ? null
                              : () => _submit(resend: true),
                          child: Text(_wait > 0
                              ? 'Resend in ${_wait}s'
                              : 'Resend code')),
                    ],
                  )),
            )),
      );
}
