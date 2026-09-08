import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/admin/admin_home_screen.dart';
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
      title: 'SAKAY Admin',
      theme: AppTheme.light(),
      home: Consumer<SessionController>(
        builder: (context, session, _) {
          if (session.isLoading) {
            return const _BootScreen();
          }

          if (!session.isAuthenticated) {
            return const AuthScreen();
          }
          return const AdminHomeScreen();
        },
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
              child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SakayGaray', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('Preparing your workspace'),
          const SizedBox(height: 24),
          const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      )));
}
