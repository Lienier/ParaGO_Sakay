import '../exceptions/api_exception.dart';

/// Converts transport and driver-operation failures into safe, actionable copy.
/// Raw exception text is intentionally never shown to drivers.
class DriverErrorMessage {
  const DriverErrorMessage({required this.title, required this.message});

  final String title;
  final String message;

  static DriverErrorMessage from(Object error) {
    if (error is ApiException) {
      final mapped = _forCode(error.code);
      if (mapped != null) {
        final action = error.action?.trim() ?? '';
        if (_isSafeServerMessage(error.message) &&
            _isSafeServerMessage(action)) {
          return DriverErrorMessage(
              title: mapped.title, message: '${error.message.trim()} $action');
        }
        return mapped;
      }
      if (isConnectivity(error)) {
        return const DriverErrorMessage(
          title: 'Connection problem',
          message:
              'The server could not be reached. Check mobile data or Wi-Fi, then refresh before retrying.',
        );
      }
      if (error.statusCode == 401) {
        return const DriverErrorMessage(
          title: 'Sign-in required',
          message: 'Your session has expired. Sign in again to continue.',
        );
      }
      if (error.statusCode == 403) {
        return const DriverErrorMessage(
          title: 'Permission denied',
          message:
              'Your account is not allowed to perform this action. Contact an administrator if this seems incorrect.',
        );
      }
      if (error.statusCode >= 500) {
        return const DriverErrorMessage(
          title: 'Service unavailable',
          message:
              'The server could not complete the action. Check your connection and try again shortly.',
        );
      }
      final serverMessage = error.message.trim();
      final action = error.action?.trim();
      if (_isSafeServerMessage(serverMessage)) {
        return DriverErrorMessage(
          title: 'Action not completed',
          message:
              '$serverMessage ${action?.isNotEmpty == true ? action : 'Refresh the trip status and try again.'}',
        );
      }
      return const DriverErrorMessage(
        title: 'Action not completed',
        message:
            'The server rejected this action. Refresh the trip status and try again.',
      );
    }

    final lower = error.toString().toLowerCase();
    if (lower.contains('location services are disabled')) {
      return const DriverErrorMessage(
        title: 'Location is turned off',
        message:
            'Turn on location services so the app can confirm terminal arrival and share your jeepney position.',
      );
    }
    if (lower.contains('location permission denied')) {
      return const DriverErrorMessage(
        title: 'Location permission needed',
        message:
            'Allow location access in phone settings, then return to the app and try again.',
      );
    }
    if (_isConnectivity(lower)) {
      return const DriverErrorMessage(
        title: 'Connection problem',
        message:
            'The server could not be reached. Check mobile data or Wi-Fi, then refresh before retrying.',
      );
    }
    return const DriverErrorMessage(
      title: 'Action not completed',
      message:
          'We could not complete that action. Refresh the trip status and try again.',
    );
  }

  static bool isConnectivity(Object error) {
    if (error is ApiException &&
        const {'REQUEST_TIMEOUT', 'NETWORK_UNAVAILABLE'}.contains(error.code)) {
      return true;
    }
    final value = error is ApiException ? error.message : error.toString();
    return _isConnectivity(value.toLowerCase());
  }

