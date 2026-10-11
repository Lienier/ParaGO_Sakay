# Manual Playwright UI lab

This folder prepares an isolated local backend and synthetic records for manual browser scenario testing. It is **not a standalone automated replay suite**. Captured results from 9 October 2026 are in [the report](../../artifacts/playwright_ui_manual_2026-10-09/REPORT.md) and [the screenshot/video dashboard](../../artifacts/playwright_ui_manual_2026-10-09/index.html).

## Latest follow-up

The [Driver information and automatic trip dashboard](../../artifacts/driver_information_flow_2026-10-09/index.html) contains the later 16-check follow-up, all passing, with fixes for the original eight UI findings. It also verifies same-route pickup visibility and automatic start, departure and completion. The current Driver dependency lockfile uses `firebase_core_web` 3.12.0, so the historical compatibility shim described below is no longer needed.

To select the follow-up lab and enable both features locally, use these settings before starting `server.cjs`:

```powershell
$env:UI_LAB_ARTIFACT_DIR='artifacts/driver_information_flow_2026-10-09'
$env:UI_LAB_AUTOMATIC_LIFECYCLE='true'
$env:UI_LAB_SHARED_DRIVERS='true'
node tools/playwright-ui-manual/server.cjs
```

Build the three web apps into the corresponding follow-up subdirectories with the same loopback URL defines shown below. On Windows, pass an absolute `--output` path. Set `UI_LAB_AUTOMATIC_LIFECYCLE=false` for the disabled-rollout control check. `write-driver-information-report.py` formats captured evidence and hashes builds; it does not execute tests.

## Isolation and prerequisites

- Node dependencies from the project, Flutter, Chromium through Playwright, MongoDB Memory Server, and a dedicated Redis instance on `127.0.0.1:6398`.
- The reviewed Playwright installation was separate from project dependencies under `.tools/playwright/`.
- `fixture.cjs` disables `.env` loading, uses `NODE_ENV=test` and `DEPLOYMENT_ENV=test`, clears external service credentials, and creates a temporary loopback MongoDB replica set. Its database is `playwright_ui_manual_isolated_staging`. Redis uses a random test namespace.
- Never point these tools at a cloud database. Controls reset/delete fixture journey records and are intended only for the temporary database. They bind to loopback and are not an application feature or a deployable service.
- Automatic group booking is enabled only in this lab. Email transport is captured locally; OTP generation, validation and sessions still use real backend code.

## Browser builds

Run each command in its corresponding Flutter project. Both URL defines must point to the local API so a fallback cannot reach the live backend. Use a separate output folder if you want to preserve the reviewed bundle hashes.

```powershell
# Working directory: parago_passenger
flutter build web --release --dart-define=PARAGO_API_BASE_URL=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_API_BASE_URLS=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_ENABLE_REALTIME=true --dart-define=SAKAY_APP_BUILD=21 --output=../artifacts/playwright_ui_manual_2026-10-09/passenger-web

# Working directory: parago_mobile (Driver app)
flutter build web --release --dart-define=PARAGO_API_BASE_URL=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_API_BASE_URLS=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_ENABLE_REALTIME=true --dart-define=SAKAY_APP_BUILD=21 --output=../artifacts/playwright_ui_manual_2026-10-09/driver-web

# Working directory: parago_admin_web
flutter build web --release --dart-define=PARAGO_API_BASE_URL=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_API_BASE_URLS=http://127.0.0.1:5069/api/v1 --dart-define=PARAGO_ENABLE_REALTIME=true --output=../artifacts/playwright_ui_manual_2026-10-09/admin-web
```

The normal Driver web build failed in `firebase_core_web` 3.11.0: two `e.isA<JSObject>()` expressions do not compile under the installed Dart version. For the reviewed browser build only, a dependency copy under `.tools/ui-lab/firebase_core_web` used `(e as JSAny).isA<JSObject>()`. The Driver `.dart_tool/package_config.json` was temporarily redirected to that copy and restored afterward. Application source, pubspec/lockfiles, the global cache and APKs were unchanged by this adaptation. Resolve compatibility properly before relying on an unmodified Driver web release. Both build logs are retained in the report folder.

## Start and stop

Start the dedicated Redis instance first; do not reuse a production Redis connection. Then, from the repository root:

```powershell
node tools/playwright-ui-manual/server.cjs
```

