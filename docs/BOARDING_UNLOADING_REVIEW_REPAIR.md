# Boarding and unloading review repair - 2026-09-10

This is a local follow-up to deployed commit 71b3e19. No deployment or APK rebuild was performed in this follow-up.

## Phase 1: boarding

Repeated validation returns the passenger's existing ride for the same booking, including when the preceding GPS upload already auto-boarded the passenger. Saved-destination validation still precedes the retry response. Manual roadside boarding requires fresh stored passenger/vehicle GPS and proximity to the assigned jeep, in addition to the pickup-area check. Expiry and the manual boarding time window are rechecked inside the transaction, after acquiring the terminal queue lock when applicable.

Review covered request ordering (GPS upload followed by explicit boarding), lost responses, cancellation, departure, trip end and capacity. Targeted existing regressions passed; new tests cover retry occupancy, a distant assigned jeep and expiry between initial validation and commit.

## Phase 2: unloading responses

Post-commit notification failures are isolated per recipient and logged without changing the successful completion response. Ride/occupancy/alert changes remain transactional. The injected-failure test initially failed because the HTTP route uses uppercase PASSENGER while the completion service compared lowercase passenger. Normalizing actorRole fixed driver notification selection; the rerun passed all five selected completion/GPS regressions.

Notifications remain best effort, not a durable retry outbox. A committed ride must be reconciled from the API if notification delivery is unavailable. This change deliberately does not pretend that an already-committed unload failed or repeat occupancy changes to resend a notification.

## Phase 3: GPS ordering and workers

Passenger location storage now conditionally accepts only newer timestamps. Old/duplicate uploads receive an explicit ignored response and do not trigger automation. Worker freshness uses processing time, preserves capture time in the vehicle observation, and skips expired/future automation jobs. Automatic boarding rejects future-dated observations. Worker tests cover expired jobs, fresh job timestamps and concurrent processing.

## Verification limits

Final combined verification: `node --test tests/realtime-capacity.characterization.test.js tests/async-worker.test.js` passed all 65 tests, with zero failures or skipped tests. `git diff --check` also passed. Manual source review covered request ordering, transaction boundaries, GPS freshness and post-commit failure handling alongside these tests. No application UI behavior, authentication scheme, database index or saved fare was changed in this follow-up. Existing deployed APK build 6 can consume the unchanged endpoint shapes once these backend changes are deployed.

Live two-phone validation is still required: delayed/lost boarding response, driver still approaching pickup, GPS loss, expired reservation, para alert, unload notifications, occupancy and terminal departure. GPS proximity cannot prove that a person physically entered a jeep, and automatic roadside boarding remains proximity-based. Background location and previously noted screenshot/ETA limitations are not solved by these backend changes.
