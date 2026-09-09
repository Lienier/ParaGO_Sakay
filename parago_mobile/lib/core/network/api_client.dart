import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/api_exception.dart';
import '../../core/config/app_config.dart';

class ApiRequestTelemetry {
  const ApiRequestTelemetry({
    required this.method,
    required this.path,
    required this.durationMs,
    required this.occurredAt,
    required this.success,
    this.statusCode,
    this.fromCache = false,
    this.usedStaleCache = false,
  });

  final String method;
  final String path;
  final int durationMs;
  final DateTime occurredAt;
  final bool success;
  final int? statusCode;
  final bool fromCache;
  final bool usedStaleCache;
}

class _ApiCachedResponse {
  _ApiCachedResponse({required this.payload, required this.expiresAt});

  final Map<String, dynamic> payload;
  final DateTime expiresAt;
}

class ApiClient {
  Future<void> Function()? beforeAuthenticatedRequest;
  Future<void> Function()? onAuthenticationRejected;
  DateTime? _cooldownUntil;
  ApiClient({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl ?? AppConfig.apiBaseUrl),
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        );

  final Dio _dio;
  final Map<String, _ApiCachedResponse> _memoryCache = {};
  final Map<String, Future<Map<String, dynamic>>> _pendingGetRequests = {};
  final List<ApiRequestTelemetry> _recentTelemetry = <ApiRequestTelemetry>[];
  int _cacheGeneration = 0;
  SharedPreferences? _cachePrefs;
  static const String _cachePrefix = 'parago_api_cache_v1:';

  String get baseUrl => _dio.options.baseUrl;
  List<ApiRequestTelemetry> get recentTelemetry =>
      List<ApiRequestTelemetry>.unmodifiable(_recentTelemetry);

  static String _normalizeBaseUrl(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim();
    if (trimmed.isEmpty) {
      return trimmed;
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

  Future<SharedPreferences> get _cacheStorage async {
    _cachePrefs ??= await SharedPreferences.getInstance();
    return _cachePrefs!;
  }

  String _normalizePathForRequest(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final parsedBasePath = Uri.tryParse(_dio.options.baseUrl)?.path ?? '';
    final baseHasNestedPath =
        parsedBasePath.isNotEmpty && parsedBasePath != '/';
    final baseHasApiV1 = parsedBasePath.endsWith('/api/v1') ||
        parsedBasePath.endsWith('/api/v1/');

    var normalized = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    if (baseHasApiV1 && normalized == 'api/v1') {
      normalized = '';
    } else if (baseHasApiV1 && normalized.startsWith('api/v1/')) {
      normalized = normalized.substring(7);
    }

    if (normalized.isEmpty) {
      return baseHasNestedPath ? '' : '/';
    }
    return baseHasNestedPath ? normalized : '/$normalized';
  }

  Future<Map<String, dynamic>?> _getCachedResponse({
    required String cacheKey,
    bool allowExpired = false,
  }) async {
    final now = DateTime.now();
    final memoryEntry = _memoryCache[cacheKey];
    if (memoryEntry != null) {
      if (!allowExpired && now.isAfter(memoryEntry.expiresAt)) {
        _memoryCache.remove(cacheKey);
        return null;
      }
      return memoryEntry.payload;
    }

    final storage = await _cacheStorage;
    final raw = storage.getString('$_cachePrefix$cacheKey');
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final expiry = decoded['expiresAt'];
    if (expiry is! int) {
      await storage.remove('$_cachePrefix$cacheKey');
      return null;
    }

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry);
    final payload = decoded['payload'];
    if (payload is! Map<String, dynamic>) return null;

    if (!allowExpired && now.isAfter(expiresAt)) {
      await storage.remove('$_cachePrefix$cacheKey');
      _memoryCache.remove(cacheKey);
      return null;
    }
    _memoryCache[cacheKey] = _ApiCachedResponse(
      payload: payload,
      expiresAt: expiresAt,
    );
    return payload;
  }

  Future<void> _setCachedResponse({
    required String cacheKey,
    required Map<String, dynamic> payload,
    required Duration ttl,
  }) async {
    if (ttl.inMilliseconds <= 0) return;
    final expiresAt = DateTime.now().add(ttl);
    final entry = _ApiCachedResponse(payload: payload, expiresAt: expiresAt);
    _memoryCache[cacheKey] = entry;

    final storage = await _cacheStorage;
    await storage.setString(
      '$_cachePrefix$cacheKey',
      jsonEncode({
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'payload': payload,
      }),
    );
  }

  String _cacheKey(String path, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return path;
    }
    final entries = queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final encoded = entries
        .map((entry) => '${entry.key}=${jsonEncode(entry.value ?? '')}')
        .join('&');
    return '$path?$encoded';
  }

  Duration _cacheTtlForPath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';

