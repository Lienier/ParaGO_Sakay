# ParaGO Implementation Summary

## Scope

This document summarizes the recent implementation work for login persistence, terminal queue operations, terminal settings, automatic onboarding, automatic offboarding, testing, and documentation.

## 1-Time Login

The system supports persistent login behavior through refresh-token rotation.

What it means:

- Users should not need to log in every time the app restarts.
- Refresh tokens are stored as hashes, not raw tokens.
- When a refresh token is rotated, the old token is revoked and linked to the replacement hash.
- Manual logout still clears the active session.

Important files:

- `test.js`
- `docs/ONE_TIME_LOGIN.md`
- `docs/TEST-SUITE-README.md`

Test coverage:

- `JWT - Refresh Token Rotation State`

## Terminal Settings

Routes now support explicit terminal configuration instead of relying only on the first route stop.

Admins can configure:

- terminal enabled or disabled
- terminal name
- operational terminal label
- terminal location
- terminal radius

Resolution rule:

1. If terminal settings are disabled, terminal queue support is disabled for the route.
2. If a configured terminal location exists, that location is used.
3. Otherwise, the system falls back to the first valid route stop.

Important files:

- `src/models/route.js`
- `src/utils/transportPayloads.js`
- `src/services/hybridDispatch.service.js`
- `parago_admin_web/lib/models/transport/route_summary.dart`
- `parago_admin_web/lib/services/route_service.dart`
- `parago_admin_web/lib/screens/admin/admin_route_management_screen.dart`
- `docs/TERMINAL_SETTINGS.md`

Test coverage:

- `Hybrid - Resolve Route Terminal Stop`
- `Hybrid - Resolve Configured Route Terminal`
- `Hybrid - Route Has Terminal Stop`

## Terminal Queue Management

The admin dashboard now exposes a terminal dispatch board.

Admins can:

- see active terminal queue jeepneys
- see waiting terminal passengers
- see route-mode drivers
- reorder terminal queue trips
- skip a jeepney
- restore a skipped jeepney

Backend behavior:

- `loading` trips sort first.
- `waiting` trips sort next.
- `skipped` trips stay visible but sort after waiting trips.
- Skipped jeepneys are excluded from new terminal passenger assignment.
- Restoring a skipped jeepney puts it back at the end of the active queue.

Important endpoints:

```http
GET /admin/hybrid-dispatch
PATCH /admin/terminal-queue/:tripId/reorder
PATCH /admin/terminal-queue/:tripId/skip
```

Important files:

- `src/models/tripSession.js`
- `src/models/driver.js`
- `src/routes/admin.routes.js`
- `src/routes/pickupRequests.routes.js`
- `src/services/hybridDispatch.service.js`
- `parago_admin_web/lib/services/admin_service.dart`
- `parago_admin_web/lib/screens/admin/admin_home_screen.dart`
- `parago_admin_web/lib/screens/admin/admin_home_sections.dart`
- `docs/TERMINAL_QUEUE_MANAGEMENT.md`

Test coverage:

- `Hybrid - Terminal Queue Sorting`
- `Hybrid - Terminal Queue Status Normalization`

## Automatic Onboarding

Passengers can now be marked onboard automatically when they stay near the assigned jeepney.

Rule:

- Pickup request must be acknowledged.
- Trip must be active.
- Passenger location must be recent.
- Driver/jeepney location must be recent.
- Passenger must stay within the configured proximity distance for at least 10 seconds.

Defaults:

