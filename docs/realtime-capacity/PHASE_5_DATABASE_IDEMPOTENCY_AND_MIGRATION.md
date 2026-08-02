# Phase 5 Database Idempotency and Explicit Migration

Recorded: 2026-07-29

## Safety Status

Phase 5 runtime code, migration tooling, isolated tests, Atlas staging
validation, and the approved production migration are complete.

No production document, index, collection, or configuration was changed during
the audit, forensic analysis, or dry-run. The only production writes were the
subsequently approved and verified migration operations described below.

## Duplicate Audit

The fail-closed read-only audit examined production and synthetic staging:

| Environment | Ride sessions | Duplicate pickup groups | Rides in duplicate groups |
| --- | ---: | ---: | ---: |
| Production | 9 | 2 | 5 |
| Staging before migration | 2 | 0 | 0 |

Production forensic analysis found that both groups:

- Belong to the same passenger and completed trip.
- Have identical fare amounts and pickup types within each group.
- Were created within 25 milliseconds and 21 milliseconds respectively.
- Are completed and do not affect an active trip.
- Came from the characterized concurrent boarding race.

The user approved retaining the earliest-created ride in each group and
quarantining the three later-created records.

The approved redacted disposition is:

| Pickup request ref | Canonical ride ref | Quarantined ride refs |
| --- | --- | --- |
| `b99e1a55724f` | `65fa5099e626` | `2c715a7702e2` |
| `d0aeb4c84bf6` | `8d8d287be694` | `defc1f171986`, `152ece875101` |

No names, emails, credentials, or coordinates are included in this evidence.

## Runtime Remediation

### Boarding Idempotency

Boarding now:

- Runs durable ride creation, pickup completion, and occupancy increment in a
  MongoDB transaction.
- Returns the existing canonical ride for an exact pickup retry.
- Prevents two simultaneous requests from creating two rides or incrementing
  occupancy twice.
- Keeps notification publication outside the database transaction.
- Treats notification failure as non-blocking after durable boarding succeeds.
- Preserves existing automatic and manual boarding behavior.

The ride model declares a unique partial index on `pickupRequestId`. Application
startup does not create it automatically; only the explicit migration does.

### Persistent Location Ordering

Jeepney location state now stores:

- `latestLocationOrder.streamId`
- `latestLocationOrder.sequence`
- `latestLocationOrder.capturedAt`
- `latestLocationOrder.serverReceivedAt`

Ordered location persistence uses one conditional `findOneAndUpdate`. The
position and ordering metadata therefore change atomically. Duplicate
sequences, older capture times, and superseded streams remain rejected after
in-memory state is cleared, backend restart, or another API instance handles
the next request.

Legacy location payloads remain temporarily compatible until the coordinated
Phase 11 cutover.

## Controlled Indexing

Application startup previously used `autoIndex: true`, normalized user provider
IDs, and ran `User.syncIndexes()`. That uncontrolled startup behavior is
removed.

The backend now connects with `autoIndex: false`. The explicit Phase 5 migration
is the only path that:

- Removes explicitly stored null or blank provider IDs.
- Ensures the existing user identity indexes.
- Creates `uniq_ride_session_pickup_request`.
- Creates unique migration-ledger and quarantine indexes.

No speculative query indexes were added. Existing representative pickup,
active-trip, and passenger-trip queries examined one key and one document in
the staging audit.

Production currently performs a collection scan for ride lookup by pickup
request, examining all 9 ride documents. Atlas staging also selects a
collection scan for its two-document dataset even after index creation because
the dataset is too small for an index scan to be cheaper. The unique index is
therefore justified primarily as a correctness constraint; no unsupported
latency improvement is claimed.

## Migration Command

The migration identifier is:

`phase5_database_idempotency_v1`

Dry-run is the default. Apply mode requires:

- An explicit environment.
- The exact dry-run fingerprint.
- Confirmation text `QUARANTINE_DUPLICATES_AND_CREATE_INDEX`.
- For production, a verified encrypted backup manifest less than 24 hours old.

The production dry-run fingerprint is:

`165b9260d682a6258a477f44cafa964cd7e094f9a2ce099446c17fd8b5a547e3`

Apply mode:

1. Recalculates and compares the duplicate fingerprint.
2. Copies each later duplicate's full original document into
   `rideSessionDuplicateQuarantine`.
3. Records canonical ride, pickup request, reason, migration ID, and timestamp.
4. Deletes only the transactionally quarantined duplicates from active rides.
5. Cleans explicitly stored blank provider IDs.
6. Records data reconciliation in `schemaMigrations`.
7. Creates the reviewed indexes.
8. Marks the migration complete and verifies zero duplicate groups.

Interrupted runs resume from the migration ledger. Completed runs are
idempotent.

## Staging Evidence

The synthetic Atlas staging dry-run fingerprint was:

`4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`

The migration was applied to staging:

- Duplicate groups before: 0
- Duplicate groups after: 0
- Ride pickup unique index before: absent
- Ride pickup unique index after: present
- Managed Atlas transaction: passed
- Immediate second apply: no changes, idempotent

Production was not used for this validation.

## Verification

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Backend integration tests | 39 | 0 |
| Phase 5 migration integration tests | 3 included | 0 |
| Total fresh backend tests | 101 | 0 |

The integration tests use local `MongoMemoryReplSet` instances and assert
localhost database isolation. They do not connect to Atlas development,
staging, or production.

Additional verification:

- Simultaneous boarding: two successful retries, one ride, one occupancy increment.
- Persistent ordering: stale packet rejected after clearing in-memory state.
- Migration stale fingerprint: rejected without writes.
- Quarantine and migration rerun: idempotent.
- JavaScript syntax checks: passed.
- `git diff --check`: passed, with Windows line-ending warnings only.

The Phase 4 Flutter suites remain the unchanged-client baseline: 20 driver and
28 passenger tests passed, with no driver analyzer issues. A fresh Phase 5
Flutter rerun was attempted but blocked before execution by the existing local
Flutter startup lock. The blocked wrappers created by the attempt were stopped
without touching pre-existing IDE or Dart processes. Phase 5 changed no Dart
files.

## Production Migration Result

The user explicitly approved production apply with fingerprint:

`165b9260d682a6258a477f44cafa964cd7e094f9a2ce099446c17fd8b5a547e3`

The first apply invocation rejected the local backup manifest's Windows UTF-8
byte-order mark before connecting to MongoDB. No production operation occurred.
The parser was corrected to strip the marker, matching the existing restore
verifier.

The successful apply verified:

- Backup creation: `2026-07-29T07:00:24.020Z`
- Encrypted SHA-256 prefix: `9E25A613EB62`
- Backup age: within the required 24-hour window
- Approved fingerprint: exact match

Independent post-apply audit:

| Check | Result |
| --- | ---: |
| Active ride sessions | 6 |
| Quarantined duplicate rides | 3 |
| Remaining duplicate pickup groups | 0 |
| Expected canonical rides | 2 |
| Retained canonical rides | 2 |
| Completed migration ledger entries | 1 |
| Unique ride pickup index | Present |

The immediate second production apply reported:

- `applied: false`
- `idempotent: true`
- Remaining duplicate groups: 0
- Reviewed indexes: present

Phase 6 must not begin before the production result is presented and Phase 5 is
explicitly approved.
