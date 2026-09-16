# Driver/passenger action repair — local implementation

Date: 2026-09-15. No deployment, account creation in the real database, APK distribution, or Git push was performed.

## Phase 1 — Manual passenger counts

Local gate passed: 57 transportation/backend tests, 30 driver tests, an additional snapshot-order regression, and clean driver analysis at the gate.

- Driver taps are serialized with distinct operation IDs. The queue is bounded at 30 pending operations; failures cancel subsequent queued taps and request count reconciliation.
- The API computes +1/-1 from the current manual count inside a transaction. An operation receipt prevents replay from applying twice. Reusing an ID for a different adjustment is rejected.
- Capacity checks retain onboard passengers and terminal reservations. A decrement cannot take manual occupancy below zero.
- Delayed trip snapshots cannot replace a snapshot with a later server `updatedAt`. Reads in flight when a mutation completes are invalidated.
- Legacy absolute-count requests must include a matching `expectedManualOccupancyCount`. Old APKs do not supply this field and will receive a conflict instead of silently overwriting counts.

Verified: concurrent increments, concurrent first submissions with the same ID, repeated receipts, wrong-driver access, capacity/zero boundaries, mixed queued taps, queue failures, stale snapshots, and existing boarding/unloading regressions.

## Phase 2 — One active passenger journey

Local gate passed: 59 transportation/backend tests, 42 passenger tests plus two new booking-policy tests. Passenger analysis reported eight existing unused-code warnings, with no compilation errors.

- The request button and submission flow block while an onboard/waiting ride or unexpired pending booking/transfer offer exists, across all jeeps and routes.
- Opening the booking dialog immediately acquires a local submission guard. Journey state is checked again before sending.
- Booking creation, boarding and transfer acceptance use a shared passenger transaction lock. Boarding checks active rides globally rather than only on the selected trip.
- Cancelled, expired and completed journeys permit new bookings. A completed pickup record does not permit a new booking while its ride remains onboard.

Verified: competing bookings for different jeeps, onboard passengers whose pickup record is completed, cancellation, expiry, completed rides and transfer regressions.

## Phase 3 — Actionable driver toasts

Local gate passed: 66 backend regressions (transportation, manual unloading and para push), 33 driver tests and clean driver analysis.

- A persistent toast on the driver surface exposes pickup acknowledgement, onboard/para-alert manual unloading and terminal departure without changing tabs.
- Requests include booking identification. Rides include the available passenger display name, booking reference and destination.
- Incoming events do not change the selected action while it remains available. The toast can be minimized; pending actions remain accessible and the existing lists are retained.
- Action buttons are disabled while their operation runs. Failures remain visible. General driver operation progress and results use in-place feedback rather than success/loading dialogs.
- Unloading and departure retain their confirmations. Acknowledgement does not board or unload a passenger. Existing para sound/push behavior is retained.
- Acknowledgement checks driver ownership before idempotent replies, rejects expired requests, and handles concurrent acknowledgement. Notification-delivery failure after saving does not turn a committed acknowledgement into a reported failure.
- The misleading terminal "Load passenger" acknowledgement label is now "Acknowledge".

Verified: stable selection, duplicate taps, minimizing, failed actions and long content at 390×844; backend ownership, expiry, concurrent acknowledgement and no unintended ride creation. No new physical-device walkthrough or audible delivery test was performed in this session.

## Phase 4 — Admin driver creation

Local gate passed: 10 backend creation/document tests; 32 tests in the full admin suite plus the added failed-save retention regression (three focused form cases passed); clean admin analysis. Successful form submission and failed-save recovery both preserve all expected fields and both image selections.

Confirmed local defect: the creation dialog used a lazy ListView for Form fields. Scrolling could remove earlier fields from the active form. A regression entering an email and scrolling to submit failed before repair and passed afterward. This can prevent Form.save from collecting values even when the user filled them in.

- The creation form now uses a scrollable Column, retaining all fields and selected image values throughout submission.
- Save operations have duplicate-submission guards; the local saving state is cleared in a finally block.
- Image processing/uploads finish before opening the database transaction. Database changes use transaction retries, preserving atomic account/profile/vehicle creation.
- Corrupt images return a validation error. Storage failures return an explicit service-unavailable error. The image preview has a failure fallback.
- Multipart requests have a 90-second response timeout; ordinary request timeouts remain unchanged.
- Failed creation cleans uploaded objects when the database confirms no driver was saved. If commit outcome/database state is unknown, documents are preserved and the administrator is told to refresh the list before retrying.
- Existing email and vehicle uniqueness prevent duplicate creation. A lost-response retry may return a conflict; refresh the driver list to identify the existing account. This is not an automatic successful replay of the original create request.

