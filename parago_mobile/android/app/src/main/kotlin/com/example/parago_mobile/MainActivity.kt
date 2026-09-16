package com.example.parago_mobile

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sakaygaray/app_release")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "buildNumber" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else info.versionCode
                        result.success(code)
                    }
                    "openDownloads" -> {
                        try {
                            startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,
                                android.net.Uri.parse("https://downloads.sakaygaray.com")))
                            result.success(true)
                        } catch (_: android.content.ActivityNotFoundException) { result.success(false) }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
