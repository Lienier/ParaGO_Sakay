# SAKAY 1.1.0 build 22 APKs

Passenger and Driver release APKs were rebuilt from the current main source after the release follow-up fixes. Both use version **1.1.0** and build **22**. The Admin web version remains **1.1.0 build 2**.

Both APKs passed Android package/version checks, non-debuggable release checks, universal architecture checks (arm64-v8a, armeabi-v7a and x86_64), and v2 signature verification against the certificate used by the existing installations. Their full public downloads matched the local SHA-256 checksums. The build enables realtime and uses the live API with its CloudFront fallback.

| Application | Version | Build | Download | SHA-256 |
|---|---|---:|---|---|
| passenger | 1.1.0 | 22 | [APK](https://downloads.sakaygaray.com/releases/passenger/22/9806fb5b775875cdf6c217a2f1c9ebd1d965b47523ea1eb23df30c8514ca3cb8.apk) | `9806fb5b775875cdf6c217a2f1c9ebd1d965b47523ea1eb23df30c8514ca3cb8` |
| driver | 1.1.0 | 22 | [APK](https://downloads.sakaygaray.com/releases/driver/22/d558b525d2247e3514948cd4a790713b7e7cdc7f365edee64377446d65bade30.apk) | `d558b525d2247e3514948cd4a790713b7e7cdc7f365edee64377446d65bade30` |

The preceding backend follow-up passed 131 checks. This rebuild changes mobile build metadata; it introduces no further UI or journey logic changes. Physical Android installation/update and real-phone GPS acceptance were not executed. Automatic group and driver lifecycle activation remains disabled pending that acceptance. Preserve the existing required-update minimum when publishing.

Rebuild command: `./scripts/build-tester-apks.ps1 -BuildName 1.1.0 -BuildNumber 22` with Flutter on PATH. Detailed local build logs, metadata and publication proof are under `artifacts/apk_rebuild_2026-10-11/`.