    if (normalized.startsWith('/routes')) return const Duration(hours: 6);
    if (normalized.startsWith('/trips/active') ||
        normalized.startsWith('/trips/mine')) {
      return const Duration(seconds: 8);
    }
    if (normalized.startsWith('/notifications/mine')) {
      return const Duration(seconds: 20);
    }
    if (normalized.startsWith('/pickup-requests/mine')) {
      return const Duration(seconds: 10);
    }
    if (normalized.startsWith('/pickup-requests/trip/') ||
        normalized.startsWith('/ride-sessions/trip/') ||
        normalized.startsWith('/ride-sessions/mine') ||
        normalized.startsWith('/stop-alerts/trip/')) {
      return const Duration(seconds: 10);
    }
    return const Duration(seconds: 30);
  }

  String _friendlyDioErrorMessage(DioException error) {
    if (error.response?.data is Map) {
      final data = error.response!.data as Map;
      final message = data['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) {
        return message;
      }
    }

    final rawMessage = (error.message ?? 'Network error').trim();
    final lower = rawMessage.toLowerCase();

    if (lower.contains('failed host lookup')) {
      return 'Could not reach the API host. Check your internet connection or '
          'point the app to a reachable local/LAN backend.';
    }

    if (lower.contains('connection refused')) {
      return 'The API server refused the connection. Make sure the backend is running.';
    }

    if (kIsWeb &&
        error.type == DioExceptionType.connectionError &&
        lower.contains('xmlhttprequest')) {
      return 'The browser could not complete the request to the API server.';
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        lower.contains('timed out') ||
        lower.contains('timeout')) {
      return 'The request timed out before the server responded.';
    }

    return rawMessage.isEmpty ? 'Network error' : rawMessage;
  }

  Future<void> _clearAllCache() async {
    _memoryCache.clear();
    final storage = await _cacheStorage;
    final keysToRemove =
        storage.getKeys().where((key) => key.startsWith(_cachePrefix)).toList();
    for (final key in keysToRemove) {
      await storage.remove(key);
    }
  }

  Future<void> _clearCacheAfterMutation(String requestPath) async {
    final normalized =
        requestPath.startsWith('/') ? requestPath : '/$requestPath';
    final isolatedPrefix = switch (normalized) {
      final path when path.startsWith('/support/') || path == '/support' =>
        '/support',
      final path
          when path.startsWith('/announcements/') || path == '/announcements' =>
        '/announcements',
      final path
          when path.startsWith('/notifications/') || path == '/notifications' =>
        '/notifications',
      _ => null,
    };
    if (isolatedPrefix == null) {
      await _clearAllCache();
      return;
    }

    _memoryCache.removeWhere((key, _) => key.startsWith(isolatedPrefix));
    final storage = await _cacheStorage;
    final keysToRemove = storage
        .getKeys()
        .where(
          (key) =>
              key.startsWith('$_cachePrefix$isolatedPrefix') ||
              key.startsWith('$_cachePrefix$isolatedPrefix?'),
        )
        .toList();
    for (final key in keysToRemove) {
      await storage.remove(key);
    }
  }

  void setAccessToken(String? token) {
    if (token == null) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<void> clearCache() async {
    await _clearAllCache();
  }

  Future<Map<String, dynamic>?> readCachedSnapshot({
    required String path,
    Map<String, dynamic>? queryParameters,
    bool allowExpired = true,
  }) async {
    final requestPath = _normalizePathForRequest(path);
    final cacheKey = _cacheKey(requestPath, queryParameters);
    return _getCachedResponse(
      cacheKey: cacheKey,
      allowExpired: allowExpired,
    );
  }

  Future<List<dynamic>> readCachedListSnapshot({
    required String path,
    Map<String, dynamic>? queryParameters,
    bool allowExpired = true,
  }) async {
    final cached = await readCachedSnapshot(
      path: path,
      queryParameters: queryParameters,
      allowExpired: allowExpired,
    );
    final data = cached?['data'];
    if (data is List<dynamic>) {
      return data;
    }
    return const <dynamic>[];
  }

  void _recordTelemetry({
    required String method,
    required String path,
    required int durationMs,
    required DateTime occurredAt,
    required bool success,
    int? statusCode,
    bool fromCache = false,
    bool usedStaleCache = false,
  }) {
    _recentTelemetry.insert(
      0,
      ApiRequestTelemetry(
        method: method,
        path: path,
        durationMs: durationMs,
        occurredAt: occurredAt,
        success: success,
        statusCode: statusCode,
        fromCache: fromCache,
        usedStaleCache: usedStaleCache,
      ),
    );
    if (_recentTelemetry.length > 60) {
      _recentTelemetry.removeRange(60, _recentTelemetry.length);
    }
  }

  Future<Map<String, dynamic>> _performRequest({
    required String upperMethod,
    required String path,
    required String requestPath,
    required String cacheKey,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    required bool useCache,
    Duration? cacheTtl,
  }) async {
    final isGet = upperMethod == 'GET';
    final cacheGeneration = _cacheGeneration;
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _dio.request(
        requestPath,
        options: Options(method: upperMethod),
        queryParameters: queryParameters,
        data: body,
      );

      final payload = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};

      final success = payload['success'] == true;
      if (!success) {
        final message = payload['message']?.toString() ?? 'Request failed';
        final errors =
            (payload['errors'] as List?)?.map((e) => e.toString()).toList();
        final status = response.statusCode ?? 500;
        _recordTelemetry(
          method: upperMethod,
          path: path,
          durationMs: stopwatch.elapsedMilliseconds,
          occurredAt: startedAt,
          success: false,
          statusCode: status,
        );
        throw ApiException(status, message, errors: errors);
      }

      if (isGet && useCache && cacheGeneration == _cacheGeneration) {
        final ttl = cacheTtl ?? _cacheTtlForPath(path);
        await _setCachedResponse(
          cacheKey: cacheKey,
          payload: payload,
          ttl: ttl,
        );
      } else if (!isGet) {
        _cacheGeneration++;
        await _clearCacheAfterMutation(requestPath);
      }

      _recordTelemetry(
        method: upperMethod,
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        occurredAt: startedAt,
        success: true,
        statusCode: response.statusCode,
      );

      return payload;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 && !path.startsWith('/auth/') &&
          error.requestOptions.headers['Authorization'] == _dio.options.headers['Authorization']) {
        await onAuthenticationRejected?.call();
      }
      if (error.response?.statusCode == 429) {
        final header = error.response?.headers.value('retry-after');
        final seconds = int.tryParse(header ?? '') ?? 60;
        _cooldownUntil =
            DateTime.now().add(Duration(seconds: seconds.clamp(1, 86400)));
      }
      final fallback = isGet &&
              useCache &&
              ![401, 403, 429].contains(error.response?.statusCode)
          ? await _getCachedResponse(cacheKey: cacheKey, allowExpired: true)
          : null;
      if (fallback != null) {
        _recordTelemetry(
          method: upperMethod,
          path: path,
          durationMs: stopwatch.elapsedMilliseconds,
          occurredAt: startedAt,
          success: true,
          statusCode: error.response?.statusCode,
          fromCache: true,
          usedStaleCache: true,
        );
        return fallback;
      }
      final status = error.response?.statusCode ?? 500;
      final message = _friendlyDioErrorMessage(error);
      _recordTelemetry(
        method: upperMethod,
        path: path,
        durationMs: stopwatch.elapsedMilliseconds,
        occurredAt: startedAt,
        success: false,
        statusCode: status,
      );
      throw ApiException(status, message);
    }
  }

  Future<Map<String, dynamic>> request({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    bool useCache = true,
    Duration? cacheTtl,
  }) async {
    if (!path.startsWith('/auth/')) await beforeAuthenticatedRequest?.call();
    final cooldown = _cooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      throw ApiException(429,
          'Please wait ${cooldown.difference(DateTime.now()).inSeconds + 1} seconds before trying again.');
    }
    final requestPath = _normalizePathForRequest(path);
    final upperMethod = method.toUpperCase();
    final isGet = upperMethod == 'GET';
    final cacheKey = _cacheKey(requestPath, queryParameters);

    if (isGet && useCache) {
      final cached = await _getCachedResponse(cacheKey: cacheKey);
      if (cached != null) {
        _recordTelemetry(
          method: upperMethod,
          path: path,
          durationMs: 0,
          occurredAt: DateTime.now(),
          success: true,
          statusCode: 200,
          fromCache: true,
        );
        return cached;
      }
    }

    if (isGet) {
      final pending = _pendingGetRequests[cacheKey];
      if (pending != null) {
        return pending;
      }
    }

    late final Future<Map<String, dynamic>> requestFuture;
    requestFuture = _performRequest(
      upperMethod: upperMethod,
      path: path,
      requestPath: requestPath,
      cacheKey: cacheKey,
      queryParameters: queryParameters,
      body: body,
      useCache: useCache,
      cacheTtl: cacheTtl,
    ).whenComplete(() {
      if (identical(_pendingGetRequests[cacheKey], requestFuture)) {
        _pendingGetRequests.remove(cacheKey);
      }
    });

    if (isGet) {
      _pendingGetRequests[cacheKey] = requestFuture;
    }

    return requestFuture;
  }

  Future<List<dynamic>> getList({
    required String path,
    Map<String, dynamic>? queryParameters,
    Duration? cacheTtl,
    bool useCache = true,
  }) async {
    final response = await request(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      cacheTtl: cacheTtl,
      useCache: useCache,
    );
    final data = response['data'];
    if (data is List<dynamic>) return data;
    return [];
  }
}
