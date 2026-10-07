# Playwright system tests

Tests the current Express backend and a locally compiled Flutter admin website. Passenger and driver workflows use Playwright's HTTP client and the real Socket.IO server; their native mobile screens are outside this suite.

The fixture disables `.env` loading, creates random JWT secrets, and starts a temporary MongoDB replica set. It requires a dedicated Redis instance on `127.0.0.1:6398`. API and website ports are `5068` and `8768`. OTP emails are captured in memory; OTP generation and verification remain real. The fixture seeds synthetic accounts, a terminal route, a jeepney, and a number-coding holiday exemption. It enables group bookings and processes GPS updates synchronously. Do not run concurrent copies: they share ports and report paths.

## Prepare

Run from the repository root with existing Node dependencies installed:

```powershell
npm install --prefix .tools/playwright --no-audit --no-fund @playwright/test@1.63.0
node .tools/playwright/node_modules/playwright/cli.js install chromium
```

Build the admin app after application changes. From `parago_admin_web`, run:

```powershell
flutter build web --release --no-pub --output=../artifacts/playwright_system_test_2026-10-06/admin-web --dart-define=PARAGO_API_BASE_URL=http://127.0.0.1:5068/api/v1 --dart-define=PARAGO_API_BASE_URLS=http://127.0.0.1:5068/api/v1 --dart-define=PARAGO_ENABLE_REALTIME=true
```

MongoDB 8.2.6 is downloaded automatically on first use and cached under `%TEMP%/parago-mongodb-binaries`. An internet connection is needed if the cache is missing. MongoDB is stopped and its temporary data removed by the fixture.

## Start dedicated Redis

Use Redis 7 or later with [redis.conf](redis.conf). This configuration listens only on loopback, uses test port 6398, and disables persistence. Redis remains a separate process so multiple sequential tests can use it.

This workspace already has portable Ubuntu Redis packages extracted under `.tools/redis-linux/root`. To start that copy in a separate PowerShell terminal:

```powershell
wsl --cd /mnt/c/Users/reineil/OneDrive/Desktop/ParaGO/.tools/redis-linux --exec env LD_LIBRARY_PATH=/mnt/c/Users/reineil/OneDrive/Desktop/ParaGO/.tools/redis-linux/root/usr/lib/x86_64-linux-gnu ./root/usr/bin/redis-server /mnt/c/Users/reineil/OneDrive/Desktop/ParaGO/tools/playwright-system/redis.conf
```

On another machine, adjust the WSL paths or use an installed Redis executable with the same configuration.

## Run and view results

From the repository root:

```powershell
node .tools/playwright/node_modules/playwright/cli.js test --config tools/playwright-system/playwright.config.cjs
node .tools/playwright/node_modules/playwright/cli.js show-report artifacts/playwright_system_test_2026-10-06/html-report
```

Use `--grep "admin browser"` to select the desktop browser test. Each run overwrites the previous Playwright reports. Screenshots, JSON results, and the HTML report are saved under `artifacts/playwright_system_test_2026-10-06`. Failure screenshots, videos, and traces are retained only on failed tests.

Flutter accessibility is explicitly activated for browser automation. Password and OTP fields use keyboard typing, and popup controls use their accessible roles. No production application source changes are required.

When finished, stop only the dedicated test Redis:

```powershell
wsl --cd /mnt/c/Users/reineil/OneDrive/Desktop/ParaGO/.tools/redis-linux --exec env LD_LIBRARY_PATH=/mnt/c/Users/reineil/OneDrive/Desktop/ParaGO/.tools/redis-linux/root/usr/lib/x86_64-linux-gnu ./root/usr/bin/redis-cli -h 127.0.0.1 -p 6398 shutdown nosave
```

## Coverage limits

This suite does not test native Android/iOS screens, physical GPS, FCM or email delivery, social login, cloud storage, external map providers, production infrastructure, or load capacity. Admin section navigation is a smoke check of successful API loading; CRUD mutations are checked through APIs, not every admin form. Seeded driver/vehicle assignment is a precondition, not a tested assignment UI flow.
