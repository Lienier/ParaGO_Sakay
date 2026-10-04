# Passenger booking and map revision — local verification

Updated: 2026-09-18. Changes remain local. No deployment or APK distribution performed.

## Phase status

| Phase | Status | Evidence and limits |
| --- | --- | --- |
| 1: Remote pickup, fare references, errors | Implemented; automated checks passed | Booking accepts absent/distant phone GPS; rejects missing, malformed, off-route and reversed pins. Actual boarding keeps fresh GPS and jeep proximity checks. Discount is a reference only. |
| 2: Companion journeys | Implemented; automated checks passed | Whole-group reservations, readiness, driver-confirmed boarding, partial unloading, ownership, duplicate actions, stale revisions, transfers and fare/deadline preservation tested. Groups remain disabled by default. Physical walkthrough pending. |
| 3: Follow/Free view maps | Implemented; automated checks passed | Persistent Free view, explicit Recenter, shortest-angle heading interpolation, stationary/stale GPS rejection. Physical movement and visual review pending. |
| 4: Release preparation | In progress; release not cleared | Local regressions completed as listed below. Device walkthrough, mixed-client rollout verification and final visual review remain release gates. |

## Implementation

- Booking pins no longer depend on passenger GPS. Route geometry, direction, terminal pickup and booking deadlines still apply.
- `partySize` includes the organizer. Missing values mean one. Saved per-person fare snapshots are unchanged; the regular ride total uses the actual boarded count.
- Group readiness occupies no seats and does not extend expiry. The driver confirms 1 through the reserved count. Confirmation releases unused reservations.
- Original group bookings never auto-board or auto-unload from organizer GPS, including groups reduced to one actual rider. The organizer unloads everyone remaining; drivers may unload a subset.
- Unloading uses a revision plus a stable mutation reference. Repeated operations do not release another seat. Conflicting revisions require refresh.
- Reservation, occupancy, terminal summaries and passenger-flow reports count people; request counts remain booking counts. Partial unloading is reported on its action date; final completion counts only the residual.
- Both maps retain Free view until Recenter. Stale GPS retains the view and shows a location warning. Heading changes require fresh movement; this is camera following, not turn-by-turn navigation.

## Local verification evidence

- Backend standard suite: 62 unit checks and 155 regression tests passed.
- Additional booking/group/terminal/boarding/manual-unload suite: 20 passed. Phase 4 added cancellation-versus-group-boarding, departure-versus-group-boarding, and trip-end-versus-partial-unloading races; the latter also verifies completion with new groups disabled.
- Passenger complete Flutter suite: 57 passed; the subsequently added trip-copy freshness regression and both navigation tests also passed (3 targeted tests).
- Driver complete Flutter suite: 42 passed.
- Admin complete Flutter suite: 33 passed.
- Driver and admin full analysis: clean. Passenger full analysis: no errors; eight existing unused-code warnings (seven in the home screen and one support-model import).
- Manual source review caught and repaired expiry-versus-boarding overwrite, transaction-retry update reuse, misleading group separation reminder, report ObjectId filtering, and dropped GPS timestamps when copying trip models.

## Release and rollback

1. Keep `GROUP_BOOKINGS_ENABLED=false` (also the default when absent) until compatible passenger and driver builds are deployed. The local and staging environment files now enable the verified group flow; production must set the flag explicitly in its runtime configuration.
2. Distribute compatible passenger and driver applications. Verify active clients support group readiness, count confirmation and partial completion. Old clients must not be used to operate group journeys.
3. Legacy records require no destructive migration: absent party/boarded/remaining counts are interpreted as one for active rides, and completed rides display zero remaining. Do not rewrite historical fares.
4. Use controlled accounts to walk through denied GPS remote booking, solo automatic boarding, full/partial group boarding, transfer, partial/final unload, trip end, expired booking, lost response and reconnect.
5. On both phones verify movement, stationary heading, north crossing, gestures, Recenter, boarding/unloading target transitions, stale GPS, background/resume and large-text layouts. Confirm no free browsing is overridden.
6. Only after these gates pass, explicitly enable `GROUP_BOOKINGS_ENABLED=true`. This flag is an operator rollout gate; it does not itself prove client compatibility.
7. Rollback first disables new groups. Retain group-aware API and client completion for existing group journeys. Never revert seat accounting while groups remain active; preserve existing session security.

## Not verified / remaining limits

- Partial physical passenger walkthrough passed: remote three-person booking, fare display, duplicate-booking block and acknowledgement gate. Full driver/admin and movement checks remain pending; see BOOKING_DEVICE_WALKTHROUGH.md.
- A connected Android phone now runs the local passenger preview. One blank-screen occurrence recovered after app restart; its cause remains unresolved.
- Map label/control placement and motion smoothness require visual road testing with a safely stopped operator or passenger tester.
- Existing overlapping-route ETA ambiguity is unchanged.
- No payment integration, priority reservations, notification-only pickup, discount eligibility verification or ID collection included.
- Passing automated checks does not establish zero bugs or live readiness.

Reproduce the focused backend checks with `npm run test:booking-revision`. Run `flutter test --no-pub` in each client project for its complete suite.

## Distribution preparation ? 2026-09-18

User requested GitHub push and distributable driver/passenger APKs. Version 1.0.4+11 targets the live API with the existing signing identity. Groups remain disabled by default pending the remaining device gates. Preparing APKs does not publish them through the super-admin or activate a mandatory update.
