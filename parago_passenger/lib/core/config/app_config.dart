import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  static const String _apiBaseUrlFallback = String.fromEnvironment(
    'PARAGO_API_BASE_URL',
    defaultValue: 'http://localhost:5000/api/v1',
  );
  static const String _apiBaseUrlsFallback = String.fromEnvironment(
    'PARAGO_API_BASE_URLS',
    defaultValue: '',
  );
  static const String googleFallbackClientId =
      String.fromEnvironment('PARAGO_GOOGLE_CLIENT_ID', defaultValue: '');
  static const String facebookFallbackClientToken =
      String.fromEnvironment('PARAGO_FACEBOOK_TOKEN', defaultValue: '');

  static final Map<String, String> _env = <String, String>{};
  static String? _resolvedApiBaseUrl;

  static String get apiBaseUrl =>
      _resolvedApiBaseUrl ?? _read('PARAGO_API_BASE_URL', _apiBaseUrlFallback);
  static String get openRouteServiceApiKey => _read('ORS_API_KEY', '');
  static bool get hasGoogleClientId => googleFallbackClientId.trim().isNotEmpty;
  static bool get enableRealtime =>
      _readBool('PARAGO_ENABLE_REALTIME', defaultValue: false);

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

  static Future<void> resolveApiBaseUrl() async {
    final candidates = _apiBaseUrlCandidates();
    if (candidates.isEmpty) {
      _resolvedApiBaseUrl = _read('PARAGO_API_BASE_URL', _apiBaseUrlFallback);
      return;
    }

    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
        headers: const {
          'Accept': 'application/json',
        },
      ),
    );

    try {
      for (final candidate in candidates) {
        if (await _isHealthyBaseUrl(client, candidate)) {
          _resolvedApiBaseUrl = candidate;
          debugPrint('Resolved ParaGO API base URL: $candidate');
          return;
        }
      }
    } finally {
      client.close(force: true);
    }

    _resolvedApiBaseUrl = candidates.first;
    debugPrint(
      'No healthy ParaGO API candidate responded. Falling back to ${candidates.first}',
    );
  }

  static String _read(String key, String fallback) {
    final value = _env[key]?.trim() ?? '';
    return value.isNotEmpty ? value : fallback;
  }

  static bool _readBool(String key, {required bool defaultValue}) {
    final value = _env[key]?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  static List<String> _apiBaseUrlCandidates() {
    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String raw) {
      final normalized = _normalizeBaseUrl(raw);
      if (normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      candidates.add(normalized);
    }

    addCandidate(_read('PARAGO_API_BASE_URL', _apiBaseUrlFallback));

    final configuredList =
        _read('PARAGO_API_BASE_URLS', _apiBaseUrlsFallback).trim();
    if (configuredList.isNotEmpty) {
      for (final item in configuredList.split(',')) {
        addCandidate(item);
      }
    }

    if (kIsWeb) {
      addCandidate('http://localhost:5000/api/v1');
      addCandidate('http://127.0.0.1:5000/api/v1');
      return candidates;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        addCandidate('http://10.0.2.2:5000/api/v1');
        addCandidate('http://127.0.0.1:5000/api/v1');
        addCandidate('http://localhost:5000/api/v1');
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        addCandidate('http://127.0.0.1:5000/api/v1');
        addCandidate('http://localhost:5000/api/v1');
        addCandidate('http://10.0.2.2:5000/api/v1');
        break;
    }

    final configured = _read('PARAGO_API_BASE_URL', _apiBaseUrlFallback);
    if (configured.contains('localhost')) {
      addCandidate(configured.replaceFirst('localhost', '10.0.2.2'));
      addCandidate(configured.replaceFirst('localhost', '127.0.0.1'));
    }
    if (configured.contains('127.0.0.1')) {
      addCandidate(configured.replaceFirst('127.0.0.1', '10.0.2.2'));
      addCandidate(configured.replaceFirst('127.0.0.1', 'localhost'));
    }

    return candidates;
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }

    final hasNestedPath = uri.path.isNotEmpty && uri.path != '/';
    if (!hasNestedPath || trimmed.endsWith('/')) {
      return trimmed;
    }
    return '$trimmed/';
  }

  static Future<bool> _isHealthyBaseUrl(Dio client, String baseUrl) async {
    final healthUrl = _joinUrl(baseUrl, 'health');
    try {
      final response = await client.get(healthUrl);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static String _joinUrl(String baseUrl, String path) {
    final trimmedBase = baseUrl.trim();
    final trimmedPath = path.trim();
    if (trimmedBase.isEmpty) {
      return trimmedPath;
    }
    if (trimmedPath.isEmpty) {
      return trimmedBase;
    }
    if (trimmedBase.endsWith('/')) {
      return '$trimmedBase$trimmedPath';
    }
    return '$trimmedBase/$trimmedPath';
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
