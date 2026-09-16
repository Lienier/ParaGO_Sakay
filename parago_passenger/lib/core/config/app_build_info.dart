import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppBuildInfo {
  static const channel = MethodChannel('sakaygaray/app_release');
  static int build = 0;
  static Future<void> load() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      build = await channel
              .invokeMethod<int>('buildNumber')
              .timeout(const Duration(seconds: 2)) ??
          0;
    } catch (_) {
      build = 0;
    }
  }

  static Future<bool> openDownload() async {
    try {
      return await channel.invokeMethod<bool>('openDownloads') ?? false;
    } catch (_) {
      return false;
    }
  }
}
