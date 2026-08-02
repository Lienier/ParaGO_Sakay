# Phase 7 Asynchronous Workers

Recorded: 2026-07-30

## Safety Status

Phase 7 code, isolated tests, and a controlled live Valkey validation are
complete. The worker architecture has not been enabled or deployed in
production. Production continues to use the existing synchronous location
path until the later staging and coordinated deployment checkpoints.

The validation used synthetic records in an in-memory MongoDB replica set. It
did not connect to production or staging Atlas. A workstation IP was
temporarily added to the managed Valkey firewall and removed immediately after
the validation. The final firewall listing contained only the ParaGO App
Platform trusted source.

## Process Boundary

ParaGO now supports separate API and worker process types.

The API process:

- Authenticates and validates ordered driver location requests.
- Resolves the driver's active jeepney, trip, and route context.
- Rejects duplicate or stale stream sequences.
- Updates the 60-second transient latest-location cache.
- Coalesces location persistence by jeepney.
- Coalesces ride automation by trip.
- Acknowledges after Redis accepts the transient work.
- Falls back to the original synchronous MongoDB and automation path if Redis
  is unavailable or queue insertion fails.

The worker process:

- Flushes newest-per-jeep locations through MongoDB `bulkWrite` every five
  seconds.
- Persists location and ordering metadata atomically.
- Runs destination alerts and automatic boarding/offboarding.
- Serializes automation per trip with a token-owned Redis lock.
- Runs pickup reassignment and announcement reconciliation under a distributed
  scheduler lock.
- Retries transient failures with bounded exponential backoff.
- Stores terminal failures in a bounded, redacted failed-job queue.
- Publishes operational realtime events through a Redis bridge to the API
  process.

MongoDB remains the durable source of truth. Redis contains only transient
locations, pending work, retries, locks, processed idempotency markers, and
redacted failure records.

## Runtime Controls

| Variable | API value | Worker value | Purpose |
| --- | --- | --- | --- |
| `RUN_API_JOBS` | `true` | `false` | Own legacy API schedulers |
| `RUN_WORKER_JOBS` | `false` | `true` | Permit the standalone worker |
| `ASYNC_LOCATION_PROCESSING_ENABLED` | rollout controlled | not required | Enable queue-backed ordered locations |
| `WORKER_LOCATION_FLUSH_INTERVAL_MS` | n/a | default `5000` | Location persistence cadence |
| `WORKER_AUTOMATION_POLL_INTERVAL_MS` | n/a | default `1000` | Automation queue cadence |
| `WORKER_MAX_BATCH_SIZE` | n/a | default `500` | Bound one drain operation |
| `WORKER_MAX_ATTEMPTS` | n/a | default `5` | Bound retry attempts |
| `WORKER_FAILED_JOB_RETENTION` | n/a | default `1000` | Bound visible failures |

Startup fails closed if `RUN_API_JOBS` and `RUN_WORKER_JOBS` are both true.
Asynchronous location processing also refuses startup without `REDIS_URL`.
The production default leaves asynchronous processing disabled.

The standalone process starts with:

```text
npm run start:worker
```

The `Procfile` declares both `web` and `worker` process types.

## Queue And Idempotency Rules

- Fifty pending samples for one jeep occupy one location work item containing
  the newest sample.
- Multiple pending samples for one trip occupy one automation work item.
- Work payloads expire after three minutes if abandoned.
- Processed automation idempotency markers expire after 24 hours.
- A retry remains in the sorted retry queue until re-enqueue succeeds.
- Invalid retry records are removed rather than retried forever.
- Terminal failure output excludes credentials and coordinates.
- The admin-only `GET /api/v1/operations/worker` endpoint exposes queue counts
  and at most 50 redacted failures.

## Live Validation

The controlled validation produced:

```json
{
  "database": "isolated-in-memory",
  "atlasContacted": false,
  "redisTls": true,
  "asyncAcknowledgementMs": 266.48,
  "persistedBeforeWorker": false,
  "workerBulkPersisted": 1,
  "workerAutomationProcessed": 1,
  "queueLagMs": 679,
  "redisOutageFallback": true,
  "fallbackAcknowledgementMs": 18.83
}
```

This is a functional validation, not a production capacity benchmark. The
Phase 10 two-hour load test remains responsible for p95 latency, sustained
resource use, and maximum validated capacity.

## Automated Evidence

The complete backend suite passed:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Integration, characterization, and worker tests | 57 | 0 |
| Total | 119 | 0 |

The 11 focused Phase 7 tests prove:

- Newest-per-jeep coalescing.
- Worker restart recovery.
- Five-second automation-lag compliance in the controlled clock.
- Duplicate-worker trip exclusion.
- Bounded retry and terminal failure visibility.
- Failure record redaction and retention bounds.
- Atomic location/order persistence construction.
- Distributed scheduler exclusion.
- Worker-to-API event bridging without coordinates.
- Mutually exclusive process ownership.
- Redis is mandatory when asynchronous location processing is enabled.

All automated database tests use in-memory MongoDB and injected fake Redis
clients. They do not contact Atlas or managed Valkey.

## Rollback And Failure Behavior

Turning `ASYNC_LOCATION_PROCESSING_ENABLED` off restores the established
synchronous path without changing the ordered client payload. If Redis becomes
unhealthy at runtime, the API writes the location directly to MongoDB and runs
automation inline. Conditional ordering prevents a delayed worker write from
moving the vehicle backward after fallback.

A worker restart does not lose pending work held in Redis. Permanent data
continues to live in MongoDB, so clearing transient queues cannot delete rides,
fares, support threads, announcements, accounts, or trips.

## Remaining Deployment Boundary

Before production activation:

- Deploy one API and one worker to isolated DigitalOcean staging.
- Inject the same TLS Valkey URI with staging-only namespaces.
- Verify queue lag and failed-job visibility during restarts and outages.
- Complete Phases 8 through 10 and obtain explicit production approval.

No Phase 8 passenger polling changes are included in this checkpoint.
