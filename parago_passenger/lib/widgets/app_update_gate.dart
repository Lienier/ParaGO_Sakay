import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/config/app_build_info.dart';
import 'package:provider/provider.dart';
import '../services/session_controller.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  SessionController? _session;
  Map<String, dynamic>? _policy;
  int? _dismissed;
  int _epoch = 0;
  bool _busy = false;
  String? _userId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final id = session.isAuthenticated ? session.user?.userId : null;
    if (_session != session || _userId != id) {
      _session = session;
      _userId = id;
      _epoch++;
      _policy = null;
      _dismissed = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted ||
        _busy ||
        _userId == null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    try {
      final response = await _session!.apiClient.request(
          method: 'GET', path: '/mobile-updates/status', useCache: false);
      if (mounted &&
          epoch == _epoch &&
          response['data'] is Map<String, dynamic>) {
        setState(() {
          _policy = response['data'] as Map<String, dynamic>;
          _error = null;
        });
      }
    } catch (_) {
      // Optional update availability must never interrupt normal usage.
    } finally {
      _busy = false;
    }
  }

  Future<void> _download() async {
    if (!await AppBuildInfo.openDownload() && mounted) {
      setState(() => _error =
          'Open downloads.sakaygaray.com in your browser to download the update.');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latest = _policy?['latest'];
    final build = latest is Map ? latest['build'] as int? : null;
    final required = _policy?['required'] == true;
    final deferred = _policy?['deferred'] == true;
    final visible = build != null &&
        build > AppBuildInfo.build &&
        (required || _dismissed != build);
    if (!visible) return widget.child;
    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(required ? 'Major update available' : 'Update available',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(required
              ? (deferred
                  ? 'You can finish your current journey. Update before starting another.'
                  : 'Please update SakayGaray before starting a new journey.')
              : 'A new version is ready. You can update now or continue using the app.'),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8), child: Text(_error!)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton(
                onPressed: _download, child: const Text('Download update')),
            if (!required || deferred)
              TextButton(
                  onPressed: () => setState(() => _dismissed = build),
                  child: const Text('Later')),
            if (required && !deferred) ...[
              TextButton(onPressed: _check, child: const Text('Check again')),
              TextButton(
                  onPressed: () => _session?.logout(),
                  child: const Text('Sign out')),
            ],
          ]),
        ]);
    // Keep the navigator and active-trip screen mounted underneath the notice.
    return Stack(children: [
      widget.child,
      if (required && !deferred)
        Positioned.fill(
            child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                    child: Center(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 480),
                                child: content))))))
      else if (_dismissed != build)
        Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: SafeArea(
                child: Card(
                    elevation: 6,
                    child: Padding(
                        padding: const EdgeInsets.all(16), child: content)))),
    ]);
  }
}
