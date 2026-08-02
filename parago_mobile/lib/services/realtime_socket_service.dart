import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/config/app_config.dart';
import 'realtime_subscription_registry.dart';

class RealtimeSocketService {
  static bool _disabledNoticeShown = false;
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _operationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _pickupRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _supportController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _announcementController =
      StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;
  String? _currentSocketBaseUrl;
  String? _currentToken;
  bool _networkFailureReported = false;
  Timer? _retryTimer;
  final RealtimeSubscriptionRegistry _subscriptions =
      RealtimeSubscriptionRegistry();

  Stream<Map<String, dynamic>> get notificationCreatedStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get operationsChangedStream =>
      _operationsController.stream;
  Stream<Map<String, dynamic>> get pickupRequestUpdatedStream =>
      _pickupRequestController.stream;
  Stream<Map<String, dynamic>> get supportActivityStream =>
      _supportController.stream;
  Stream<Map<String, dynamic>> get announcementActivityStream =>
      _announcementController.stream;
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
          .setExtraHeaders(<String, dynamic>{
            'Authorization': 'Bearer $trimmedToken',
          })
          .setAuth(<String, dynamic>{'token': trimmedToken})
          .build(),
    );

    socket.onConnect((_) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _networkFailureReported = false;
      debugPrint('Realtime socket connected.');
      _restoreSubscriptions();
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
      _emitReconciliationEvent(payload);
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
    socket.on('pickup_request.updated', (payload) {
      final normalized = _normalizePayload(payload);
      if (normalized.isNotEmpty) {
        _pickupRequestController.add(normalized);
      }
    });
    for (final eventName in const [
      'support.thread.created',
      'support.message.created',
      'support.thread.updated',
      'support.thread.read',
    ]) {
      socket.on(eventName, (payload) {
        _emitSupportEvent(eventName, payload);
      });
    }
    for (final eventName in const [
      'announcement.published',
      'announcement.updated',
      'announcement.archived',
    ]) {
      socket.on(eventName, (payload) {
        final normalized = _normalizePayload(payload);
        if (normalized.isNotEmpty) {
          _announcementController.add(normalized);
        }
      });
    }

    _socket = socket;
    socket.connect();
  }

  void disconnect() {
    final socket = _socket;
    _retryTimer?.cancel();
    _retryTimer = null;
    _socket = null;
    _currentSocketBaseUrl = null;
    _currentToken = null;
    _networkFailureReported = false;
    socket?.disconnect();
    socket?.dispose();
  }

  void dispose() {
    disconnect();
    _subscriptions.clear();
    _notificationController.close();
    _operationsController.close();
    _pickupRequestController.close();
    _supportController.close();
    _announcementController.close();
  }

  void subscribeToTrip(String tripId) {
    final trimmedTripId = tripId.trim();
    if (trimmedTripId.isEmpty) {
      return;
    }
    final isNewSubscription = _subscriptions.addTrip(trimmedTripId);
    if (!isNewSubscription || _socket == null || !_socket!.connected) {
      return;
    }

    _requestSubscription(
      RealtimeSubscription('subscribe.trip', trimmedTripId),
    );
  }

  void unsubscribeFromTrip(String tripId) {
    final trimmedTripId = tripId.trim();
    if (trimmedTripId.isEmpty) {
      return;
    }
    final removed = _subscriptions.removeTrip(trimmedTripId);
    if (!removed || _socket == null || !_socket!.connected) {
      return;
    }

    _requestUnsubscribe('unsubscribe.trip', trimmedTripId);
  }

  Map<String, dynamic> _normalizePayload(dynamic payload) =>
      normalizeRealtimePayload(payload);

  void _emitSupportEvent(String eventName, dynamic payload) {
    final normalized = _normalizePayload(payload);
    if (normalized.isEmpty) return;

    final nestedPayload = _normalizePayload(normalized['payload']);
    final nestedThread = _normalizePayload(normalized['thread']);
    final threadId = normalized['threadId'] ??
        normalized['id'] ??
        normalized['_id'] ??
        nestedPayload['threadId'] ??
        nestedThread['id'] ??
        nestedThread['_id'];
    _supportController.add({
      ...normalized,
      'eventName': eventName,
      'notificationType': eventName,
      if (threadId != null && threadId.toString().trim().isNotEmpty)
        'threadId': threadId.toString(),
    });
  }

  void _emitReconciliationEvent(dynamic payload) {
    final normalized = _normalizePayload(payload);
    final event = <String, dynamic>{
      ...normalized,
      'eventName': 'socket.ready',
      'notificationType': 'socket.ready',
    };
    _supportController.add(event);
    _announcementController.add(event);
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

  void _restoreSubscriptions() {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return;
    }
    for (final subscription in _subscriptions.restorationEvents) {
      _requestSubscription(subscription);
    }
    for (final subscription in _subscriptions.pendingAuthorizationEvents) {
      _requestSubscription(subscription);
    }
  }

  void _requestSubscription(RealtimeSubscription subscription) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emitWithAck(
      subscription.eventName,
      subscription.identifier,
      ack: (dynamic response, [dynamic _]) {
        final result = _normalizePayload(response);
        if (result['ok'] == true) {
          _subscriptions.markAuthorized(
            subscription.eventName,
            subscription.identifier,
          );
          debugPrint(
            'Realtime subscription authorized: '
            '${subscription.eventName} ${subscription.identifier}',
          );
          return;
        }
        _subscriptions.reject(
          subscription.eventName,
          subscription.identifier,
        );
        debugPrint(
          'Realtime subscription rejected: '
          '${result['code'] ?? 'UNKNOWN'}',
        );
      },
    );
  }

  void _requestUnsubscribe(String eventName, String identifier) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emitWithAck(
      eventName,
      identifier,
      ack: (dynamic response, [dynamic _]) {
        final result = _normalizePayload(response);
        if (result['ok'] != true) {
          debugPrint(
            'Realtime unsubscribe rejected: '
            '${result['code'] ?? 'UNKNOWN'}',
          );
        }
      },
    );
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
        'Realtime socket hit a $source network failure. Retrying in the background.',
      );
      _networkFailureReported = true;
    }
    _scheduleReconnect(socket);
  }

  void _scheduleReconnect(io.Socket socket) {
    if (_retryTimer?.isActive == true) return;
    _retryTimer = Timer(const Duration(seconds: 15), () {
      _retryTimer = null;
      if (!identical(_socket, socket) || socket.connected) return;
      _networkFailureReported = false;
      socket.connect();
    });
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
