# Phase 1 Characterization and Regression Evidence

Recorded: 2026-07-29

## Approval Boundary

Phase 0 was explicitly approved before this work began. Phase 1 adds isolated
tests and small testability refactors only. It does not change the public API,
Socket.IO authorization policy, location-reporting frequency, ride-state
rules, deployment configuration, production database, staging database, or
paid infrastructure.

No Phase 2 behavior has been implemented.

## Database and Service Isolation

Backend integration tests start their own MongoDB 8.0.28 process through
`mongodb-memory-server`.

The test bootstrap enforces both of these conditions before a test can run:

- The integration-test URI must use `mongodb://127.0.0.1`.
- The integration-test URI must not equal the configured `MONGO_URI`.

The tests use a local ephemeral HTTP server and local Socket.IO clients. They
do not call DigitalOcean, production Atlas, staging Atlas, Redis, AWS, Google
Routes, Firebase, or SMS providers. Test fixtures contain synthetic users,
routes, jeeps, trips, pickups, rides, and alerts only.

## Added Test Infrastructure

- Added `socket.io-client` as a development-only dependency.
- Added `npm run test:characterization`.
- Included the characterization suite in the root `npm test` command.
- Added passenger and driver realtime subscription registries so reconnect
  behavior can be tested without changing its runtime contract.
- Extracted passenger location parsing and marker matching into a policy used
  by the production screen and tests.

## Backend Characterization Coverage

The backend suite contains 12 Phase 1 characterization tests:

1. Refuses the configured Atlas URI and uses local MongoDB only.
2. Preserves driver-location authentication, role authorization, validation,
   and PATCH/POST/PUT compatibility.
3. Verifies authoritative jeep location persistence.
4. Verifies active-trip assignment fallback.
5. Verifies current synchronous automatic boarding and offboarding behavior.
6. Verifies passenger ETA role boundaries and stale-location checks before a
   Google request can occur.
7. Verifies stop-alert onboard ownership and assigned-driver boundaries.
8. Verifies Socket.IO auth-payload authentication and unauthenticated
   rejection.
9. Reproduces query-string token acceptance as a known security gap.
10. Reproduces arbitrary passenger route/trip subscriptions as a known
    security gap.
11. Reproduces role-wide unscoped passenger location delivery as a known
    privacy and capacity gap.
12. Reproduces duplicate ride creation during simultaneous boarding, while
    also verifying normal socket room cleanup on disconnect.

The concurrency test uses a test-only synchronization barrier around the
existing check-then-create boarding path. Two simultaneous accepted location
requests create two ride sessions for one pickup and increment occupancy
twice. It does not modify application behavior to manufacture the outcome.

## Flutter Characterization Coverage

Passenger tests cover:

- Route and trip subscription normalization and reconnect restoration.
- Unsubscribe and disconnect cleanup.
- Dynamic Socket.IO payload normalization.
- Numeric-string coordinate parsing and receive-time fallback.
- Marker matching priority: trip, jeepney, then active route.
- Invalid-coordinate rejection.
- Detection of an older vehicle sample while documenting that current code
  still applies it.

Driver tests cover:

- Trip subscription normalization, deduplication, and reconnect restoration.
- Unsubscribe and disposal cleanup.
- Dynamic Socket.IO payload normalization.

## Test Results

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Announcement integration tests | 6 | 0 |
| Realtime capacity characterization tests | 12 | 0 |
| Passenger Flutter full suite | 21 | 0 |
| Driver Flutter full suite | 11 | 0 |
| Total | 112 | 0 |

Additional verification:

- Targeted driver analysis: no issues.
- Targeted passenger analysis: no errors and no new Phase 1 warnings.
- Dart format check: 8 touched files, 0 changes required.
- JavaScript syntax checks: passed.
- `git diff --check`: passed.

The passenger analyzer still reports seven pre-existing unused-code warnings
in `passenger_home_screen.dart`. Phase 1 did not add those warnings. Node also
prints a non-failing `punycode` deprecation warning.

## Known Gaps and Assigned Remediation

| Reproduced behavior | Risk | Planned phase |
| --- | --- | --- |
| Socket token accepted through query string | Token exposure through URLs and logs | Phase 2 |
| Passenger can join arbitrary route/trip rooms | Cross-route or cross-user data leakage | Phase 2 |
| Location event sent to all passenger sockets | Privacy leakage and excessive fanout | Phase 2 |
| Older passenger location sample is applied | Marker can move backward | Phase 3 |
| Boarding check and create are not atomic | Duplicate rides and incorrect occupancy | Phase 5 |
| Location request performs automation synchronously | Higher API latency and failure coupling | Phase 7 |

These tests characterize current behavior. The tests for known gaps pass when
the gap is reproduced so the baseline remains deterministic. In the assigned
remediation phase, each assertion will be inverted to require secure behavior.

## Dependency Audit

The read-only npm audit reports:

| Severity | Count |
| --- | ---: |
| Low | 1 |
| Moderate | 16 |
| High | 7 |
| Critical | 2 |
| Total | 26 |

Direct dependencies represented in the report are `axios`, `express`,
`firebase-admin`, `mongoose`, and `morgan`. Remaining findings are transitive.
No automatic audit fix was run because dependency upgrades can change runtime
behavior and require a separately reviewed compatibility pass.

The workstation uses Node.js 24.13.1 while the backend declares Node.js 22.x.
The passing results are valid characterization evidence, but CI and deployment
verification should use the declared Node.js 22 runtime.

## Phase 1 Checkpoint

Phase 1 is ready for review. Advancing to Phase 2 will intentionally change
Socket.IO authentication and room-subscription behavior. It requires explicit
approval before implementation starts.
