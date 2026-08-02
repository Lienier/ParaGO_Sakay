# API and Realtime Compatibility Baseline

Recorded against commit `9391296f0407f2280412cd021bc7abe174f7733e`.

## HTTP Surface

| Domain | Current behavior | Remediation compatibility rule |
| --- | --- | --- |
| Health | `/health` and `/api/v1/health` return process health | Preserve both; add non-secret readiness separately |
| Driver location | Multiple method/path compatibility attempts with `lat` and `lng` | Introduce one canonical request while coordinating new APKs |
| Passenger ETA | Authenticated trip ETA using server-owned jeep origin | Preserve response fields and Google-only failure behavior |
| Announcements | Independent active feed, revision dismissals, paginated admin history | No blocking dependency on trip or map APIs |
| Support | Authenticated passenger/driver threads and admin inbox | Preserve text, lifecycle, polling fallback, and realtime reconciliation |
| Notifications | Per-user records and unread counts | Announcements remain excluded from notification counts |
| Trips and pickup | MongoDB-backed trip, pickup, boarding, and ride state | Preserve state transitions and add idempotency before workers |

The backend currently registers both `/api/v1` routes and temporary
compatibility routes without the prefix. Their continued need must be measured
before removal; they must not be removed as part of unrelated realtime work.

## Socket Authentication and Rooms

Current authentication accepts:

- Socket auth payload token
- `Authorization: Bearer` header
- Query-string token

Current automatic rooms:

- `user:<userId>`
- `role:<role>`

Current client-requested rooms:

- `route:<routeId>`
- `trip:<tripId>`

Current subscription handlers validate only that the room key is non-empty.
They do not verify ObjectId shape, route visibility, trip membership, role, or
subscription count. Query-string token support and permissive room joins are
security remediation targets for Phase 2.

## Current Realtime Events

| Event | Audience | Compatibility requirement |
| --- | --- | --- |
| `socket.ready` | Connected user | Preserve and use to reconcile after reconnect |
| `notification.created` | User room | Preserve |
| `ops.changed` | Affected user and admin role | Preserve |
| `jeepney.location.updated` | Route, trip, and all passengers | Replace global fanout; keep route-scoped form only until coordinated cutover |
| `support.thread.created` | Support participants/admin | Preserve |
| `support.message.created` | Support participants/admin | Preserve |
| `support.thread.updated` | Support participants/admin | Preserve |
| `support.thread.read` | Support participants/admin | Preserve |
| `announcement.published` | Targeted role rooms | Preserve |
| `announcement.updated` | Targeted role rooms | Preserve |
| `announcement.archived` | Targeted role rooms | Preserve |

## Current Location Data Flow

1. Driver samples GPS as frequently as once per second.
2. Driver sends `lat` and `lng` through several compatibility method/path
   attempts.
3. Backend resolves the driver, jeepney, previous location, and active trip.
4. Backend writes the jeep location to MongoDB.
5. Backend synchronously runs destination, boarding, and offboarding logic.
6. Backend emits the location to route, trip, and global passenger rooms.
7. Passenger also performs periodic API reconciliation.

No location request stream identifier or sequence exists. Delayed requests can
therefore overwrite newer state. There is no route-level batching.

## Coordinated Protocol Target

The approved rollout is a coordinated backend/APK cutover rather than permanent
dual-protocol support.

The target driver request adds:

- `latitude`
- `longitude`
- `accuracyMeters`
- `speedMetersPerSecond`
- `headingDegrees`
- `streamId`
- `sequence`
- `capturedAt`

The target passenger event is `route.vehicles.updated`, containing one
route-level sequence and a bounded list of changed vehicles.

The final production cutover removes global location fanout and the old
single-location event only after the new APKs and backend pass staging tests.

## Phase 4 Local Contract Status

The canonical ordered driver payload and acknowledgement described above are
implemented locally. The driver now samples locally every second, transmits
every two seconds while moving and five seconds while stationary, retains only
the newest unsent coordinate, and creates a new UUID stream whenever tracking
starts.

The backend rejects duplicate sequence values, older capture times, and
superseded streams before persistence or realtime emission. A higher sequence
may repeat the same capture time for a stationary GPS fix. Legacy `lat`/`lng`
payloads and endpoint aliases remain temporarily accepted until the coordinated
Phase 11 cutover.

Ordering state is bounded but in process. It is not durable across backend
restart until the approved Phase 5 migration adds persistent latest
stream/sequence metadata.

## Phase 5 Local Contract Status

Ordered driver locations now persist the latest stream, sequence, capture time,
and server receive time in the jeepney document. MongoDB conditionally updates
the location and ordering metadata together, so clearing process memory or
handling the next packet on another API instance does not allow stale movement.