  static DriverErrorMessage? _forCode(String? code) {
    switch (code) {
      case 'DRIVER_ACCOUNT_INACTIVE':
        return const DriverErrorMessage(
            title: 'Account inactive',
            message:
                'Your driver account is not active. Contact an administrator before starting a trip.');
      case 'DRIVER_OFFLINE':
        return const DriverErrorMessage(
            title: 'Driver status offline',
            message:
                'Set your driver status to online, then refresh and try again.');
      case 'DRIVER_ASSIGNMENT_MISSING':
        return const DriverErrorMessage(
            title: 'Assignment required',
            message:
                'You need an assigned jeepney and route before starting terminal entry. Contact an administrator if they are missing.');
      case 'JEEPNEY_NOT_FOUND':
      case 'JEEPNEY_INACTIVE':
        return const DriverErrorMessage(
            title: 'Jeepney unavailable',
            message:
                'Your assigned jeepney is missing or inactive. Refresh your assignment or contact an administrator.');
      case 'ROUTE_NOT_FOUND':
      case 'ROUTE_INACTIVE':
        return const DriverErrorMessage(
            title: 'Route unavailable',
            message:
                'The selected route is missing or inactive. Refresh the route list and choose an active route.');
      case 'TERMINAL_NOT_CONFIGURED':
        return const DriverErrorMessage(
            title: 'Terminal unavailable',
            message:
                'This route has no configured departure terminal. Choose another active route or contact an administrator.');
      case 'TERMINAL_ARRIVAL_PENDING':
        return const DriverErrorMessage(
            title: 'Arrival not confirmed',
            message:
                'Fresh GPS has not confirmed terminal arrival yet. Drive inside the configured terminal area and keep location enabled.');
      case 'TERMINAL_GPS_STALE':
        return const DriverErrorMessage(
            title: 'GPS update is old',
            message:
                'The latest location is too old to confirm arrival. Keep the app open briefly and try again.');
      case 'TERMINAL_GPS_POOR_ACCURACY':
        return const DriverErrorMessage(
            title: 'GPS accuracy is low',
            message:
                'Move to an open area and wait for a more accurate location before continuing.');
      case 'OUTSIDE_TERMINAL_RADIUS':
        return const DriverErrorMessage(
            title: 'Outside terminal area',
            message:
                'Move closer to the configured departure terminal. Arrival requires two accurate GPS updates inside the terminal area.');
      case 'TERMINAL_WRONG_QUEUE_STATE':
      case 'WRONG_QUEUE_STATE':
        return const DriverErrorMessage(
            title: 'Trip status changed',
            message:
                'That action is no longer available in the current terminal state. Refresh to see the next permitted action.');
      case 'DEPARTURE_REQUIRED':
      case 'TERMINAL_DEPARTURE_REQUIRED':
        return const DriverErrorMessage(
            title: 'Departure required',
            message:
                'The 10-minute loading period has ended. New terminal reservations are closed. Confirm departure when the jeep leaves.');
      case 'TRIP_ALREADY_CLOSED':
        return const DriverErrorMessage(
            title: 'Trip already ended',
            message:
                'This trip has already been closed. Refresh your trip list before starting another one.');
      case 'TRIP_NOT_ASSIGNED':
        return const DriverErrorMessage(
            title: 'Trip assignment changed',
            message:
                'This trip is assigned to another driver. Refresh your trips and open the assigned trip.');
      case 'STOP_ALERT_NOT_FOUND':
        return const DriverErrorMessage(
            title: 'Stop alert unavailable',
            message:
                'This passenger alert is no longer available. Refresh the alert list before trying again.');
      case 'OCCUPANCY_CAPACITY_CONFLICT':
        return const DriverErrorMessage(
            title: 'No seats available',
            message:
                'That passenger change would exceed available capacity or reserved seats. Refresh the count and try a smaller change.');
      case 'OCCUPANCY_STALE_SNAPSHOT':
        return const DriverErrorMessage(
            title: 'Passenger count changed',
            message:
                'Another update changed the count. Refresh before making another adjustment.');
      case 'DUPLICATE_OPERATION':
        return const DriverErrorMessage(
            title: 'Change already recorded',
            message:
                'That passenger-count change was already applied. Refresh the count to see the current total.');
      default:
        return null;
    }
  }

  static bool _isConnectivity(String value) =>
      value.contains('network') ||
      value.contains('connection') ||
      value.contains('socket') ||
      value.contains('timed out') ||
      value.contains('timeout') ||
      value.contains('host lookup') ||
      value.contains('xmlhttprequest') ||
      value.contains('fetch');

  static bool _isSafeServerMessage(String value) {
    if (value.isEmpty || value.length > 240) return false;
    final lower = value.toLowerCase();
    return !lower.contains('stack trace') &&
        !lower.contains('mongodb') &&
        !lower.contains('mongoose') &&
        !lower.contains('\n') &&
        !lower.contains('exception:') &&
        !lower.contains('error:') &&
        !lower.contains('econn') &&
        !lower.contains('syntaxerror');
  }
}
