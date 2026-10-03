import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'widgets/app_update_gate.dart';
import 'core/config/app_build_info.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'firebase_options.dart';
import 'models/user_role.dart';
import 'screens/auth_screen.dart';
import 'screens/legal_acceptance_screen.dart';
import 'screens/passenger/passenger_home_screen.dart';
import 'services/session_controller.dart';
import 'theme/app_theme.dart';

Future<void> _initializeFirebaseIfSupported() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // Web is not configured in FlutterFire yet; allow email-based flows to run.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBuildInfo.load();
  await AppConfig.load();
  await AppConfig.resolveApiBaseUrl();
  await _initializeFirebaseIfSupported();

  final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final storage = TokenStorage();
  final sessionController =
      SessionController(apiClient: apiClient, tokenStorage: storage);
  await sessionController.restore();

  runApp(
    ChangeNotifierProvider(
      create: (_) => sessionController,
      child: const ParagoApp(),
    ),
  );
}

class ParagoApp extends StatelessWidget {
  const ParagoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ParaGO Passenger',
      theme: AppTheme.light(),
      builder: (context, child) =>
          AppUpdateGate(child: child ?? const SizedBox.shrink()),
      home: Consumer<SessionController>(
        builder: (context, session, _) {
          if (session.isLoading) {
            return const _BootScreen();
          }

          if (!session.isAuthenticated) {
            return const AuthScreen();
          }

          if (session.requiresLegalAcceptance) {
            return const LegalAcceptanceScreen();
          }

          if (session.user?.role == UserRole.passenger) {
            return const PassengerHomeScreen();
          }

          return const _PassengerOnlyAccessScreen();
        },
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ParaGO Passenger',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Preparing your passenger commute dashboard',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                ),
                const SizedBox(height: 22),
                const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmPassengerRoleGateLogout(
  BuildContext context,
  SessionController session,
) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'Are you sure you want to sign out of the passenger application?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );

  if (shouldLogout == true) {
    await session.logout();
  }
}

class _PassengerOnlyAccessScreen extends StatelessWidget {
  const _PassengerOnlyAccessScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Consumer<SessionController>(
              builder: (context, session, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.no_accounts_outlined,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Passenger Account Required',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This app only supports passenger accounts. Please sign in with a passenger profile or use the driver/admin app instead.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () =>
                          _confirmPassengerRoleGateLogout(context, session),
                      child: const Text('Sign out'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