Verified: complete multipart backend creation with both images and no GPS; duplicate email/plate protection; storage failure; second-image cleanup; corrupt images; concurrent creation and retries. The full form submission test uses simulated image selection and an API double; backend creation uses an isolated MongoDB replica set and an S3 test double.

The backend accepted a complete form before this repair when tested with working simulated storage. The form bug is confirmed, but the original deployed failure cannot be attributed exclusively to it without the original error or live logs. AWS CLI reported missing credentials in this session; deployed bucket/IAM verification remains outstanding.

## Release requirements and limitations

1. Coordinate the API and rebuilt driver APK rollout: old count requests are intentionally rejected. Do not deploy this API change alone and expect old APK manual counts to work.
2. New MongoDB data consists of the occupancy operation receipt collection and an incremented passenger journey revision (existing passengers are initialized on first write). Retain receipts while retries for their trips remain possible. No business records are deleted.
3. Verify the deployed API role can use the configured document bucket and that real admin creation succeeds with controlled data.
4. Perform a physical-device walkthrough of rapid counts, pickup acknowledgement, para alert and manual unloading before distributing APKs. Phone sound delivery remains subject to notification permissions, background restrictions and sound settings.
5. Review any pre-existing duplicate passenger journeys separately; the new write guards prevent additional competing journeys but do not silently cancel old records.
6. A network timeout can leave a count operation's outcome uncertain. The app cancels the remaining queued batch and refreshes; drivers should verify the authoritative count before entering further adjustments.
7. External storage and MongoDB do not share a transaction. Uploads may need reconciliation after a process crash or unknown commit result; preserving possible live documents takes precedence over deleting them blindly.

Test logs are kept locally under artifacts/phase1-backend-tests.log, artifacts/phase2-backend-tests.log, artifacts/phase3-regressions.log, artifacts/phase4-backend-tests.log and artifacts/final-repair-backend.log. Passing local tests does not guarantee absence of future failures or certify the deployed environment.

## Final verification

- `npm test`: 62 unit tests and 155 integration/scaffold tests passed with the new creation integration suite included in the normal command.
- Driver: 33 tests passed; analysis clean.
- Passenger: 44 tests passed; analysis retains the eight existing unused-code warnings listed below.
- Admin: full suite (32 cases at that run) passed, then the three focused form cases passed after adding failed-save recovery coverage. Analysis clean.
- Manual review followed API authorization, transaction lock ordering, duplicate operations, stale responses, notification-after-commit behavior, form field lifetime, external upload cleanup and ambiguous commit handling.
- No real-email sending, live database writes, production deployment, APK build or physical-device validation was performed.

Existing passenger warnings: unused latlong import in support_thread.dart; unused _showSupportBottomSheet, _routeQuickMeta, _buildSelectedRouteCard, _buildRideSnapshotCard, _PassengerMapLabel and _SectionHeader declarations; unused _SectionHeader.trailing parameter.

## Release preparation requested after local acceptance

Both mobile applications are version 1.0.2 (build 9), superseding build 8. Release builds use the existing signing identity and include ARM32, ARM64 and x86_64. For this coordinated repair, both API URL build settings point to https://api.sakaygaray.com/api/v1; these APKs do not fall back to a backend that may lack the new occupancy protocol.

Distribution paths: dist/android-apk/sakaygaray-driver-release.apk and dist/android-apk/sakaygaray-passenger-release.apk. Actual APK hashes, certificate checks and the source commit are recorded in the local distribution manifest after successful builds. Pushing main triggers the existing AWS deployment workflow; its result must be checked separately from APK build success.


## Immediate driver count feedback (2026-09-16)

Driver +/- taps now update the walk-in and onboard display immediately while a 300 ms trailing debounce delays persistence. Continuous tapping releases the debounce within one second. The existing ordered one-seat API operations and distinct operation IDs are retained; no taps are dropped or combined into an unsafe absolute count. The preview is held separately from server snapshots so echoed updates cannot count a pending tap twice. Zero/capacity guards use the preview, with server-side reservations/capacity validation remaining authoritative. Failed operations clear the preview, cancel the remaining batch and request reconciliation. The 30-pending-operation bound remains.

Verification: all 36 driver tests passed, including trailing debounce, continuous taps, distinct IDs, optimistic mixed taps during a server response, failure cleanup, ordered persistence and stale snapshots. No backend changes, deployment, APK rebuild or physical-device walkthrough were performed for this update. Displayed pending counts remain provisional until accepted by the server.