Keep that console running. It serves Admin on 8771, Passenger on 8772 and Driver on 8773. The real API uses 5069; fixture controls use 5070. `lab-ready.json` contains these URLs. Read synthetic login details and the locally captured admin code:

```powershell
Invoke-RestMethod http://127.0.0.1:5070/fixture
Invoke-RestMethod http://127.0.0.1:5070/otp
Invoke-RestMethod http://127.0.0.1:5070/state
```

Open three independent browser contexts, with Passenger and Driver at 390 × 844 and Admin at 1440 × 844. Set geolocation permissions and fresh geolocation around latitude 14.9, longitude 121.05. Enable Flutter semantics for locator-based interaction. Keyboard entry with a short delay is more reliable than DOM fill for these Flutter forms. Exact canvas pin input may require making the map semantics overlay pointer-transparent; do not change booking logic or server data to manufacture a UI result.

Shut down the lab after review:

```powershell
Invoke-RestMethod -Method Post http://127.0.0.1:5070/shutdown
```

Stop the dedicated Redis process separately. Close Playwright contexts before closing the browser so videos are finalized. Verify no lab ports remain listening.

## Fixture controls

`POST /reset` accepts `{ "noTrip": true }` for a clean driver-start scenario, `{ "terminal": true }` for a v2 loading terminal trip, `{}` for an active v2 roadside trip, or `{ "legacy": true }` for an active legacy trip. It clears only the lab's synthetic journeys, alerts and notifications. Login sessions remain available.

`POST /fare` accepts `{ "amount": 27 }` to change the route base fare after quote review. Restore the original amount, 17, before the next price scenario.

`POST /gps` sends a real authenticated location request. Driver input accepts `actor`, `latitude`, `accuracy`, `speed` in metres/second, and `ageMs`; longitude is fixed at 121.05. Passenger input accepts `actor: "passenger"` and `latitude`. **The helper defaults an omitted driver speed to zero**, so missing-speed rejection must be tested with a direct ordered location request that omits speed, rather than with this helper. Likewise, changed streams and finer ordering cases require direct requests. Never infer missing-speed protection merely from default helper calls.

For fixture-only pagination and legacy setup, `seed-cases.cjs` accepts the actual temporary MongoDB URI and mode `drivers` or `legacy`. It refuses all URIs except `mongodb://127.0.0.1:<port>/playwright_ui_manual_isolated_staging`. Legacy setup additionally requires a flowVersion 1 active trip and the synthetic identities. It is setup, not proof of a UI operation.

## Manual scenario sequence

1. Validate empty/wrong logins, admin OTP/cooldown and successful login for all three roles. Start the driver through terminal entry, fresh GPS/loading and departure using UI controls.
2. Validate required pins, destination route order, capacity, per-member fares, changed-price rejection and a three-person roadside booking. Inspect both maps and the full destination list. Confirm the driver has no acknowledgement/count actions.
3. Keep fresh organizer and jeep locations together for the automatic boarding rule. Inspect one booking, one ride and three seats. Send drive-by, missing-speed and poor-accuracy observations, then valid stopped observations at College, Market and Nearby Stop. Observe organizer-first continuation, nearby completed-stop protection and repeated-update idempotency.
4. Send a para alert through Passenger and inspect Driver. Review Admin report counts, default range freshness and local date boundaries. Simulate a Reports 503 in Playwright routing, then restore requests and confirm recovery.
5. Repeat terminal booking entry with a current loading jeep; record the blocker rather than bypassing it with direct booking creation. Check shared-destination booking, solo cancellation, selected-member manual correction and early trip ending.
6. Prepare a legacy ride and finish it through its original controls. Check admin pagination/search, support round-trip messages, announcement validation/publication, missing route geometry, driver creation validation, narrow dispatch, signup consent/identity, saved-place guidance, logout and an unassigned driver start attempt.

Record screenshots, page exceptions, role videos, expected/observed behavior and synthetic final states. A passing named check may still have a separate visual/usability finding. Failed calibration attempts must remain in raw results; successful reruns may be adjudicated only with actual observed evidence.

`write-report.py` formats the captured review results and probes the six documented recordings with ffprobe. It does not execute browser scenarios. Run it only when those captured artifact files are present:

```powershell
python tools/playwright-ui-manual/write-report.py
```

Native GPS/background behavior, cloud staging, real push/email delivery, positive cloud document uploads and exhaustive device coverage require separate acceptance testing.
