enum UserRole {
  passenger,
  driver,
  admin,
  unknown;

  static UserRole fromString(String? value) {
    switch ((value ?? '').toUpperCase()) {
      case 'PASSENGER':
        return UserRole.passenger;
      case 'DRIVER':
        return UserRole.driver;
      case 'ADMIN':
        return UserRole.admin;
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
      case UserRole.admin:
        return 'ADMIN';
      case UserRole.unknown:
        return 'UNKNOWN';
    }
  }
}
