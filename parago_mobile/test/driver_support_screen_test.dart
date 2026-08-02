import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_mobile/core/network/api_client.dart';
import 'package:parago_mobile/models/support/support_thread.dart';
import 'package:parago_mobile/screens/support/driver_support_screen.dart';
import 'package:parago_mobile/services/realtime_socket_service.dart';
import 'package:parago_mobile/services/support_service.dart';

void main() {
  testWidgets(
    'renders a support conversation and composer without a layout freeze',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final realtimeService = RealtimeSocketService();
      addTearDown(realtimeService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DriverSupportThreadScreen(
            thread: SupportThreadModel.fromJson(_FakeSupportService.threadJson),
            realtimeSocketService: realtimeService,
            supportService: _FakeSupportService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Synthetic driver support message.'), findsOneWidget);
      expect(find.text('Synthetic admin response.'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeSupportService extends SupportService {
  _FakeSupportService() : super(ApiClient(baseUrl: 'http://localhost/'));

  static const threadJson = <String, dynamic>{
    '_id': 'support-thread-1',
    'userId': 'driver-1',
    'userRole': 'DRIVER',
    'category': 'trip_issue',
    'status': 'awaiting_user',
    'subject': 'Synthetic driver support thread',
    'lastMessagePreview': 'Synthetic admin response.',
    'lastMessageSenderRole': 'ADMIN',
    'createdAt': '2026-07-29T08:12:13.219Z',
    'lastMessageAt': '2026-07-29T08:12:13.219Z',
  };

  @override
  Future<Map<String, dynamic>> getThreadMessages(String threadId) async {
    return <String, dynamic>{
      'thread': threadJson,
      'messages': const <Map<String, dynamic>>[
        <String, dynamic>{
          '_id': 'support-message-1',
          'threadId': 'support-thread-1',
          'senderId': 'driver-1',
          'senderRole': 'DRIVER',
          'body': 'Synthetic driver support message.',
          'createdAt': '2026-07-29T08:12:13.219Z',
        },
        <String, dynamic>{
          '_id': 'support-message-2',
          'threadId': 'support-thread-1',
          'senderId': 'admin-1',
          'senderRole': 'ADMIN',
          'senderName': 'Synthetic Staging Admin',
          'body': 'Synthetic admin response.',
          'createdAt': '2026-07-29T08:12:13.219Z',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(String threadId) async {
    return Map<String, dynamic>.from(threadJson);
  }
}
