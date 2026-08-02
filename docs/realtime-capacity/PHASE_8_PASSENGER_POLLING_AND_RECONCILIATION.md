# Phase 8 Passenger Polling and Reconciliation

Recorded: 2026-08-02

## Safety Status

Phase 8 passenger code and isolated tests are complete. The changes are not
deployed to production and no APK has been published from this checkpoint.
Production users therefore remain on the existing client behavior until the
later staging and coordinated cutover gates.

This phase changes client reconciliation only. It does not modify production
MongoDB, managed Valkey, backend environment variables, trips, rides, support
threads, announcements, or accounts.

## Refresh Boundary

The passenger dashboard no longer performs a complete dashboard reload every
short polling interval. Refresh work is separated into these domains:

| Domain | Normal trigger | Failure behavior |
| --- | --- | --- |
| Trips and vehicle metadata | Stale or disconnected realtime, unmatched vehicle event, reconnect | Preserve the last trip and marker snapshot |
| Pickup requests and rides | 45-second metadata cadence or affected notification | Preserve the last booking snapshot |
| Notifications | 45-second metadata cadence or incomplete notification event | Preserve the last notification snapshot |
| Routes | Initial load and five-minute metadata cadence | Preserve the last route list |
| Announcements | Existing 30-second best-effort controller and announcement events | Preserve the last successful list, or show none on first failure |
| Support | Support screen polling and support events | Remains independent from the dashboard and map |

One in-flight request is coalesced per domain. A replacement request receives a
new generation, and an older result is marked stale so it cannot overwrite the
newer state. Failures are caught per domain rather than by one broad
`Future.wait` operation.

## Realtime Reconciliation

The socket service now exposes connected, disconnected, and ready lifecycle
events without exposing authentication data.

After initial core data loads, the passenger client connects its socket and
subscribes to the selected route. On reconnect:

1. Location events are temporarily buffered by jeep or as the newest route
   batch.
2. The client requests one fresh active-trip snapshot.
3. The snapshot is applied before buffered location events.
4. A second ready event during reconciliation queues one additional snapshot
   rather than starting duplicate concurrent work.
5. Metadata and announcements reconcile independently afterward.

The buffer retains at most one legacy location per vehicle, is bounded to 100
vehicles, and retains only the newest route batch. It is cleared on disconnect
and route change.

## Route Cleanup

Changing routes now performs one coordinated cleanup:

- Unsubscribe from the previous authorized route.
- Subscribe to the new route.
- Reset route batch sequence and vehicle freshness state.
- Remove marker animation and vehicle state from the previous route.
- Discard buffered events from the previous route.
- Invalidate the selected-jeep ETA request and restart its periodic timer.

This prevents delayed events or HTTP responses from restoring markers and ETA
state belonging to a route the passenger has left.

## Request Opportunity Comparison

The following figures describe scheduled refresh opportunities, not measured
server traffic. API caching and event-driven updates can reduce actual network
requests further.

| Condition | Previous behavior | Phase 8 behavior |
| --- | ---: | ---: |
| Healthy realtime metadata cadence | Four-domain refresh effectively about every 16 seconds | Booking/ride/notification refresh every 45 seconds; routes every five minutes |
| Stale or disconnected realtime | Five-domain dashboard reload every 8 seconds | Trip-only fallback every 15 seconds plus independent 45-second metadata refresh |
| One unmatched vehicle event | Full metadata or dashboard reload | Trip domain only, coalesced and throttled |
| Announcement event | Announcement endpoint only | Announcement endpoint only, unchanged |

At the scheduler level, disconnected trip polling falls from up to 7.5 broad
reload opportunities per minute to four trip-only opportunities per minute.
The Phase 10 network harness will measure actual request counts and p95 latency.

## Automated Evidence

The passenger test suite passed:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Passenger Flutter tests | 33 | 0 |

The five focused Phase 8 tests prove:

- Concurrent requests for one domain are coalesced.
- A replacement generation prevents an older HTTP response from winning.
- One failed endpoint does not block another domain or a later retry.
- Reconnect buffering keeps only the newest state until snapshot completion.
- Disconnect and route changes discard unsafe buffered events.

Existing tests also continue to prove announcement endpoint failure isolation,
stale announcement revision handling, long announcement wrapping, route batch
ordering, route sequence reset, and support-thread creation without freezing.

Targeted Flutter analysis reports no errors. Eight existing unused-code
warnings remain in the passenger project and are unrelated to Phase 8.

## Deployment Boundary

Phase 8 remains local. Before production activation it must pass:

- Phase 9 proxy, rate-limit, and deployment hardening.
- Phase 10 isolated DigitalOcean staging and load validation.
- The coordinated APK/backend protocol cutover in Phase 11.

No production capacity or latency claim is made from these client tests.
