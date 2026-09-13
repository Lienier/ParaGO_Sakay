import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';
import 'session_controller.dart';

class ParaSoundService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'para_alerts_v1', 'Passenger para alerts',
    description: 'Passengers requesting to get off',
    importance: Importance.high,
  );
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<String>? _tokens;

  static String? sessionId(String? token) {
    try {
      return (jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(token!.split('.')[1])))) as Map)['sid'] as String?;
    } catch (_) { return null; }
  }

  static Future<void> initialize() async {
    await _notifications.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
  }

  Future<bool> start(SessionController session) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('para_api_base_url', session.apiClient.baseUrl);
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) return false;
    Future<void> register(String token) async {
      await session.apiClient.request(method: 'PUT', path: '/notifications/push-device', body: {'token': token});
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return false;
    await register(token);
    _tokens = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(register(token).catchError((Object _) {}));
    });
    _messages = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['sessionId'] != sessionId(session.token)) return;
      unawaited(play(message.data['alertId'] ?? '', session.apiClient,
        sentAt: message.data['sentAt']).catchError((Object _) {}));
    });
    return true;
  }

  static Future<void> play(String alertId, ApiClient client, {String? sentAt, String? receipt}) async {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(alertId)) return;
    final sent = DateTime.tryParse(sentAt ?? '');
    if (sent == null || DateTime.now().difference(sent).inSeconds > 60) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final played = prefs.getStringList('para_played_ids') ?? <String>[];
    if (played.contains(alertId)) return;
    // Check session revocation and trip ownership before making any sound.
    if (receipt != null) {
      await client.request(method: 'POST', path: '/notifications/para/validate',
        body: {'receipt': receipt}, useCache: false);
    } else {
      await client.request(method: 'GET', path: '/notifications/para/$alertId', useCache: false);
    }
    await initialize();
    await _notifications.show(
      id: int.parse(alertId.substring(17), radix: 16),
      title: 'Passenger para alert', body: 'A passenger requested to get off. Check the driver app.',
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
        'para_alerts_v1', 'Passenger para alerts', importance: Importance.high,
        priority: Priority.high, onlyAlertOnce: true, playSound: true,
      )),
    );
    await prefs.setStringList('para_played_ids', [...played.skip(played.length > 99 ? played.length - 99 : 0), alertId]);
  }

  void dispose() { _messages?.cancel(); _tokens?.cancel(); }
}
