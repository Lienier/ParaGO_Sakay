# Phase 2 Socket Authorization and Route Scoping

Recorded: 2026-07-29

## Approval Boundary

Phase 1 was explicitly approved before Phase 2 began. This phase changes only
Socket.IO authentication, subscription authorization, room scoping, client
subscription acknowledgement handling, and location-event fanout.

It does not implement route batching, adaptive driver reporting, database
migrations, Redis, workers, AWS infrastructure, or a production deployment.
No production or staging service was contacted during verification.

## Authentication Contract

Socket.IO access tokens are accepted from either:

1. The Socket.IO auth payload:

```json
{
  "auth": {
    "token": "<access-token>"
  }
}
```

2. The `Authorization: Bearer <access-token>` handshake header.

Tokens supplied only through the connection query string are rejected. The
passenger and driver clients no longer add a token to their Socket.IO query
parameters.

## Subscription Contract

Clients continue to use these event names:

- `subscribe.route`
- `unsubscribe.route`
- `subscribe.trip`
- `unsubscribe.trip`

Every event requires a 24-character MongoDB ObjectId and supports a Socket.IO
acknowledgement callback.

Successful subscription acknowledgement:

```json
{
  "ok": true,
  "eventName": "subscribe.route",
  "resourceType": "route",
  "resourceId": "000000000000000000000000",
  "alreadySubscribed": false
}
```

When a passenger changes routes, the acknowledgement may also include:

```json
{
  "replacedRouteId": "000000000000000000000001"
}
```

Rejected subscription acknowledgement:

```json
{
  "ok": false,
  "eventName": "subscribe.trip",
  "code": "FORBIDDEN",
  "message": "You are not authorized for this subscription",
  "resourceId": "000000000000000000000000"
}
```

Possible rejection codes are:

- `INVALID_IDENTIFIER`
- `NOT_FOUND`
- `FORBIDDEN`
- `RATE_LIMITED`
- `ROOM_LIMIT`
- `AUTHORIZATION_UNAVAILABLE`

## Authorization Rules

### Route Rooms

- Passengers may subscribe to one active route at a time.
- A successful passenger route change removes the previous route room.
- Drivers may subscribe only to their active assigned route.
- Admins may subscribe to an existing route for operational access.
- Inactive routes are rejected for passengers and drivers.

### Trip Rooms

- Drivers may subscribe only when their driver profile is assigned to the
  scheduled or active trip.
- Passengers may subscribe only when they have a pending or acknowledged
  pickup request, or a waiting or onboard ride, for the scheduled or active
  trip.
- Admins may subscribe to an existing trip for operational access.
- Unrelated passenger and driver accounts are rejected.

## Abuse Controls

- A socket may hold at most eight custom route/trip rooms.
- A socket may make at most 20 subscription or unsubscription requests in a
  rolling 10-second window.
- Malformed and oversized identifiers are rejected before database access.
- Reflected identifiers in logs and acknowledgements are limited to 64
  characters.
- Rejections produce structured `socket.subscription.rejected` log entries.
- Rejection logs include the event, reason, user ID, role, socket ID, bounded
  resource ID, and timestamp.
- Logs do not contain access tokens or passenger coordinates.

## Client Reconnect Behavior

Passenger and driver registries now distinguish requested subscriptions from
server-authorized subscriptions.

- A successful acknowledgement marks the room as authorized.
- A rejected acknowledgement removes the room from reconnect state.
- Previously authorized rooms are reauthorized after reconnect.
- Requests made while disconnected remain pending and are authorized after the
  connection returns.
- Passenger route state holds only one desired route.
- Disconnect and disposal cleanup removes stale registry state according to
  each screen's existing lifecycle.

## Location Delivery Comparison

Phase 1 baseline behavior invoked three broadcast paths for every location:

1. Selected route room.
2. Specific trip room.
3. Entire passenger role room.

A passenger present in both route and trip rooms could therefore receive the
same update three times, while an unscoped passenger received it once.

Phase 2 invokes only the authorized route-room path. The automated test places
one passenger in both an authorized route and trip room, sends one location
update, and verifies:

| Recipient | Phase 1 paths | Phase 2 deliveries |
| --- | ---: | ---: |
| Authorized route and trip member | Up to 3 | 1 |
| Authenticated but unscoped passenger | 1 | 0 |

The legacy event name `jeepney.location.updated` is preserved for the
coordinated protocol cutover in Phase 3.

## Verification Coverage

The isolated backend suite verifies:

- Auth-payload and authorization-header authentication.
- Query-string token rejection.
- MongoDB ObjectId validation.
- Active-route enforcement and one-route replacement.
- Assigned-driver trip access.
- Associated-passenger trip access.
- Admin operational access.
- Cross-route and cross-trip non-delivery.
- One scoped location delivery and zero unscoped deliveries.
- Room cleanup after disconnect.
- Maximum custom-room enforcement.
- Per-socket subscription throttling.
- Structured security-log redaction and bounded identifiers.

Flutter tests verify:

- Only server-authorized subscriptions enter restoration state.
- Pending requests remain separate from authorized restoration state.
- Rejected subscriptions are not retried.
- Passenger route changes replace previous registry state.
- Unsubscribe, disconnect, and disposal cleanup.
- Dynamic Socket.IO payload normalization.

## Results

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Backend unit tests | 62 | 0 |
| Announcement integration tests | 6 | 0 |
| Realtime characterization and security tests | 15 | 0 |
| Passenger Flutter full suite | 22 | 0 |
| Driver Flutter full suite | 12 | 0 |
| Total | 117 | 0 |

Targeted analysis of the modified passenger and driver files reports no issues.
JavaScript syntax checks, Dart formatting, and `git diff --check` pass.

The duplicate boarding race and stale passenger location ordering tests remain
as known gaps assigned to Phases 5 and 3 respectively.

## Phase 2 Checkpoint

Phase 2 is ready for review. Advancing to Phase 3 will introduce the batched
`route.vehicles.updated` protocol behind a disabled feature flag. It requires
explicit approval before implementation starts.
