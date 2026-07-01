# Automatic Offboarding

## Purpose

Automatic offboarding closes an onboard ride when the passenger and assigned jeepney become too far apart. It uses the same completion path as manual unload, so the trip passenger count decreases in driver/admin views.

Manual `I unloaded` remains available as the fallback.

## Rule

An onboard ride can auto-complete when:

- The ride session is `onboard`.
- The trip is active.
- The passenger has a recent location ping.
- The driver/jeepney has a recent location ping.
- Passenger-to-jeepney distance is at least `AUTO_OFFBOARDING_DISTANCE_METERS`.
- The separation is confirmed for enough checks or enough sustained time.

Defaults:

```env
AUTO_OFFBOARDING_DISTANCE_METERS=120
AUTO_OFFBOARDING_CONSECUTIVE_OUTSIDE_CHECKS=3
AUTO_OFFBOARDING_SUSTAINED_SEPARATION_SECONDS=60
AUTO_OFFBOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_OFFBOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

## Location Inputs

Driver app:

- Existing driver location updates call `/drivers/me/location` or `/drivers/location`.
- Each driver location update checks onboard ride sessions for that active trip.

Passenger app:

- Passenger location pings call `/passengers/me/location`.
- The passenger app reports location when a ride is onboard.

Either side can trigger the separation check.

## Result

When the separation rule passes:

- The ride session becomes `completed`.
- `offboardingMethod` is set to `auto_separation`.
- The trip `occupancyCount` decrements by 1.
- Active stop alerts for that ride are dismissed.
- Passenger and driver receive ride-completed notifications.

## Network/GPS Fallback

Automatic offboarding pauses when either location is stale or missing. It does not complete the ride from old GPS data. If GPS or internet prevents automatic completion, the passenger can still press `I unloaded`.

The passenger app also keeps the existing separation prompt, so the user sees a manual fallback message if they are far from the jeepney but automation has not completed the ride yet.

## Verification

Run:

```bash
npm test
```

Relevant tests:

- `Boarding - Auto Offboarding Separation Pending`
- `Boarding - Auto Offboarding Separation Complete`
- `Boarding - Auto Offboarding Separation Reset When Near`
