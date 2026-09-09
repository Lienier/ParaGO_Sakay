# Mobile ride reliability repair - 2026-09-09

Implemented locally, not deployed or packaged into APKs.

## Changes

- Both mobile API clients now run serialized session preparation and Retry-After cooldown checks on normal requests instead of cache snapshot reads. Protected HTTP 401 responses clear the rejected current session; responses for a superseded token do not clear the new session. Ride mutations are never automatically replayed.
- Passenger ride-location refresh is attempted every five seconds while onboard or awaiting acknowledged boarding. GPS fixes must have their original capture timestamp within 15 seconds and accuracy within 35 metres. Cached fallback fixes are checked too, and forced boarding refresh does not fall back to an old position when acquisition fails. Capture timestamps accompany location uploads and are checked by the server.
- Passenger location failures now explain that automation may be unavailable; a later successful upload restores the status. Destination guidance distinguishes automatic para from separation-based unloading.
- Ride completion, occupancy decrement and stop-alert dismissal now commit in one MongoDB transaction. Concurrent completions decrement occupancy only once.
- Offboarding counts each passenger sample once using a conditional atomic update. Concurrent passenger/driver evaluations cannot count one sample repeatedly. Observation gaps over 15 seconds restart the sequence.

## Verification

- 58 backend characterization/worker tests passed, including boarding, cancellation, capacity, departure, ending trips, socket revocation and new repair regressions.
- New database tests: concurrent completion, injected-write rollback, duplicate sample races followed by distinct fresh samples, stale captured GPS rejection.
- 40 passenger and 24 driver functional tests passed. Focused final session/GPS tests also passed after the final edits.
- Real local HTTP tests exercise the actual API clients: refresh preparation before a mutation, no replay after 401, authentication-endpoint recursion avoidance and 429 cooldown enforcement.
- Driver modified-file analysis clean. Passenger analysis has seven pre-existing unused-code warnings and no errors in the checked files.
- Full mobile suites each retain one announcement screenshot mismatch (small regions inspected in the generated differences). Baselines were not overwritten because this repair changes no announcement rendering. These are not counted as passing tests.

## Release and remaining limits

Deploy backend and install rebuilt passenger/driver APKs before device acceptance. Verify an expiring session, denied/weak GPS, connection loss, explicit boarding, para, three distinct separated samples, manual unload, occupancy, terminal departure and end trip using controlled accounts. No live account/session or business record was changed during this work.

Older clients omit capturedAt; the backend retains receipt-time compatibility for them. Only updated clients provide the stronger capture-time freshness guarantee. A forced-close/backgrounded passenger app still cannot guarantee GPS reporting; manual unloading remains available after session recovery. The current fix does not introduce a background location service.

Notifications publish after transaction commit. A delivery failure cannot partially commit occupancy/ride changes, but notification delivery is not a durable outbox guarantee; clients reconcile authoritative ride state. Previously inconsistent ride/occupancy records need a separate read-only audit before any data correction. Existing overlapping-route ETA ambiguity remains outside this repair.
