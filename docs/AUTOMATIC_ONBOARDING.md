# Automatic Onboarding

## Purpose

Automatic onboarding marks a passenger as onboard when the passenger stays near the assigned driver/jeepney for more than 10 seconds. It uses the same ride-session creation path as manual boarding, so the trip passenger count increases in the driver/admin views.

Manual `I boarded` remains available as a fallback.

## Rule

A pickup request can auto-board when:

- The request is already `acknowledged` by the driver.
- The trip is active.
- The passenger has a recent location ping.
- The driver/jeepney has a recent location ping.
- Passenger-to-jeepney distance stays within `AUTO_BOARDING_PROXIMITY_METERS` for at least `AUTO_BOARDING_DWELL_SECONDS`.

Defaults:

```env
AUTO_BOARDING_PROXIMITY_METERS=25
AUTO_BOARDING_DWELL_SECONDS=10
AUTO_BOARDING_PASSENGER_LOCATION_MAX_AGE_SECONDS=45
AUTO_BOARDING_DRIVER_LOCATION_MAX_AGE_SECONDS=20
```

## Location Inputs

Driver app:

- Existing driver location updates call `/drivers/me/location` or `/drivers/location`.
- Each driver location update checks acknowledged pickup requests for that active trip.

Passenger app:

- Passenger location pings call `/passengers/me/location`.
- The passenger app reports location after a request is acknowledged.

Either side can trigger the check. This helps when one app updates more often than the other.

## Result

When the 10-second proximity rule passes:

- A ride session is created with `status: onboard`.
- `boardingMethod` is set to `auto_proximity`.
- The pickup request becomes `completed`.
- The trip `occupancyCount` increments by 1.
- Terminal queue status is refreshed when the pickup is a terminal pickup.
- The driver receives the existing passenger-boarded notification.

## Fallback

Automatic boarding is intentionally conservative:

- Stale passenger or driver locations do not auto-board.
- Moving too far away resets the 10-second proximity timer.
- If automatic boarding cannot run because of GPS/network issues, passengers can still press `I boarded`.

## Verification

Run:

```bash
npm test
```

Relevant tests:

- `Boarding - Auto Boarding Proximity Dwell Pending`
- `Boarding - Auto Boarding Proximity Dwell Complete`
- `Boarding - Auto Boarding Proximity Reset When Far`
