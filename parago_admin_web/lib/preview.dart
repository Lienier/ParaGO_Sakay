// Local design-review entrypoint. Never used by the production main.dart.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'services/session_controller.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/admin_email_otp_screen.dart';
import 'services/auth_service.dart';
import 'models/auth/auth_models.dart';
import 'theme/app_theme.dart';

void main() {
  if (!const bool.fromEnvironment('LOCAL_DESIGN_PREVIEW')) {
    throw StateError('Preview requires LOCAL_DESIGN_PREVIEW=true');
  }
  runApp(ChangeNotifierProvider(
    create: (_) => SessionController(
        apiClient: PreviewApi(), tokenStorage: TokenStorage()),
    child: const PreviewApp(),
  ));
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  bool login = false;
  bool otp = false;
  String mode = 'Populated';
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
            body: Column(children: [
          Container(
              color: const Color(0xFFEFF4F3),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                        width: 240,
                        child: Text('LOCAL DESIGN PREVIEW - Sample data only',
                            style: TextStyle(fontSize: 12))),
                    DropdownButton<String>(
                        value: mode,
                        items: [
                          'Populated',
                          'Empty',
                          'Error',
                          'Loading',
                          'Dispatch error'
                        ]
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (value) => setState(() {
                              mode = value!;
                              PreviewApi.mode = mode;
                            })),
                    TextButton(
                        onPressed: () => setState(() {
                              otp = !otp;
                              login = false;
                            }),
                        child: const Text('OTP')),
                    TextButton(
                        onPressed: () => setState(() {
                              login = !login;
                              otp = false;
                            }),
                        child: Text(login ? 'View workspace' : 'View login')),
                  ])),
          Expanded(
              child: otp
                  ? AdminEmailOtpScreen(
                      auth: AuthService(
                          context.read<SessionController>().apiClient),
                      challenge: AdminLoginChallenge(
                          challengeId: 'preview-only',
                          maskedEmail: 'a***@example.test',
                          expiresAt:
                              DateTime.now().add(const Duration(minutes: 5)),
                          expiresInSeconds: 300),
                      email: 'admin@example.test',
                      password: '')
                  : login
                      ? const AuthScreen()
                      : AdminHomeScreen(key: ValueKey(mode))),
        ])),
      );
}

