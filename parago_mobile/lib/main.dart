import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/para_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'widgets/app_update_gate.dart';
import 'core/config/app_build_info.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/legal_acceptance_screen.dart';
import 'screens/driver/driver_home_screen.dart';
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

@pragma('vm:entry-point')
Future<void> handleParaBackground(RemoteMessage message) async {
  try {
    await _initializeFirebaseIfSupported();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final tokens = await TokenStorage(prefs: prefs).loadTokens();
    if (message.data['sessionId'] !=
        ParaSoundService.sessionId(tokens['accessToken'])) {
      return;
    }
    await AppConfig.load();
    final client = ApiClient(
        baseUrl: prefs.getString('para_api_base_url') ?? AppConfig.apiBaseUrl);
    await ParaSoundService.play(message.data['alertId'] ?? '', client,
        sentAt: message.data['sentAt'], receipt: message.data['receipt']);
  } catch (_) {
    // Never sound an alert when its session cannot be authorized.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBuildInfo.load();
  await AppConfig.load();
  await AppConfig.resolveApiBaseUrl();
  await _initializeFirebaseIfSupported();
  FirebaseMessaging.onBackgroundMessage(handleParaBackground);

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
      title: 'ParaGO!',
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
          return const DriverHomeScreen();
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
                  'ParaGO!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Preparing your driver dashboard',
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
