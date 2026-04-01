import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/passenger/passenger_profile.dart';

void main() {
  test('PassengerProfileModel.fromResponses combines user and passenger data',
      () {
    final profile = PassengerProfileModel.fromResponses(
      user: {
        'fullName': 'Alex Santos',
        'email': 'alex@example.com',
      },
      passenger: {
        'phone': '09171234567',
        'photoUrl': 'https://example.com/photo.jpg',
        'defaultRouteId': 'route-7',
        'emergencyContact': {
          'name': 'Jamie Santos',
          'phone': '09998887777',
        },
      },
    );

    expect(profile.fullName, 'Alex Santos');
    expect(profile.email, 'alex@example.com');
    expect(profile.phone, '09171234567');
    expect(profile.photoUrl, 'https://example.com/photo.jpg');
    expect(profile.defaultRouteId, 'route-7');
    expect(profile.emergencyContactName, 'Jamie Santos');
    expect(profile.emergencyContactPhone, '09998887777');
  });

  test('PassengerProfileModel.fromResponses tolerates missing optional fields',
      () {
    final profile = PassengerProfileModel.fromResponses(
      user: const {},
      passenger: const {},
    );

    expect(profile.fullName, isEmpty);
    expect(profile.email, isEmpty);
    expect(profile.phone, isNull);
    expect(profile.emergencyContactName, isNull);
    expect(profile.emergencyContactPhone, isNull);
  });
}
