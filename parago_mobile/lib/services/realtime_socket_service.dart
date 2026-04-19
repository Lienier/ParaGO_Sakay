import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';

class RealtimeSocketService {
  static bool _disabledNoticeShown = false;
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _operationsController =
      StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;
  String? _currentSocketBaseUrl;
  String? _currentToken;
  bool _networkFailureReported = false;

  Stream<Map<String, dynamic>> get notificationCreatedStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get operationsChangedStream =>
      _operationsController.stream;
  bool get isConnected => _socket?.connected == true;
  bool get hasActiveSocket => _socket != null;

  void connect({
    required String apiBaseUrl,
    required String token,
  }) {
    if (!AppConfig.enableRealtime) {
      if (!_disabledNoticeShown) {
        debugPrint('Realtime socket disabled by PARAGO_ENABLE_REALTIME.');
        _disabledNoticeShown = true;
      }
      disconnect();
      return;
    }

    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      return;
    }

    final socketBaseUrl = _socketBaseUrl(apiBaseUrl);
    if (_socket != null &&
        _currentSocketBaseUrl == socketBaseUrl &&
        _currentToken == trimmedToken) {
      if (_socket!.connected) {
        return;
      }
      debugPrint('Realtime socket reconnecting to existing target.');
      _networkFailureReported = false;
      _socket!.connect();
      return;
    }

    disconnect();

    _currentSocketBaseUrl = socketBaseUrl;
    _currentToken = trimmedToken;
    _networkFailureReported = false;
    debugPrint('Realtime socket target: $socketBaseUrl');

    final socket = io.io(
      socketBaseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket', 'polling'])
          .setUpgrade(true)
          .enableForceNew()
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(6)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setTimeout(30000)
          .setQuery(<String, dynamic>{'token': trimmedToken})
          .setExtraHeaders(<String, dynamic>{
            'Authorization': 'Bearer $trimmedToken',
          })
          .setAuth(<String, dynamic>{'token': trimmedToken})
          .build(),
    );

    socket.onConnect((_) {
      _networkFailureReported = false;
      debugPrint('Realtime socket connected.');
    });
    socket.onDisconnect((reason) {
      debugPrint('Realtime socket disconnected: $reason');
    });
    socket.onReconnect((attempt) {
      debugPrint('Realtime socket reconnected on attempt $attempt.');
    });
    socket.onReconnectAttempt((attempt) {
      if (attempt == 1 || attempt % 3 == 0) {
        debugPrint('Realtime socket reconnect attempt $attempt.');
      }
    });
    socket.onReconnectError((error) {
      debugPrint('Realtime socket reconnect error: $error');
      _stopRetryingOnNetworkError(socket, error, source: 'reconnect');
    });
    socket.onReconnectFailed((_) {
      debugPrint('Realtime socket reconnect failed.');
    });
    socket.onConnectError((error) {
      debugPrint('Realtime socket connect error: $error');
      _stopRetryingOnNetworkError(socket, error, source: 'connect');
    });
    socket.onError((error) {
      debugPrint('Realtime socket error: $error');
      _stopRetryingOnNetworkError(socket, error, source: 'generic');
    });
    socket.on('socket.ready', (payload) {
      debugPrint('Realtime socket ready: $payload');
    });
    socket.on('notification.created', (payload) {
      final normalized = _normalizePayload(payload);
      if (normalized.isNotEmpty) {
        _notificationController.add(normalized);
      }
    });
    socket.on('ops.changed', (payload) {
      final normalized = _normalizePayload(payload);
      if (normalized.isNotEmpty) {
        _operationsController.add(normalized);
      }
    });

    _socket = socket;
    socket.connect();
  }

  void disconnect() {
    final socket = _socket;
    _socket = null;
    _currentSocketBaseUrl = null;
    _currentToken = null;
    _networkFailureReported = false;
    socket?.disconnect();
    socket?.dispose();
  }

  void dispose() {
    disconnect();
    _notificationController.close();
    _operationsController.close();
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  String _socketBaseUrl(String apiBaseUrl) {
    final trimmed = apiBaseUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }

    final scheme = uri.scheme.trim();
    final host = uri.host.trim();
    if (scheme.isEmpty || host.isEmpty) {
      return trimmed;
    }

    final explicitPort = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$explicitPort';
  }

  void _stopRetryingOnNetworkError(
    io.Socket socket,
    Object error, {
    required String source,
  }) {
    if (!identical(_socket, socket) || !_looksLikeConnectivityIssue(error)) {
      return;
    }

    if (!_networkFailureReported) {
      debugPrint(
        'Realtime socket stopped after $source network failure. Waiting for an explicit reconnect.',
      );
      _networkFailureReported = true;
    }
    disconnect();
  }

  bool _looksLikeConnectivityIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('no address associated with hostname') ||
        message.contains('socketexception') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('xmlhttprequest') ||
        message.contains('fetch');
  }
}
