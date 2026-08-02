# Phase 3 Batched Route Location Protocol

Recorded: 2026-07-29

## Approval Boundary

Phase 2 was explicitly approved before Phase 3 began. This phase introduces a
bounded route-location batcher, a dual-protocol Socket.IO rollout, passenger
batch parsing, sequence controls, reconnect snapshots, and atomic marker-state
reconciliation.

It does not change driver reporting frequency, add stream IDs, modify database
indexes, provision Redis, create workers, deploy to DigitalOcean, or enable
the batch protocol in released passenger applications.

## Event Contract

Event name:

`route.vehicles.updated`

Example:

```json
{
  "routeId": "000000000000000000000000",
  "sequence": 42,
  "generatedAt": "2026-07-29T10:00:00.000Z",
  "vehicles": [
    {
      "tripId": "000000000000000000000001",
      "jeepneyId": "000000000000000000000002",
      "latitude": 14.5995,
      "longitude": 120.9816,
      "speedMetersPerSecond": 0,
      "headingDegrees": 0,
      "lastSeenAt": "2026-07-29T09:59:59.800Z"
    }
  ]
}
```

An authorized route subscription may receive a current-state snapshot:

```json
{
  "routeId": "000000000000000000000000",
  "sequence": 42,
  "generatedAt": "2026-07-29T10:00:01.000Z",
  "snapshot": true,
  "vehicles": []
}
```

Snapshots are emitted only when the server has retained vehicle state for the
authorized route.

## Backend Aggregation

- The newest pending update is retained per jeep and route.
- Client timestamps are not used for freshness. `lastSeenAt` is assigned from
  server receive time.
- Invalid, missing, non-finite, or out-of-range coordinates are rejected.
- Speed defaults to zero when absent or invalid.
- Heading defaults to zero when absent or outside 0 through 360 degrees.
- A route emits at most once within a one-second window.
- Every emitted non-snapshot batch increments a route-local sequence.
- A batch contains at most 100 vehicles.
- At most 200 route states are retained in process memory.
- Vehicle maps are bounded to 100 entries per route.
- The least recently active route is evicted when route capacity is reached.
- Timers are unreferenced so they cannot prevent clean process exit.

The batcher remains in-memory during this phase. Redis-backed transient state
is intentionally deferred to Phase 6.

## Dual-Protocol Rollout

The server currently emits both:

- `jeepney.location.updated`
- `route.vehicles.updated`

The legacy event remains route-scoped under Phase 2 authorization. It is not
removed until the approved coordinated protocol cutover.

The passenger feature flag is:

`PARAGO_ENABLE_ROUTE_LOCATION_BATCHES`

Its default is `false`.

When false, the passenger screen processes the legacy event and ignores route
batches. When true, it processes route batches and ignores the legacy event,
preventing duplicate marker updates during the dual-protocol period.

## Passenger Reconciliation

- Only the currently selected route is accepted.
- A lower or duplicate normal sequence is ignored.
- A reconnect snapshot can reset a sequence after a server restart only when
  its generation time is not older than the last accepted batch.
- Vehicle samples older than or equal to the last accepted jeep timestamp are
  ignored.
- Duplicate jeep entries are deduplicated, retaining the newest valid sample.
- Invalid coordinates, speed, heading, timestamps, and malformed vehicles are
  ignored.
- Parsing stops at 100 input vehicles.
- Trip matching retains the existing trip, jeepney, then live-route priority.
- A route change clears sequence and per-jeep freshness state.
- Unmatched vehicles trigger one throttled metadata reconciliation instead of
  one refresh per vehicle.
- All accepted marker states and animations from one batch are committed
  inside one `setState`.
- Existing snap, jitter, heading, speed, projection, ETA movement, camera
  follow, and interpolation behavior is retained.

## Capacity Evidence

The backend test sends 50 distinct jeep updates for one authorized route,
forces the eligible flush, and verifies:

| Measurement | Result |
| --- | ---: |
| Input jeep updates | 50 |
| `route.vehicles.updated` events | 1 |
| Vehicles in event | 50 |
| Unscoped passenger deliveries | 0 |
| Reconnect snapshot vehicles | 50 |

The passenger receives one stream event and invokes one batch reconciliation
method containing one marker-state `setState`, rather than processing 50
legacy stream events and causing up to 50 marker-state rebuilds.

## Ordering and Memory Evidence

- A 5,000-flush test ends at sequence 5,000.
- The long-running test retains one route map, one jeep entry, and no pending
  updates after flushing.
- Immediate overlapping flush attempts return no batch until the one-second
  route window elapses.
- Repeated updates for one jeep produce one newest sample.
- Oversized route and vehicle sets remain within configured bounds.
- Duplicate sequences, older normal sequences, stale vehicle timestamps,
  wrong routes, and delayed snapshots are ignored.
- A newer reconnect snapshot safely resets sequence after a simulated server
  restart.

## Verification Results

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Announcement integration tests | 6 | 0 |
| Realtime characterization and protocol tests | 20 | 0 |
| Passenger Flutter full suite | 28 | 0 |
| Driver Flutter full suite | 12 | 0 |
| Total | 128 | 0 |

The modified JavaScript files pass syntax checks. Dart formatting and
`git diff --check` pass. Targeted analysis introduces no new warning or error.
The passenger home screen still has the seven pre-existing unused-code
warnings recorded during Phases 1 and 2.

No production, staging, Google, Redis, or AWS service was contacted.

## Visual Evidence Boundary

Automated tests verify multi-jeep parsing, one-event delivery, and atomic state
application. A physical-device screen recording has not been produced in this
phase because the batch flag remains disabled and no staging deployment was
authorized. The recording should be captured during the approved DigitalOcean
staging validation, using synthetic jeeps only.

## Phase 3 Checkpoint

Phase 3 is ready for review. Advancing to Phase 4 will change the driver
location request and acknowledgement contract, add stream ordering, and alter
transmission cadence. It requires explicit approval before implementation.
