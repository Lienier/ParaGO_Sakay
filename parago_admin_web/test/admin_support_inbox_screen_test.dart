import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/models/support/support_thread.dart';
import 'package:parago_admin_web/screens/admin/admin_support_inbox_screen.dart';
import 'package:parago_admin_web/services/realtime_socket_service.dart';
import 'package:parago_admin_web/services/support_service.dart';
import 'package:parago_admin_web/theme/app_theme.dart';

void main() {
  testWidgets('desktop support uses lazy list and bounded long messages',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeSupportRepository(
      List.generate(30, _thread),
      longBody: List.filled(
        100,
        'The detailed support message wraps without blocking the inbox.',
      ).join(' '),
    );

    await tester.pumpWidget(_app(repository, realtime));
    await tester.pumpAndSettle();

    expect(find.text('Conversation queue'), findsOneWidget);
    expect(find.text('30 threads'), findsOneWidget);
    expect(find.text('Thread 29'), findsNothing);
    expect(find.byType(IntrinsicHeight), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow support opens thread detail sheet and can reply',
      (tester) async {
    tester.view.physicalSize = const Size(620, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeSupportRepository([_thread(0)]);

    await tester.pumpWidget(_app(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thread 0'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Take thread'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Admin reply');
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    expect(repository.sentBodies, ['Admin reply']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet opens detail when viewport is wide but inbox is narrow',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeSupportRepository([_thread(0)]);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: Row(children: [
          const SizedBox(width: 224),
          Expanded(
              child: AdminSupportInboxScreen(
                  realtimeSocketService: realtime, repository: repository)),
        ]))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thread 0'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop support workspace review image', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeSupportRepository(
      List.generate(5, _thread),
      longBody: 'The passenger reports a fare concern during the morning trip. '
          'Operations can review the complete conversation here.',
    );

    await tester.pumpWidget(_app(repository, realtime));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AdminSupportInboxScreen),
      matchesGoldenFile('goldens/admin_support_desktop.png'),
    );
  });

  testWidgets('narrow support detail review image', (tester) async {
    tester.view.physicalSize = const Size(620, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeSupportRepository([_thread(0)]);

    await tester.pumpWidget(_app(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thread 0'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/admin_support_narrow.png'),
    );
  });
}

Widget _app(
  SupportRepository repository,
  RealtimeSocketService realtime,
) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: AdminSupportInboxScreen(
        realtimeSocketService: realtime,
        repository: repository,
      ),
    ),
  );
}

SupportThreadModel _thread(int index) {
  return SupportThreadModel.fromJson({
    'id': 'thread-$index',
    'userId': {
      'id': 'user-$index',
      'fullName': index.isEven ? 'Passenger Sample' : 'Driver Sample',
      'email': 'user$index@example.com',
    },
    'userRole': index.isEven ? 'PASSENGER' : 'DRIVER',
    'category': index.isEven ? 'fare_concern' : 'trip_issue',
    'status': index == 0 ? 'awaiting_admin' : 'open',
    'subject': 'Thread $index',
    'lastMessagePreview': 'A concise preview for support thread $index.',
    'unreadAdminCount': index == 0 ? 2 : 0,
    'createdAt': '2026-07-28T04:00:00.000Z',
    'updatedAt': '2026-07-28T05:00:00.000Z',
  });
}

class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository(this.threads, {this.longBody = 'Please help me.'});

  final List<SupportThreadModel> threads;
  final String longBody;
  final List<String> sentBodies = [];

  SupportThreadModel _find(String id) =>
      threads.firstWhere((thread) => thread.id == id);

  Map<String, dynamic> _threadJson(SupportThreadModel thread) => {
        'id': thread.id,
        'userId': {
          'id': thread.userId,
          'fullName': thread.creatorName,
          'email': thread.creatorEmail,
        },
        'userRole': thread.userRole,
        'category': thread.category,
        'status': thread.status,
        'subject': thread.subject,
        'lastMessagePreview': thread.lastMessagePreview,
        'unreadAdminCount': thread.unreadAdminCount,
        'createdAt': thread.createdAt,
        'updatedAt': thread.updatedAt,
      };

  @override
  Future<List<SupportThreadModel>> getInboxThreads({
    String? status,
    String? category,
    String? userRole,
    String? assignedAdminId,
    bool includeClosed = false,
  }) async {
    return threads
        .where((thread) => status == null || thread.status == status)
        .where((thread) => category == null || thread.category == category)
        .where((thread) => userRole == null || thread.userRole == userRole)
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getThreadMessages(String threadId) async {
    final thread = _find(threadId);
    return {
      'thread': _threadJson(thread),
      'messages': [
        {
          'id': 'message-$threadId',
          'threadId': threadId,
          'senderId': {
            'id': thread.userId,
            'fullName': thread.creatorName,
          },
          'senderRole': thread.userRole,
          'body': longBody,
          'createdAt': '2026-07-28T05:00:00.000Z',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String threadId,
    required String body,
  }) async {
    sentBodies.add(body);
    return {'thread': _threadJson(_find(threadId))};
  }

  @override
  Future<Map<String, dynamic>> markRead(String threadId) async {
    return _threadJson(_find(threadId));
  }

  @override
  Future<Map<String, dynamic>> assignThread({
    required String threadId,
    required String assignedAdminId,
  }) async {
    return _threadJson(_find(threadId));
  }

  @override
  Future<Map<String, dynamic>> resolveThread({
    required String threadId,
    String status = 'resolved',
  }) async {
    return _threadJson(_find(threadId));
  }

  @override
  Future<Map<String, dynamic>> closeThread(
    String threadId, {
    String? reason,
  }) async {
    return _threadJson(_find(threadId));
  }

  @override
  Future<Map<String, dynamic>> reopenThread(String threadId) async {
    return _threadJson(_find(threadId));
  }
}
