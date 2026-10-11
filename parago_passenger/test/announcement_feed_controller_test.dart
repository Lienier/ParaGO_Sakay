import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/core/exceptions/api_exception.dart';
import 'package:parago_passenger/models/operations/announcement.dart';
import 'package:parago_passenger/services/announcement_service.dart';
import 'package:parago_passenger/widgets/announcement_card.dart';

void main() {
  test('refreshes are serialized and coalesced to the newest response',
      () async {
    final firstResponse = Completer<List<AnnouncementModel>>();
    final repository = _FakeAnnouncementRepository([
      firstResponse.future,
      [_announcement(id: 'newest', revision: 2)],
    ]);
    final feed = AnnouncementFeedController(repository);

    final first = feed.refresh();
    final second = feed.refresh();
    firstResponse.complete([_announcement(id: 'older')]);
    await Future.wait([first, second]);

    expect(repository.getCalls, 2);
    expect(repository.maxConcurrentGets, 1);
    expect(feed.items.single.id, 'newest');
  });

  test('endpoint failure keeps the last successful snapshot', () async {
    final existing = _announcement(id: 'existing');
    final repository = _FakeAnnouncementRepository([
      [existing],
      Exception('announcement endpoint unavailable'),
    ]);
    final feed = AnnouncementFeedController(repository);

    await feed.refresh();
    await feed.refresh();

    expect(feed.hasSuccessfulSnapshot, isTrue);
    expect(feed.items, [existing]);
  });

  test('first-load endpoint failure produces an empty silent snapshot',
      () async {
    final feed = AnnouncementFeedController(
      _FakeAnnouncementRepository([Exception('offline')]),
    );

    await feed.refresh();

    expect(feed.hasSuccessfulSnapshot, isFalse);
    expect(feed.items, isEmpty);
  });

  test('stale dismissal does not restore old revision and refetches', () async {
    final oldRevision = _announcement(id: 'same', revision: 3);
    final newRevision = _announcement(id: 'same', revision: 4);
    final repository = _FakeAnnouncementRepository([
      [oldRevision],
      [newRevision],
    ])
      ..dismissError = ApiException(409, 'Announcement revision changed');
    final feed = AnnouncementFeedController(repository);
    await feed.refresh();

    final result = await feed.dismiss(oldRevision);

    expect(result.status, AnnouncementDismissStatus.staleRevision);
    expect(repository.dismissedRevisions, [3]);
    expect(feed.items.single.revision, 4);
  });

  test('network dismissal failure restores the previous position', () async {
    final first = _announcement(id: 'first');
    final second = _announcement(id: 'second');
    final repository = _FakeAnnouncementRepository([
      [first, second],
    ])
      ..dismissError = Exception('network unavailable');
    final feed = AnnouncementFeedController(repository);
    await feed.refresh();

    final result = await feed.dismiss(second);

    expect(result.status, AnnouncementDismissStatus.failed);
    expect(feed.items.map((item) => item.id), ['first', 'second']);
    expect(repository.dismissedRevisions, [1]);
  });

  testWidgets('announcement card styles warning and safely wraps long text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final body = List.filled(80, 'Long service update').join(' ');
    final announcement = _announcement(
      id: 'long',
      body: body,
      severity: 'warning',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnnouncementCard(
              announcement: announcement,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    final bodyText = tester.widget<Text>(find.text(body));
    expect(bodyText.maxLines, isNull);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.campaign_rounded)).color == const Color(0xFFFFD77A),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnouncementCard(
            announcement: announcement,
            onDismiss: () {},
            compact: true,
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text(body)).maxLines, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('announcement card applies every severity palette',
      (tester) async {
    const expectedColors = {
      'info': Color(0xFFB8EFE0),
      'warning': Color(0xFFFFD77A),
      'critical': Color(0xFFFFB4AB),
    };

    for (final entry in expectedColors.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnouncementCard(
              announcement: _announcement(
                id: entry.key,
                severity: entry.key,
              ),
              onDismiss: () {},
            ),
          ),
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.campaign_rounded)).color == entry.value,
        isTrue,
      );
    }
  });

  testWidgets('passenger home and notices announcement review image',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final announcement = _announcement(
      id: 'passenger-review',
      publishedAt: DateTime.now().subtract(const Duration(hours: 25)),
      severity: 'critical',
      body:
          'Flooding has temporarily moved the boarding point beside City Hall. '
          'Trips and booking remain available while this notice is active.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F2E9),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Passenger home'),
                  const SizedBox(height: 10),
                  AnnouncementCard(
                    announcement: announcement,
                    onDismiss: () {},
                    compact: true,
                  ),
                  const SizedBox(height: 24),
                  const Text('Notices'),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AnnouncementCard(
                        announcement: announcement,
                        onDismiss: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/passenger_announcements.png'),
    );
  });
}

AnnouncementModel _announcement({
  required String id,
  int revision = 1,
  DateTime? publishedAt,
  String body = 'Service announcement',
  String severity = 'info',
}) {
  final startsAt = DateTime.utc(2026, 7, 28, 4, revision);
  return AnnouncementModel(
    id: id,
    title: 'Announcement $id',
    body: body,
    category: 'service_change',
    severity: severity,
    audiences: const ['PASSENGER'],
    status: 'published',
    revision: revision,
    startsAt: startsAt,
    publishedAt: publishedAt ?? startsAt,
  );
}

class _FakeAnnouncementRepository implements AnnouncementRepository {
  _FakeAnnouncementRepository(this.responses);

  final List<Object> responses;
  Object? dismissError;
  int getCalls = 0;
  int concurrentGets = 0;
  int maxConcurrentGets = 0;
  final List<int> dismissedRevisions = [];

  @override
  Future<List<AnnouncementModel>> getActive({bool useCache = true}) async {
    getCalls++;
    concurrentGets++;
    if (concurrentGets > maxConcurrentGets) {
      maxConcurrentGets = concurrentGets;
    }
    try {
      final response = responses.removeAt(0);
      if (response is Future<List<AnnouncementModel>>) {
        return await response;
      }
      if (response is List<AnnouncementModel>) return response;
      throw response;
    } finally {
      concurrentGets--;
    }
  }

  @override
  Future<void> dismiss(String id, {required int revision}) async {
    dismissedRevisions.add(revision);
    final error = dismissError;
    dismissError = null;
    if (error != null) throw error;
  }
}
