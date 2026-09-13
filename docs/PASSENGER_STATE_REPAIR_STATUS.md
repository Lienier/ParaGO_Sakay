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

## Phase 3 — local validation passed

- Authorized driver/admin trip rosters now include passenger display names while retaining the existing passenger ID shape. No email, phone or other profile fields are added.
- Onboard cards display passenger name and short booking identifier. Both driver unload actions use a confirmation showing the passenger, booking and destination. Duplicate dialog/action submissions for the same ride are guarded.
- Completion records include authenticated actor ID/role and the existing method/timestamp, saved with the occupancy transaction. Concurrent attempts preserve the first completion audit. Driver assignment is rechecked inside the transaction.
- No fresh passenger GPS or para alert is required for driver manual unloading. Closing the passenger app does not itself unload the passenger. Automatic separation rules are unchanged.
- Validation: all 27 driver tests passed; targeted analysis passed; combined boarding/manual-unloading/realtime backend run passed 60 tests. Final focused unloading run passed 4 tests, including a new reassignment check. Initial invalid test fixture was corrected to include saved booking coordinates, with no fresh GPS provided.
- These changes are local, not yet pushed, deployed or installed on the phone. A physical end-to-end ride walkthrough remains part of final release verification.

## Phase 4 - implemented locally; device gate pending

- Successful new logins transactionally replace previous sessions for all roles. Admin replacement occurs only after OTP verification. Refresh retains the session and absolute expiry.
- Old HTTP/refresh credentials receive SESSION_REPLACED. All clients clear credentials and show the replacement explanation, with uncached periodic profile validation to recover from missed events.
- Socket replacement revalidates current sessions to tolerate delayed events. The existing 20-second recheck with a five-second deadline remains. Offline/background client UI updates depend on connectivity and OS scheduling; server revocation still applies.
- Passed: 79 combined backend session, socket, boarding, unloading and push checks; 23 security-suite checks; all 28 driver tests; nine focused client session tests across three applications. Targeted client analysis passed.
- All 42 passenger tests passed after correcting a date-dependent announcement screenshot fixture. No screenshot baseline was changed.
- Physical two-device login replacement and the full boarding/para/unloading walkthrough remain release blockers. No deployment or APK distribution was performed.

### Single-session cutover and rollback

1. Finish device validation and prepare matching clients. Back up the database and pause API/authentication traffic across all instances for maintenance.
2. Review `node scripts/security-session-cutover.js` (dry-run description). During the separately authorized release, run it with `--apply` to revoke all existing sessions, refresh tokens, OTP challenges and reset links. Do not retain one arbitrary legacy session. Business records remain untouched.
3. Start only the updated backend, restart sockets/workers and resume traffic. Require fresh login; verify second-device rejection while active trips and rides persist.
4. Rollback must retain revocation enforcement and transactional session replacement. Never restore revoked token records or insecure authentication code; pause authentication and repair forward if necessary.

One server session is enforced per account. This is not hardware attestation: copied credentials or tabs sharing one session cannot be distinguished as separate physical devices.

## GitHub checkpoint

Phases 1–2 were committed as `b21ab4b` and pushed to `repair/passenger-state-para-alerts`. Main automatically deploys staging, so it was not updated by this GitHub checkpoint. Unrelated admin UI and tooling changes were excluded.

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
