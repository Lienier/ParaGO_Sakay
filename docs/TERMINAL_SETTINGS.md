# Terminal Settings

## Purpose

Terminal settings let an admin define the exact terminal location for a route instead of relying only on the first stop in the route stop list.

This is the route configuration foundation for terminal queue management:

- visible jeepney queue
- terminal map setting UI
- terminal passenger dispatch board

## Route Terminal Fields

Routes now support a `terminal` object:

```json
{
  "terminal": {
    "enabled": true,
    "name": "North Terminal",
    "stopRef": "NORTH-GATE",
    "location": {
      "type": "Point",
      "coordinates": [121.1234, 14.5678]
    },
    "radiusMeters": 75
  }
}
```

Field meanings:

- `enabled`: when false, terminal queue support is disabled for the route.
- `name`: admin-facing terminal name.
- `stopRef`: operational terminal label used in requests and trip sessions.
- `location`: terminal coordinate as `[longitude, latitude]`.
- `radiusMeters`: terminal geofence radius for future UI and automatic checks.

## Resolution Rule

When the system needs the terminal for a route:

1. If `route.terminal.enabled === false`, the route has no terminal queue support.
2. If `route.terminal.location` is configured, that terminal is used.
3. If no explicit terminal is configured, the system falls back to the lowest-order valid route stop.

This keeps existing routes working while allowing precise terminal setup.

## Affected Flows

The terminal resolver is shared by:

- terminal queue trip creation/start
- passenger terminal boarding requests
- admin driver route validation for terminal queue mode
- terminal queue availability checks

## Admin UI

The admin route management screen now exposes terminal settings from each route card.

Admins can:

- enable or disable terminal queue support for a route
- set the terminal name and operational label
- choose an existing route landmark as the terminal
- tap the map to place a custom terminal pin
- set the terminal radius in meters
- see whether a route is using a configured terminal or the fallback first landmark

Saving the terminal dialog updates only the route `terminal` object, so route geometry, landmarks, and fare settings remain unchanged.

## Verification

Run:

```bash
npm test
```

Relevant tests:

- `Hybrid - Resolve Route Terminal Stop`
- `Hybrid - Resolve Configured Route Terminal`
- `Hybrid - Route Has Terminal Stop`

## Next Slice

Automatic passenger onboard detection is covered in [AUTOMATIC_ONBOARDING.md](AUTOMATIC_ONBOARDING.md).
Automatic passenger offboarding is covered in [AUTOMATIC_OFFBOARDING.md](AUTOMATIC_OFFBOARDING.md).

The next implementation slice should focus on end-to-end verification:

- run the mobile passenger and driver apps together
- confirm onboard/offboard passenger counts in driver and admin views
- capture any UI polish needed after real-device testing
