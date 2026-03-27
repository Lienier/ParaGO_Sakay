enum UserRole {
  passenger,
  driver,
  unknown;

  static UserRole fromString(String? value) {
    switch ((value ?? '').toUpperCase()) {
      case 'PASSENGER':
        return UserRole.passenger;
      case 'DRIVER':
        return UserRole.driver;
      default:
        return UserRole.unknown;
    }
  }

  String get label {
    switch (this) {
      case UserRole.passenger:
        return 'PASSENGER';
      case UserRole.driver:
        return 'DRIVER';
      case UserRole.unknown:
        return 'UNKNOWN';
    }
  }
}
