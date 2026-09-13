# Passenger state and para-alert repair

Local work only. No deployment or APK distribution authorized by this change.

## Phase 1 — local validation passed

- Boarding publishes the saved booking and ride to the passenger after commit, independently of driver delivery.
- Passenger refreshes bypass booking cache, reload on resume, and retain completed states against delayed responses/events. Existing socket-ready reconciliation remains enabled.
- Three new database integration tests pass: manual/automatic concurrent boarding and notification failure with a retry. Occupancy changes once.
- Nineteen passenger refresh/realtime tests pass. Targeted analysis has no errors, with seven existing unused-code warnings.
- This is local verification, not a physical passenger/driver walkthrough.

## Phase 2 — local checks and controlled-device sound checks passed

- Removed driver para acknowledgement buttons, retaining visible alerts and manual unloading.
- Added Firebase data messages and local Android notification sound, with a dedicated channel, a 60-second freshness window and alert-ID deduplication.
- Push tokens are session-bound and are never included in logs or API responses. Revoked sessions are excluded from sending.
- Background playback validates a 60-second, sound-only receipt against current session and driver ownership. This avoids racing refresh-token rotation from another isolate. Receipts cannot authorize ordinary API requests.
- Added PUT/DELETE `/notifications/push-device`, authenticated GET `/notifications/para/:id`, and scoped POST `/notifications/para/validate`.
- Physical-device verification on 2026-09-13 confirmed real Firebase delivery to the controlled driver account (see walkthrough below).
- Two integration tests pass covering token registration, expiry/tampering, wrong-driver rejection, revocation and registration recovery. Driver analysis passes.
- Initial driver suite: 24 pass, one announcement golden mismatch (0.29%, 912 pixels). Compared images: relative-age text differed. Stabilized the test fixture at a one-day-old announcement without updating the baseline. Full-suite rerun: all 25 tests passed.
- Foreground/minimized/locked-phone sound, duplicate suppression, offline expiry and logged-out suppression are physically verified. Notification permission denial was checked on-device and permission restored.
- Android debug APK build succeeded. Physical delivery checks are still required; no APK has been installed or distributed.

## Phases 3 and 4 — not started

Phase 2's controlled-device sound gate is complete. Manual-unloading enhancements and single-device session enforcement remain to be implemented. Existing manual unloading remains; multiple concurrent login sessions remain possible.

## Resume validation

Run `npm run test:passenger-state`. Backend unit suite: 62 tests passed.
Connect a controlled Android driver device with USB debugging, point the test build at the local API, and verify the Phase 2 scenarios above using controlled accounts. Do not point the new client at the deployed API expecting these new endpoints to exist.

Reference: https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages

## Physical walkthrough — 2026-09-13

- Connected Android device model 2311DRK48G. Installed debug build 7 targeting only the loopback test API over USB; used an isolated temporary MongoDB and synthetic driver/route/trip records.
- Found an actual initialization failure: installed Firebase Admin SDK 14.2.0 does not expose the legacy `admin.apps` namespace used by the adapter. Updated to modular app/auth/messaging imports. Actual SDK initialization regression test and both push integration tests pass.
- Test account signed in; token registered against its local session. Real FCM accepted the messages.
- User confirmed one sound and visible notification with app open.
- Repeated alert ID stayed silent (user confirmed).
- User confirmed sound with app minimized and with phone locked.
- Offline expiry test passed: FCM accepted an alert while Android Airplane mode was on. Waited over 70 seconds, reconnected, and confirmed the expired notification was absent. User confirmed it stayed silent.
- Permission-denial check: Android confirmed POST_NOTIFICATIONS was false; FCM accepted a fresh test alert and its notification ID was not posted. Android subsequently confirmed permission was restored. Separate user audible confirmation has not been received for this case.
- Logout check passed: user signed out, a deliberate test message was sent to the old session, and the user confirmed silence with no new notification. On-device storage inspection confirmed both access and refresh tokens were absent. The harness deliberately sends directly through FCM to exercise receipt/device rejection; normal sender revocation filtering is covered by the integration tests.
- Scope of acceptance: local analysis/build/regressions plus controlled FCM device delivery. Permission denial was verified by Android state and absence of a posted notification, not by separate audible user confirmation. Live deployment and end-to-end real passenger ride flows have not been verified.
- During the walkthrough a missing USB reverse mapping left the local test build at its startup logo. Restored port 5052 forwarding and confirmed the Driver Drive screen loaded. The test build still depends on the local server and USB connection; no production startup fix is claimed.
- After the Firebase adapter fix, all 14 SDK/push/auth-security regression tests passed.
- Notification channel inspected: high importance and default notification sound. Phone initially had notification audio muted; user was asked to enable audible mode.
- This does not verify server deployment or real passenger boarding flows. No production database records were changed.
- The phone currently has the local-only test APK (build 7) installed. The temporary API runs on PC loopback port 5052 via USB forwarding; it must not be used as the normal live driver application. Test harness is in ignored `.tmp/phase2-device.cjs` and is not release code.