Boarding creation now runs in a MongoDB transaction. An exact pickup retry
returns its existing canonical ride, and concurrent attempts produce one ride
and one occupancy increment. The required unique partial index is declared in
the model but is created only by the explicit Phase 5 migration.

Backend startup now uses `autoIndex: false` and no longer calls `syncIndexes()`
or performs provider-ID cleanup. The idempotent migration command owns those
changes and requires an approved fingerprint. The approved production
migration is complete: three duplicate rides are quarantined, both canonical
rides remain, duplicate pickup groups are zero, and the unique pickup-request
ride index is present.

## Phase 6 Local Contract Status

Redis is an optional transient accelerator and never replaces MongoDB as the
durable source of truth. When configured, the backend requires a TLS
`rediss://` URI in production and an environment-qualified namespace.

The transient contract now covers:

- Latest jeep locations with a 60-second TTL.
- Driver-to-jeep/trip/route context with a 45-second TTL and targeted
  invalidation.
- Google passenger ETA results and distributed request coalescing.
- Token-owned locks for operations that must not run concurrently.

Redis failure leaves core operations available through MongoDB lookup, direct
location persistence, route-scoped realtime delivery, and direct ETA
processing. `/ready` reports Redis as healthy or unhealthy without returning
connection details.

The approved DigitalOcean Managed Valkey service is provisioned and validated,
but its URI is intentionally not present in the production application
environment before the later staging and coordinated deployment gates.

## Phase 7 Local Contract Status

Ordered driver locations can now use a separate worker path when
`ASYNC_LOCATION_PROCESSING_ENABLED` is explicitly enabled. The API validates
and orders the request, caches the latest transient location, coalesces
persistence per jeep, coalesces automation per trip, and acknowledges after
Redis accepts the work.

The worker persists the newest locations in five-second MongoDB bulk writes,
runs destination and ride automation under per-trip locks, retries transient
failures with bounded backoff, and exposes redacted terminal failures through
an admin-only operational endpoint. Pickup reassignment and announcement
reconciliation run under one distributed scheduler lock.

The API and worker cannot both own scheduled jobs. Worker-originated
notifications and operational events cross the process boundary through a
namespaced Redis pub/sub bridge. If Redis or queue insertion is unavailable,
the API retains the established synchronous MongoDB and automation behavior.

This path has passed isolated tests and controlled managed-Valkey validation,
but remains disabled and undeployed in production pending the Phase 8 through
10 gates.

## Phase 8 Local Contract Status

Passenger refreshes are now separated into trip, booking, notification, route,
and announcement domains. In-flight work is coalesced per domain, replacement
requests advance a generation, and stale HTTP results cannot replace a newer
domain snapshot. Support and announcement failures remain independent from
trips, bookings, maps, and vehicle markers.

The short polling loop no longer performs a full dashboard reload. Healthy
realtime uses route vehicle batches while booking and notification metadata
refresh every 45 seconds. Routes refresh every five minutes. When realtime is
disconnected or vehicle state becomes stale, the client polls only active
trips every 15 seconds.

Socket lifecycle events now gate reconnect processing. The passenger buffers
the newest location state, obtains one authoritative active-trip snapshot, and
only then applies newer buffered events. Route changes clear old subscriptions,
batch sequence, marker motion state, buffered events, and selected-jeep ETA
state.

These client changes pass isolated Flutter tests but remain undeployed pending
the Phase 9 and Phase 10 gates.

## Phase 9 Local Contract Status

The backend now trusts exactly one reverse proxy, requires an explicit
production CORS allowlist, limits request bodies to 1 MB, disables server
identification, and emits structured query-free request logs with validated
request IDs.

Every API group is rate limited. Location, ETA, support, admin, and general
limits use a verified token subject when available, so passengers and drivers
sharing a carrier IP do not consume one another's quota. Authentication and
invalid-token traffic retain a hashed client-address boundary.

API and worker shutdown are bounded and idempotent. The API stops schedulers,
HTTP, Socket.IO, route batching, Redis, and MongoDB. The worker waits for active
jobs and flushes pending locations before closing dependencies.

Hardened Nginx and non-root systemd templates are present for the later EC2
deployment. They remain templates, and live proxy/restart evidence is deferred
to isolated Phase 10 staging. No Phase 9 code is deployed to production.

## Behaviors That Must Not Regress

- Driver and passenger authentication
- Route selection and live marker rendering
- Pickup request lifecycle
- Manual and automatic boarding/offboarding
- Passenger plate, distance, seat, and Google ETA presentation
- Support chat authorization and realtime reconciliation
- Announcement targeting, revision dismissal, and resilient loading
- Notification unread counts
- Admin operational views
- OSM and `flutter_map` rendering
