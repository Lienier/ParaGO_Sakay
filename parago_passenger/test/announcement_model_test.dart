import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/operations/announcement.dart';

void main() {
  test('AnnouncementModel parses audience, revision, and UTC timing', () {
    final announcement = AnnouncementModel.fromJson({
      'id': 'announcement-1',
      'title': 'Route maintenance',
      'body': 'Expect a short service delay.',
      'category': 'maintenance',
      'severity': 'warning',
      'audiences': ['PASSENGER', 'DRIVER'],
      'status': 'published',
      'revision': 3,
      'startsAt': '2026-07-28T04:00:00.000Z',
      'expiresAt': '2026-07-29T04:00:00.000Z',
      'publishedAt': '2026-07-28T04:00:00.000Z',
    });

    expect(announcement.id, 'announcement-1');
    expect(announcement.category, 'maintenance');
    expect(announcement.severity, 'warning');
    expect(announcement.audiences, ['PASSENGER', 'DRIVER']);
    expect(announcement.revision, 3);
    expect(announcement.startsAt.isUtc, isTrue);
    expect(announcement.expiresAt, isNotNull);
  });
}
