import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  static const String _apiBaseUrlFallback = String.fromEnvironment(
    'PARAGO_API_BASE_URL',
    defaultValue: 'http://localhost:5000/api/v1',
  );
  static const String googleFallbackClientId =
      String.fromEnvironment('PARAGO_GOOGLE_CLIENT_ID', defaultValue: '');
  static const String facebookFallbackClientToken =
      String.fromEnvironment('PARAGO_FACEBOOK_TOKEN', defaultValue: '');

  static final Map<String, String> _env = <String, String>{};

  static String get apiBaseUrl => _read('PARAGO_API_BASE_URL', _apiBaseUrlFallback);
  static String get openRouteServiceApiKey => _read('ORS_API_KEY', '');
  static bool get hasGoogleClientId => googleFallbackClientId.trim().isNotEmpty;

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('.env');
      _env
        ..clear()
        ..addAll(_parseEnv(raw));
    } catch (_) {
      _env.clear();
    }
  }

  static String _read(String key, String fallback) {
    final value = _env[key]?.trim() ?? '';
    return value.isNotEmpty ? value : fallback;
  }

  static Map<String, String> _parseEnv(String raw) {
    final values = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      final key = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (key.isEmpty) continue;
      values[key] = value;
    }
    return values;
  }
}