```env
AUTO_BOARDING_PROXIMITY_METERS=25
AUTO_BOARDING_DWELL_SECONDS=10
AUTO_BOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_BOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

Result:

- ride session is created
- ride status becomes `onboard`
- `boardingMethod` is set to `auto_proximity`
- pickup request becomes `completed`
- trip `occupancyCount` increases by 1
- terminal queue status is refreshed when the pickup is terminal-based
- driver receives passenger-boarded notification

Fallback:

- Manual `I boarded` remains available.
- Stale or missing GPS does not auto-board the passenger.
- Moving too far away resets the 10-second proximity timer.

Important endpoints:

```http
POST /passengers/me/location
PATCH /drivers/me/location
PATCH /drivers/location
```

Important files:

- `src/utils/automaticBoarding.js`
- `src/services/automaticBoarding.service.js`
- `src/services/boarding.service.js`
- `src/routes/passengers.routes.js`
- `src/routes/drivers.routes.js`
- `src/models/passenger.js`
- `src/models/pickupRequest.js`
- `src/models/rideSession.js`
- `parago_passenger/lib/services/passenger_service.dart`
- `parago_passenger/lib/screens/passenger/passenger_home_screen.dart`
- `docs/AUTOMATIC_ONBOARDING.md`

Test coverage:

- `Boarding - Auto Boarding Proximity Dwell Pending`
- `Boarding - Auto Boarding Proximity Dwell Complete`
- `Boarding - Auto Boarding Proximity Reset When Far`

## Automatic Offboarding

Passengers can now be marked unloaded automatically when they separate from the jeepney.

Rule:

- Ride session must be `onboard`.
- Trip must be active.
- Passenger location must be recent.
- Driver/jeepney location must be recent.
- Passenger-to-jeepney distance must be outside the configured separation distance.
- Separation must be confirmed by 3 consecutive fresh outside checks.

Defaults:

```env
AUTO_OFFBOARDING_DISTANCE_METERS=120
AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS=3
AUTO_OFFBOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=15
AUTO_OFFBOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=15
```

Result:

- ride session becomes `completed`
- `offboardingMethod` is set to `auto_separation`
- trip `occupancyCount` decreases by 1
- active stop alerts for that ride are dismissed
- passenger and driver receive ride-completed notifications

Fallback:

- Manual `I unloaded` remains available.
- Stale or missing GPS pauses automatic offboarding.
- Returning near the jeepney resets the separation counter.
- The passenger app still shows a manual unload prompt if automation cannot safely complete.

Important files:

- `src/utils/automaticOffboarding.js`
- `src/services/automaticOffboarding.service.js`
- `src/services/rideCompletion.service.js`
- `src/routes/rideSessions.routes.js`
- `src/routes/passengers.routes.js`
- `src/routes/drivers.routes.js`
- `src/models/rideSession.js`
- `parago_passenger/lib/services/passenger_service.dart`
- `parago_passenger/lib/screens/passenger/passenger_home_screen.dart`
- `docs/AUTOMATIC_OFFBOARDING.md`

Test coverage:

- `Boarding - Auto Offboarding Separation Pending`
- `Boarding - Auto Offboarding Separation Complete`
- `Boarding - Auto Offboarding Separation Reset When Near`

## Data Model Changes

Route:

- Added `terminal` settings object.

TripSession:

- Added `skipped` terminal queue status support.

Driver:

- Added `skipped` terminal queue status support.

Passenger:

- Added `lastKnownLocation`.
- Added `lastSeenAt`.

PickupRequest:

- Added `autoBoarding` state fields.

RideSession:

- Added `boardingMethod`.
- Added `offboardingMethod`.
- Added `autoOffboarding` state fields.

## Testing Status

Backend test command:

```bash
npm.cmd test
```

Latest passing result:

- Total: 56
- Passed: 56
- Failed: 0

Additional backend syntax checks were run with `node --check` for the changed backend files.

Flutter/Dart note:

- `dart.bat format` timed out locally.
- `flutter analyze` timed out locally.
- This appears to be a local Dart tool hang in the workspace, seen repeatedly across slices.

## Real-Device Verification Checklist

Use one passenger device/app and one driver device/app.

1. Log in once, restart the apps, and confirm the session restores.
2. Configure a route terminal in admin route management.
3. Start a terminal queue trip as a driver.
4. Confirm the admin terminal dispatch board shows the jeepney.
5. Reorder the queue and confirm the UI updates.
6. Skip a jeepney and confirm it remains visible but does not receive new terminal passenger assignment.
7. Restore the skipped jeepney and confirm it returns to active queue handling.
8. Passenger sends a booking request.
9. Driver acknowledges the request.
10. Keep passenger and driver close for more than 10 seconds.
11. Confirm ride becomes onboard automatically.
12. Confirm trip passenger count increases.
13. Move passenger and driver apart beyond the configured separation range.
14. Confirm ride completes automatically after three fresh outside checks.
15. Confirm trip passenger count decreases.
16. Disable GPS or internet on one side and confirm manual `I boarded` / `I unloaded` remains usable.

## Related Docs

- [ONE_TIME_LOGIN.md](ONE_TIME_LOGIN.md)
- [TERMINAL_SETTINGS.md](TERMINAL_SETTINGS.md)
- [TERMINAL_QUEUE_MANAGEMENT.md](TERMINAL_QUEUE_MANAGEMENT.md)
- [AUTOMATIC_ONBOARDING.md](AUTOMATIC_ONBOARDING.md)
- [AUTOMATIC_OFFBOARDING.md](AUTOMATIC_OFFBOARDING.md)
- [TEST-SUITE-README.md](TEST-SUITE-README.md)
