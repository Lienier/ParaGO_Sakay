import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage({SharedPreferences? prefs}) : _prefs = prefs;
  SharedPreferences? _prefs;

  static const _accessKey = 'parago_access_token';
  static const _refreshKey = 'parago_refresh_token';

  Future<void> _ensure() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _ensure();
    await _prefs!.setString(_accessKey, accessToken);
    await _prefs!.setString(_refreshKey, refreshToken);
  }

  Future<Map<String, String?>> loadTokens() async {
    await _ensure();
    return {
      'accessToken': _prefs!.getString(_accessKey),
      'refreshToken': _prefs!.getString(_refreshKey),
    };
  }

  Future<void> clearTokens() async {
    await _ensure();
    await _prefs!.remove(_accessKey);
    await _prefs!.remove(_refreshKey);
  }
}
