import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/models/support/support_thread.dart';
import 'package:parago_passenger/screens/support/passenger_support_screen.dart';
import 'package:parago_passenger/services/realtime_socket_service.dart';
import 'package:parago_passenger/services/support_service.dart';
import 'package:parago_passenger/theme/app_theme.dart';

void main() {
  testWidgets(
    'opens composer and creates a general support thread without freezing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final supportService = _FakeSupportService();
      final realtimeService = RealtimeSocketService();
      addTearDown(realtimeService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PassengerSupportScreen(
            tripSessionId: 'unverified-selected-trip',
            realtimeSocketService: realtimeService,
            supportService: supportService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No support threads yet'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('New thread'));
      await tester.pumpAndSettle();

      expect(find.text('New support thread'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byType(TextFormField).last,
        'I need help with my account.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(supportService.createdMessage, 'I need help with my account.');
      expect(supportService.createdTripSessionId, isNull);
      expect(find.text('General support request'), findsWidgets);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeSupportService extends SupportService {
  _FakeSupportService() : super(ApiClient(baseUrl: 'http://localhost/'));

  String? createdMessage;
  String? createdTripSessionId;

  static const _threadJson = <String, dynamic>{
    '_id': 'support-thread-1',
    'userId': 'passenger-1',
    'userRole': 'PASSENGER',
    'category': 'general_help',
    'status': 'open',
    'subject': 'General support request',
    'lastMessagePreview': 'I need help with my account.',
    'lastMessageSenderRole': 'PASSENGER',
    'createdAt': '2026-07-28T02:00:00.000Z',
    'lastMessageAt': '2026-07-28T02:00:00.000Z',
  };

  @override
  Future<List<SupportThreadModel>> getMyThreads({
    bool includeClosed = false,
  }) async {
    return const <SupportThreadModel>[];
  }

  @override
  Future<Map<String, dynamic>> createThread({
    String? subject,
    required String category,
    required String message,
    String? tripSessionId,
    String? pickupRequestId,
    String? rideSessionId,
    String? routeId,
  }) async {
    createdMessage = message;
    createdTripSessionId = tripSessionId;
    return <String, dynamic>{
      'thread': _threadJson,
      'message': <String, dynamic>{
        '_id': 'support-message-1',
        'threadId': 'support-thread-1',
        'senderId': 'passenger-1',
        'senderRole': 'PASSENGER',
        'body': message,
        'createdAt': '2026-07-28T02:00:00.000Z',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getThreadMessages(String threadId) async {
    return <String, dynamic>{
      'thread': _threadJson,
      'messages': const <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'support-message-1',
          'threadId': 'support-thread-1',
          'senderId': 'passenger-1',
          'senderRole': 'PASSENGER',
          'body': 'I need help with my account.',
          'createdAt': '2026-07-28T02:00:00.000Z',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(String threadId) async {
    return Map<String, dynamic>.from(_threadJson);
  }
}
