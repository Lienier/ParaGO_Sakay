import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/api_exception.dart';
import '../../core/config/app_config.dart';

class _ApiCachedResponse {
  _ApiCachedResponse({required this.payload, required this.expiresAt});

  final Map<String, dynamic> payload;
  final DateTime expiresAt;
}

class ApiClient {
  ApiClient({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
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
  SharedPreferences? _cachePrefs;
  static const String _cachePrefix = 'parago_api_cache_v1:';

  Future<SharedPreferences> get _cacheStorage async {
    _cachePrefs ??= await SharedPreferences.getInstance();
    return _cachePrefs!;
  }

  String _normalizePathForRequest(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '/';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final parsedBasePath = Uri.tryParse(_dio.options.baseUrl)?.path ?? '';
    final baseHasApiV1 =
        parsedBasePath.endsWith('/api/v1') || parsedBasePath.endsWith('/api/v1/');

    var normalized = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    if (baseHasApiV1 && normalized.startsWith('api/v1/')) {
      normalized = normalized.substring(6); // remove duplicated API version
    }

    if (normalized.isEmpty) return '/';
    return normalized.startsWith('/') ? normalized : '/$normalized';
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

  Future<void> _clearAllCache() async {
    _memoryCache.clear();
    final storage = await _cacheStorage;
    final keysToRemove = storage.getKeys().where((key) => key.startsWith(_cachePrefix));
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

  Future<Map<String, dynamic>> request({
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    bool useCache = true,
    Duration? cacheTtl,
  }) async {
    final requestPath = _normalizePathForRequest(path);
    final upperMethod = method.toUpperCase();
    final isGet = upperMethod == 'GET';
    final cacheKey = _cacheKey(requestPath, queryParameters);

    if (isGet && useCache) {
      final cached = await _getCachedResponse(cacheKey: cacheKey);
      if (cached != null) {
        return cached;
      }
    }

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
        throw ApiException(status, message, errors: errors);
      }

      if (isGet && useCache) {
        final ttl = cacheTtl ?? _cacheTtlForPath(path);
        await _setCachedResponse(
          cacheKey: cacheKey,
          payload: payload,
          ttl: ttl,
        );
      } else if (!isGet) {
        await _clearAllCache();
      }

      return payload;
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 500;
      final message = error.response?.data is Map
          ? ((error.response!.data as Map)['message'] ??
                  error.message ??
                  'Network error')
              .toString()
          : error.message ?? 'Network error';
      throw ApiException(status, message);
    }
  }

  Future<List<dynamic>> getList({
    required String path,
    Map<String, dynamic>? queryParameters,
    Duration? cacheTtl,
  }) async {
    final response = await request(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      cacheTtl: cacheTtl,
    );
    final data = response['data'];
    if (data is List<dynamic>) return data;
    return [];
  }
}
