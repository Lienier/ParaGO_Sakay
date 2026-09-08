import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_admin_web/models/operations/announcement.dart';
import 'package:parago_admin_web/screens/admin/admin_announcements_screen.dart';
import 'package:parago_admin_web/services/announcement_service.dart';
import 'package:parago_admin_web/services/realtime_socket_service.dart';
import 'package:parago_admin_web/theme/app_theme.dart';

void main() {
  test('AnnouncementPage parses the paginated admin response', () {
    final page = AnnouncementPage.fromJson({
      'items': [
        _announcementJson(id: 'announcement-1'),
      ],
      'pagination': {
        'page': 2,
        'limit': 25,
        'total': 31,
        'totalPages': 2,
      },
    });

    expect(page.items.single.id, 'announcement-1');
    expect(page.page, 2);
    expect(page.limit, 25);
    expect(page.total, 31);
    expect(page.totalPages, 2);
  });

  testWidgets('desktop uses a bounded lazy list and one full detail body',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final longBody = List.filled(
      100,
      'Service operations remain available while this detailed update wraps.',
    ).join(' ');
    final repository = _FakeAnnouncementRepository([
      _announcement(id: 'one', body: longBody),
      _announcement(id: 'two', title: 'Second notice'),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();

    expect(find.text('Announcement history'), findsOneWidget);
    expect(find.text(longBody), findsOneWidget);
    expect(find.byType(IntrinsicHeight), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout opens complete details in a bottom sheet',
      (tester) async {
    tester.view.physicalSize = const Size(620, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository([
      _announcement(id: 'one', title: 'Narrow service notice'),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    expect(find.text('Select an announcement to view its full details.'),
        findsNothing);

    await tester.tap(find.text('Narrow service notice'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Audience'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history pagination requests the next bounded page',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository(
      List.generate(
        30,
        (index) => _announcement(
          id: 'announcement-$index',
          title: 'Announcement $index',
        ),
      ),
    );

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, containsAllInOrder([1, 2]));
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Announcement 29'), findsOneWidget);
  });

  testWidgets('expired announcements can duplicate but cannot edit',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository([
      _announcement(id: 'expired', status: 'expired'),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Duplicate'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Edit'), findsNothing);

    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(
      find.text('A new announcement will be created at revision 1.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createBodies, hasLength(1));
    expect(repository.createBodies.single['expiresAt'], isNull);
  });

  testWidgets('active archive confirmation sends the required flag',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository([
      _announcement(id: 'active'),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archive active announcement?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(repository.archiveConfirmations, [true]);
  });

  testWidgets('critical creation sends confirmation only after approval',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository(const []);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New announcement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Critical disruption',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message'),
      'Road access is temporarily closed.',
    );
    await tester.tap(find.byKey(const ValueKey('severity:info')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Critical').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createBodies, isEmpty);
    expect(find.text('Publish critical announcement?'), findsOneWidget);

    await tester.tap(find.text('Publish critical'));
    await tester.pumpAndSettle();

    expect(repository.createBodies.single['confirmCritical'], isTrue);
  });

  testWidgets('editing a published record preserves its original start time',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final original = _announcement(id: 'published');
    final repository = _FakeAnnouncementRepository([original]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Original start time will be preserved.'), findsOneWidget);

    await tester.tap(find.text('Save revision'));
    await tester.pumpAndSettle();

    final submitted = DateTime.parse(
      repository.updateBodies.single['startsAt'] as String,
    );
    expect(submitted, original.startsAt);
  });

  testWidgets('an older admin response cannot overwrite a newer refresh',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _RacingAnnouncementRepository();

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    repository.completeSecond();
    await tester.pumpAndSettle();
    repository.completeFirst();
    await tester.pumpAndSettle();

    expect(find.text('Newest response'), findsNWidgets(2));
    expect(find.text('Stale response'), findsNothing);
  });

  testWidgets('desktop announcement workspace review image', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository([
      _announcement(
        id: 'critical',
        title: 'Flooding along Rizal Avenue',
        body:
            'Jeepney service is temporarily rerouted while crews clear standing water. '
            'Passengers should use the temporary boarding point beside City Hall.',
      ),
      _announcement(
        id: 'scheduled',
        title: 'Terminal maintenance tomorrow',
        status: 'scheduled',
      ),
      _announcement(
        id: 'expired',
        title: 'Earlier service advisory',
        status: 'expired',
      ),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AdminAnnouncementsScreen),
      matchesGoldenFile('goldens/admin_announcements_desktop.png'),
    );
  });

  testWidgets('narrow announcement detail review image', (tester) async {
    tester.view.physicalSize = const Size(620, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realtime = RealtimeSocketService();
    addTearDown(realtime.dispose);
    final repository = _FakeAnnouncementRepository([
      _announcement(
        id: 'narrow',
        title: 'Temporary boarding point',
        body: 'Drivers and passengers should use the signed temporary boarding '
            'area beside the municipal hall until road maintenance is complete.',
      ),
    ]);

    await tester.pumpWidget(_testApp(repository, realtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temporary boarding point'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/admin_announcements_narrow.png'),
    );
  });
}

Widget _testApp(
  AnnouncementRepository repository,
  RealtimeSocketService realtime,
) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: AdminAnnouncementsScreen(
        realtimeSocketService: realtime,
        repository: repository,
      ),
    ),
  );
}

AnnouncementModel _announcement({
  required String id,
  String title = 'Service update',
  String body = 'Normal service announcement body.',
  String status = 'published',
}) {
  return AnnouncementModel.fromJson(
    _announcementJson(
      id: id,
      title: title,
      body: body,
      status: status,
    ),
  );
}

Map<String, dynamic> _announcementJson({
  required String id,
  String title = 'Service update',
  String body = 'Normal service announcement body.',
  String status = 'published',
}) {
  final now = DateTime.utc(2026, 7, 28, 6);
  return {
    'id': id,
    'title': title,
    'body': body,
    'category': 'service_change',
    'severity': 'warning',
    'audiences': ['PASSENGER', 'DRIVER'],
    'status': status,
    'revision': 2,
    'startsAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
    if (status == 'expired')
      'expiresAt': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    'updatedAt': now.toIso8601String(),
    'creator': {'fullName': 'Operations Admin'},
    'lastEditor': {'fullName': 'Duty Admin'},
  };
}

class _FakeAnnouncementRepository implements AnnouncementRepository {
  _FakeAnnouncementRepository(this.items);

  final List<AnnouncementModel> items;
  final List<int> requestedPages = [];
  final List<bool> archiveConfirmations = [];
  final List<Map<String, dynamic>> createBodies = [];
  final List<Map<String, dynamic>> updateBodies = [];

  @override
  Future<AnnouncementPage> getAdminAnnouncements({
    required int page,
    required int limit,
    String? status,
    String? category,
    String? severity,
    String? audience,
    DateTime? from,
    DateTime? to,
  }) async {
    requestedPages.add(page);
    final start = (page - 1) * limit;
    final pageItems = start >= items.length
        ? const <AnnouncementModel>[]
        : items.sublist(start, (start + limit).clamp(0, items.length));
    return AnnouncementPage(
      items: pageItems,
      page: page,
      limit: limit,
      total: items.length,
      totalPages: items.isEmpty ? 0 : (items.length / limit).ceil(),
    );
  }

  @override
  Future<AnnouncementModel> archive(
    String id, {
    required bool confirmActiveArchive,
  }) async {
    archiveConfirmations.add(confirmActiveArchive);
    return items.firstWhere((item) => item.id == id);
  }

  @override
  Future<AnnouncementModel> create(Map<String, dynamic> body) async {
    createBodies.add(Map<String, dynamic>.from(body));
    return _announcement(
      id: 'created',
      title: body['title']?.toString() ?? 'Created announcement',
      body: body['body']?.toString() ?? '',
    );
  }

  @override
  Future<AnnouncementModel> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    updateBodies.add(Map<String, dynamic>.from(body));
    return items.firstWhere((item) => item.id == id);
  }
}

class _RacingAnnouncementRepository implements AnnouncementRepository {
  final _first = Completer<AnnouncementPage>();
  final _second = Completer<AnnouncementPage>();
  int _requests = 0;

  void completeFirst() => _first.complete(
        _pageWith(_announcement(id: 'stale', title: 'Stale response')),
      );

  void completeSecond() => _second.complete(
        _pageWith(_announcement(id: 'newest', title: 'Newest response')),
      );

  AnnouncementPage _pageWith(AnnouncementModel item) => AnnouncementPage(
        items: [item],
        page: 1,
        limit: 25,
        total: 1,
        totalPages: 1,
      );

  @override
  Future<AnnouncementPage> getAdminAnnouncements({
    required int page,
    required int limit,
    String? status,
    String? category,
    String? severity,
    String? audience,
    DateTime? from,
    DateTime? to,
  }) {
    _requests++;
    return _requests == 1 ? _first.future : _second.future;
  }

  @override
  Future<AnnouncementModel> archive(
    String id, {
    required bool confirmActiveArchive,
  }) =>
      throw UnimplementedError();

  @override
  Future<AnnouncementModel> create(Map<String, dynamic> body) =>
      throw UnimplementedError();

  @override
  Future<AnnouncementModel> update(
    String id,
    Map<String, dynamic> body,
  ) =>
      throw UnimplementedError();
}
