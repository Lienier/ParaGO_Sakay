import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parago_passenger/core/network/api_client.dart';
import 'package:parago_passenger/core/exceptions/api_exception.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('protected mutation refreshes first; 401 is surfaced without replay', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.headers.value('authorization'), 'Bearer fresh');
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"message":"Invalid or expired token"}');
      await request.response.close();
    });
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    var prepared = 0;
    var rejected = 0;
    api.beforeAuthenticatedRequest = () async { prepared++; api.setAccessToken('fresh'); };
    api.onAuthenticationRejected = () async { rejected++; };
    await expectLater(api.request(method: 'PATCH', path: '/ride-sessions/test/complete'), throwsA(isA<ApiException>()));
    expect(prepared, 1); expect(rejected, 1); expect(requests, 1);
  });
  test('429 cooldown blocks another mutation; refresh bypasses auth hook', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 429;
      request.response.headers.set('Retry-After', '60');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"message":"Wait"}');
      await request.response.close();
    });
    final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    var prepared = 0;
    api.beforeAuthenticatedRequest = () async { prepared++; };
    await expectLater(api.request(method: 'POST', path: '/auth/refresh'), throwsA(isA<ApiException>()));
    expect(prepared, 0);
    await expectLater(api.request(method: 'POST', path: '/pickup-requests'), throwsA(isA<ApiException>()));
    expect(requests, 1);
  });
}
