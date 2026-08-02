# Phase 4 Adaptive Driver Reporting and Ordering

Recorded: 2026-07-29

## Approval Boundary

Phase 3 was explicitly approved before Phase 4 began. This phase changes the
driver location request and acknowledgement contract, adds bounded in-process
ordering, reduces normal reporting frequency, coalesces network backlog, and
adds immediate reporting hooks.

It does not add database indexes or persistent ordering metadata, provision
Redis, create asynchronous workers, change automatic ride-state timing, deploy
to DigitalOcean, or begin AWS migration.

## Driver Request Contract

The canonical driver request is:

```json
{
  "latitude": 14.5995,
  "longitude": 120.9816,
  "accuracyMeters": 5.2,
  "speedMetersPerSecond": 8.4,
  "headingDegrees": 91,
  "streamId": "11111111-1111-4111-8111-111111111111",
  "sequence": 42,
  "capturedAt": "2026-07-29T12:00:00.000Z"
}
```

The successful acknowledgement is:

```json
{
  "success": true,
  "message": "Location updated",
  "data": {
    "accepted": true,
    "streamId": "11111111-1111-4111-8111-111111111111",
    "sequence": 42,
    "serverReceivedAt": "2026-07-29T12:00:00.200Z"
  }
}
```

Duplicate, older-sequence, older-capture, and superseded-stream requests return
HTTP `409`. The current accepted stream and sequence are returned in the first
entry of `errors`, allowing clients to recognize an explicit stale rejection.

The backend temporarily accepts legacy `{ "lat": 0, "lng": 0 }` payloads and
all existing method/path aliases. This compatibility remains only for the
coordinated APK/backend cutover in Phase 11.

## Validation and Ordering

- Ordered payloads are limited to 2,048 bytes.
- Latitude and longitude must be finite and in geographic bounds.
- Accuracy must be between 0 and 500 meters.
- Speed must be between 0 and 100 meters per second.
- Heading must be at least zero and below 360 degrees.
- Stream IDs must be UUIDs.
- Sequence must be a positive safe integer.
- Capture timestamps may be at most ten minutes old or 30 seconds in the
  future.
- The server uses receive time for `lastSeenAt`, WebSocket freshness, and the
  acknowledgement.
- A higher sequence in one stream may repeat the same capture timestamp. This
  supports stationary devices that reuse one GPS fix without allowing an older
  capture timestamp to move the vehicle backward.
- A new stream must have a capture timestamp newer than the retained previous
  stream.
- Ordering is reserved before persistence, automation, or realtime emission,
  closing concurrent request races.
- Ordering state is bounded to 5,000 jeepneys.

Ordering is in process during Phase 4. A backend restart clears it. Persistent
latest stream/sequence metadata is intentionally deferred to the explicit
Phase 5 schema migration.

## Adaptive Driver Behavior

- GPS remains sampled locally every second when Android supplies samples.
- The local driver marker receives every accepted local sample independently
  of backend transmission.
- Moving transmission cadence is two seconds.
- Stationary transmission cadence is five seconds.
- The first sample in a tracking session sends immediately.
- Meaningful movement of at least 15 meters sends immediately.
- A moving heading change of at least 25 degrees sends immediately.
- Availability changes, recovered connectivity, detected trip/route context
  changes, tracking start, and tracking stop request an immediate latest
  position.
- Every transmission attempt increments sequence exactly once.
- A tracking restart creates a cryptographically random UUID v4 stream and
  resets sequence to one.
- While HTTP is in flight, only the newest unsent sample is retained.
- A failed or explicitly stale request is never automatically retried.
- A later sample or explicit reconnect flush sends the newest coordinate with
  a new sequence.
- GPS fallback requests are coalesced so only one recovery request can be in
  flight.

## Staging Safety Guard

Physical validation exposed that the ignored staging file uses
`STAGING_MONGO_URI`, while the normal backend reads `MONGO_URI`. The first
manual launcher inherited the default database configuration and was stopped.

A read-only audit covering the complete contact window found:

| Production audit item | Result |
| --- | ---: |
| Announcement updates | 0 |
| Pickup-request updates | 0 |
| Reassignment notifications | 0 |
| Driver location calls | 0 |

No production mutation was found. The user explicitly approved resuming after
the audit.

The new `scripts/start-staging.js` launcher now fails closed:

- Reads `STAGING_MONGO_URI` explicitly.
- Refuses an identical production/staging URI.
- Requires database `parago_staging`.
- Requires a different MongoDB host from production.
- Requires staging to use Atlas SRV syntax.
- Logs only database, host, and a redacted URI fingerprint.
- Overrides JWT credentials with staging-only values.
- Clears Google, TomTom, Firebase, SMS, and CORS production integrations.
- Accepts only validated ports from 1024 through 65535.

The guarded physical run logged:

```text
target=parago_staging
fingerprint=11df22212485
ephemeralJwt=false
```

The fingerprint matches the staging target recorded during the incident audit.
Persistent random staging-only JWT secrets are stored only in ignored
`.env.staging`.

## Physical Device Evidence

Device:

- Xiaomi `2311DRK48G`
- Android 16
- Physical device ID `W4VOAI7D4LHUS8QG`
- USB reverse from device port 5001 to guarded local staging port 5001

The first guarded physical run produced one stream and these accepted
server-receive timestamps:

| Sequence | Server receive time | Gap |
| ---: | --- | ---: |
| 3 | `12:07:38.172Z` | - |
| 4 | `12:07:43.162Z` | 4.990 s |
| 5 | `12:07:48.164Z` | 5.002 s |
| 6 | `12:07:53.157Z` | 4.993 s |

This demonstrates the stationary five-second cadence. Sequence 2 exposed the
equal-capture-time edge and returned `409`; the rule was corrected and a
dedicated integration test now proves that sequence 2 with the same capture
time is accepted.

During the corrected physical rerun, Android started the foreground location
service but could not obtain a GNSS fix. Recovery calls timed out after four
seconds. No corrected physical packet could therefore be generated in that
run. This limitation is recorded rather than represented as a passing physical
GPS result. The repeated-fix correction, moving/stationary cadence, immediate
movement/heading behavior, restart streams, reconnect flushing, and backlog
coalescing are covered by deterministic automated tests.

## Verification Results

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Announcement, realtime, and staging-guard integration tests | 36 | 0 |
| Driver Flutter full suite | 20 | 0 |
| Passenger Flutter regression suite | 28 | 0 |
| Total | 146 | 0 |

The full driver analyzer reports no issues. JavaScript syntax is exercised by
the complete backend suite. Dart formatting and `git diff --check` pass.

## Deferred Work

- Persistent ordering recovery belongs to Phase 5.
- Redis ordering/cache coordination belongs to Phase 6.
- Moving automation and persistence off the request path belongs to Phase 7.
- Production protocol cutover and legacy payload removal belong to Phase 11.
- No production deployment, Redis provisioning, database migration, or AWS
  resource change occurred in this phase.

## Phase 4 Checkpoint

Phase 4 implementation and automated verification are complete. The physical
device proves stationary cadence but the final corrected rerun remains limited
by unavailable GNSS. Phase 5 must not begin until the user reviews this evidence
and explicitly approves the database idempotency and migration phase.