class PreviewApi extends ApiClient {
  static String mode = 'Populated';
  @override
  Future<Map<String, dynamic>> request(
      {required String method,
      required String path,
      Map<String, dynamic>? queryParameters,
      dynamic body,
      bool useCache = true,
      Duration? cacheTtl}) async {
    if (path.endsWith('/read')) {
      return {'success': true, 'data': <String, dynamic>{}};
    }
    if (method != 'GET') throw Exception('Preview only. Changes are disabled.');
    if (mode == 'Loading') {
      await Future<void>.delayed(const Duration(minutes: 10));
    }
    if (mode == 'Error' ||
        (mode == 'Dispatch error' && path == '/admin/hybrid-dispatch')) {
      throw Exception('Unable to load this section. Please retry.');
    }
    final empty = mode == 'Empty';
    dynamic data = <String, dynamic>{};
    if (path == '/admin/dashboard') {
      data = {
        'activeTrips': empty ? 0 : 12,
        'pendingRequests': empty ? 0 : 8,
        'onboardRides': empty ? 0 : 46,
        'routeModeTrips': empty ? 0 : 9,
        'terminalQueueTrips': empty ? 0 : 3
      };
    }
    if (path == '/admin/hybrid-dispatch') {
      data = {
        'terminalQueue': empty
            ? []
            : [
                {
                  '_id': 'preview-trip',
                  'terminalQueueNumber': 1,
                  'terminalQueueStatus': 'loading',
                  'operatingMode': 'terminal_queue',
                  'terminalStopRef': 'Town terminal',
                  'driverId': {
                    'userId': {'fullName': 'Sample Driver'}
                  },
                  'jeepneyId': {'plateNumber': 'DEMO 001'},
                  'routeId': {'name': 'Town center - Terminal'},
                  'occupancyCount': 8,
                  'terminalSummary': {
                    'reservedSeats': 4,
                    'availableSeats': 8,
                    'gpsWarning': false
                  }
                }
              ],
        'waitingTerminalPassengers': [],
        'routeDrivers': []
      };
    }
    if (path == '/admin/hybrid-dispatch' && !empty) {
      final first = Map<String, dynamic>.from(data['terminalQueue'][0]);
      for (final item in ['waiting', 'skipped']) {
        data['terminalQueue'].add({
          ...first,
          '_id': 'preview-$item',
          'terminalQueueStatus': item,
          'terminalQueueNumber': item == 'waiting' ? 2 : 3,
          'occupancyCount': 0,
          'terminalSummary': {
            'reservedSeats': 0,
            'availableSeats': 20,
            'gpsWarning': item == 'skipped'
          },
          'jeepneyId': {
            'plateNumber': item == 'waiting' ? 'DEMO 002' : 'DEMO 003'
          }
        });
      }
    }
    if (path == '/admin/drivers') {
      data = empty
          ? []
          : List.generate(
              8,
              (i) => {
                    '_id': 'sample-$i',
                    'userId': {
                      'fullName': [
                        'Miguel Santos',
                        'Rafael Cruz',
                        'Paolo Reyes',
                        'Luis Garcia'
                      ][i % 4],
                      'email': 'driver$i@example.test',
                      'status': 'active'
                    },
                    'status': 'offline',
                    'assignedJeepneyId': {
                      'plateNumber': 'DEMO 00$i',
                      'capacity': 20
                    },
                    'assignedRouteId': {
                      '_id': 'route-1',
                      'name': 'Town center - Terminal',
                      'code': 'R01'
                    },
                  });
    }
    if (path == '/reports/passenger-flow') {
      data = {
        'summary': {
          'totalBoarded': empty ? 0 : 124,
          'totalUnloaded': empty ? 0 : 116
        },
        'daily': empty
            ? []
            : List.generate(
                7,
                (i) => {
                      'label': 'Day ${i + 1}',
                      'boarded': 10 + i * 3,
                      'unloaded': 8 + i * 3
                    }),
        'topBoardingLocations': [],
        'topUnloadLocations': []
      };
    }
    if (path == '/routes') {
      data = empty
          ? []
          : [
              for (var i = 0; i < 3; i++)
                {
                  '_id': 'route-$i',
                  'name': [
                    'Town center - Terminal',
                    'Terminal - Town center',
                    'Market connection'
                  ][i],
                  'code': 'R0${i + 1}',
                  'direction': i == 1 ? 'inbound' : 'outbound',
                  'status': i == 2 ? 'inactive' : 'active',
                  'stopsCount': 6,
                  'fareConfig': {
                    'baseAmount': 17,
                    'baseDistanceKm': 4,
                    'additionalAmountPerKm': 2
                  }
                }
            ];
    }
    if (path == '/jeepneys') data = [];
    if (path == '/announcements/admin') {
      data = {
        'items': empty
            ? []
            : [
                for (var i = 0; i < 3; i++)
                  {
                    '_id': 'announcement-$i',
                    'title': [
                      'Terminal boarding reminder',
                      'Route service update',
                      'Scheduled maintenance'
                    ][i],
                    'body':
                        'Please confirm your assigned jeep before boarding. Follow the terminal queue and ask the dispatcher if you need assistance.',
                    'category': 'general',
                    'severity': 'info',
                    'audiences': ['PASSENGER', 'DRIVER'],
                    'status': i == 2 ? 'scheduled' : 'published',
                    'startsAt': DateTime.now()
                        .subtract(const Duration(hours: 1))
                        .toIso8601String(),
                    'revision': 1,
                  }
              ],
        'pagination': {
          'page': 1,
          'limit': 25,
          'total': empty ? 0 : 3,
          'totalPages': 1
        }
      };
    }
    final thread = {
      '_id': 'sample-support',
      'subject': 'Help with a pickup request',
      'userId': {'_id': 'sample-user', 'fullName': 'Sample Passenger'},
      'userRole': 'PASSENGER',
      'category': 'general_help',
      'status': 'open',
      'lastMessagePreview': 'Where should I wait for my assigned jeep?',
      'unreadAdminCount': 1
    };
    if (path == '/support/admin/threads') data = empty ? [] : [thread];
    if (path == '/support/threads/sample-support/messages') {
      data = {
        'thread': thread,
        'messages': [
          {
            '_id': 'sample-message',
            'body': 'Where should I wait for my assigned jeep?',
            'senderRole': 'PASSENGER',
            'createdAt': DateTime.now().toIso8601String()
          }
        ]
      };
    }
    return {'success': true, 'data': data};
  }
}
