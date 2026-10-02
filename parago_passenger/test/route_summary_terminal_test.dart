import 'package:flutter_test/flutter_test.dart';
import 'package:parago_passenger/models/transport/route_summary.dart';

void main() {
  test('configured departure terminal is distinct from the route end', () {
    final route = RouteSummaryModel.fromJson({
      '_id': 'route',
      'name': 'Route',
      'code': 'R',
      'direction': 'up',
      'status': 'active',
      'terminal': {
        'enabled': true,
        'name': 'Main Terminal',
        'location': {
          'type': 'Point',
          'coordinates': [121.01, 14.61]
        }
      },
      'stops': [
        {
          'name': 'First stop',
          'order': 1,
          'location': {
            'type': 'Point',
            'coordinates': [121.02, 14.62]
          }
        },
        {
          'name': 'Last stop',
          'order': 2,
          'location': {
            'type': 'Point',
            'coordinates': [121.03, 14.63]
          }
        },
      ],
    });
    expect(route.departureTerminal?.name, 'Main Terminal');
    expect(route.departureTerminal?.position.latitude, 14.61);
    expect(route.endTerminal?.name, 'Last stop');
  });
}
