import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeSocketService {
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;

  Stream<Map<String, dynamic>> get notificationCreatedStream =>
      _notificationController.stream;

  void connect({
    required String apiBaseUrl,
    required String token,
  }) {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      return;
    }

    disconnect();

    final socketBaseUrl = _socketBaseUrl(apiBaseUrl);
    debugPrint('Realtime socket target: $socketBaseUrl');

    final socket = io.io(
      socketBaseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['polling', 'websocket'])
          .setUpgrade(true)
          .enableForceNew()
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(5000)
          .setTimeout(30000)
          .setQuery(<String, dynamic>{'token': trimmedToken})
          .setExtraHeaders(<String, dynamic>{
            'Authorization': 'Bearer $trimmedToken',
          })
          .setAuth(<String, dynamic>{'token': trimmedToken})
          .build(),
    );

    socket.onConnect((_) {
      debugPrint('Realtime socket connected.');
    });
    socket.onDisconnect((reason) {
      debugPrint('Realtime socket disconnected: $reason');
    });
    socket.onReconnect((attempt) {
      debugPrint('Realtime socket reconnected on attempt $attempt.');
    });
    socket.onReconnectAttempt((attempt) {
      debugPrint('Realtime socket reconnect attempt $attempt.');
    });
    socket.onReconnectError((error) {
      debugPrint('Realtime socket reconnect error: $error');
    });
    socket.onReconnectFailed((_) {
      debugPrint('Realtime socket reconnect failed.');
    });
    socket.onConnectError((error) {
      debugPrint('Realtime socket connect error: $error');
    });
    socket.onError((error) {
      debugPrint('Realtime socket error: $error');
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

    _socket = socket;
    socket.connect();
  }

  void disconnect() {
    final socket = _socket;
    _socket = null;
    socket?.disconnect();
    socket?.dispose();
  }

  void dispose() {
    disconnect();
    _notificationController.close();
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
}
