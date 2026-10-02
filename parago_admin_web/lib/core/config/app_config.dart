import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  static const String awsApiBaseUrl =
      'https://api.sakaygaray.com/api/v1';
  static const String awsCloudFrontApiBaseUrl =
      'https://d3f9uwhh18xrzf.cloudfront.net/api/v1';

  static const String _apiBaseUrlFallback = String.fromEnvironment(
    'PARAGO_API_BASE_URL',
    defaultValue: awsApiBaseUrl,
  );
  static const String _apiBaseUrlsFallback = String.fromEnvironment(
    'PARAGO_API_BASE_URLS',
    defaultValue: awsCloudFrontApiBaseUrl,
  );
  static const String googleFallbackClientId =
      String.fromEnvironment('PARAGO_GOOGLE_CLIENT_ID', defaultValue: '');
  static const String facebookFallbackClientToken =
      String.fromEnvironment('PARAGO_FACEBOOK_TOKEN', defaultValue: '');
  static const String _openRouteServiceApiKeyFallback =
      String.fromEnvironment('ORS_API_KEY', defaultValue: '');
  static const bool _enableRealtimeFallback = bool.fromEnvironment(
    'PARAGO_ENABLE_REALTIME',
    defaultValue: false,
  );

  static String? _resolvedApiBaseUrl;

  static String get apiBaseUrl => _resolvedApiBaseUrl ?? _apiBaseUrlFallback;
  static String get openRouteServiceApiKey => _openRouteServiceApiKeyFallback;
  static bool get hasGoogleClientId => googleFallbackClientId.trim().isNotEmpty;
  static bool get enableRealtime => _enableRealtimeFallback;

  static Future<void> load() async {}

  static Future<void> resolveApiBaseUrl() async {
    final candidates = _apiBaseUrlCandidates();
    if (candidates.isEmpty) {
      _resolvedApiBaseUrl = _apiBaseUrlFallback;
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

    addCandidate(_apiBaseUrlFallback);

    final configuredList = _apiBaseUrlsFallback.trim();
    if (configuredList.isNotEmpty) {
      for (final item in configuredList.split(',')) {
        addCandidate(item);
      }
    }

    if (kIsWeb) {
      addCandidate('http://localhost:5000/api/v1');
      addCandidate('http://127.0.0.1:5000/api/v1');
    }

    if (kIsWeb) {
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

    final configured = _apiBaseUrlFallback;
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
}
