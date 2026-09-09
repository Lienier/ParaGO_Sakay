# Coding, terminal loading and passenger hours

Implemented locally; not pushed or deployed.

## Rules

- Manila calendar dates: Monday 1/2, Tuesday 3/4, Wednesday 5/6, Thursday 7/8, Friday 9/0. Weekends and admin-entered holidays have no coding. No individual exemptions. Invalid plates need correction before weekday operation.
- Coding checks cover active trip creation, scheduled-trip activation, terminal check-in/promotion/departure, new bookings and reopening route pickups. Existing passengers are not automatically unloaded and accounts are not suspended.
- Each promotion to Loading persists a new server timestamp. Waiting time is excluded. At eight minutes clients warn; at ten minutes new terminal reservations and transfer acceptance into that jeep are rejected transactionally. Existing boarding and manual departure remain available. The deadline alone never promotes another jeep or switches the trip to route mode.
- Driver/admin notification records are created once per warning/expiry by the existing approximately 30-second lifecycle reconciliation. Queue events publish after commit. This is in-app notification delivery, not an OS push guarantee. Reservation enforcement does not depend on the worker running.
- All clients display the countdown for the loading jeep. Passenger map and list views display the 4:30 AM–7:30 PM advisory. No scheduled daily push or service-hour booking cutoff is introduced. After departure, roadside reservations retain their existing rules and coding checks.

## Administration and API

Terminal dispatch contains **Coding holidays**, with date/name entry and removal. Authenticated ADMIN endpoints: GET `/admin/coding-holidays`, PUT `/admin/coding-holidays/:date` with `{name}`, DELETE `/admin/coding-holidays/:date`. Dates are validated YYYY-MM-DD; the saved record includes its last editor. Holidays start empty and must be configured before release.

Trip records add `terminalLoadingStartedAt`, `terminalLoadingWarnedAt`, `terminalLoadingExpiredAt`. `terminalSummary` adds server time, loading deadline, remaining seconds, warning/expiry and missing-timer flags. Existing fields and paths remain compatible.

## Verification and release

- Four focused tests pass: weekly/holiday coding, Manila date boundary, timer boundaries, and database-backed promotion/reservation races, expiry, roadside continuation and duplicate notification suppression.
- Eight existing terminal integration regressions pass. All 26 admin tests pass.
- Targeted admin/driver analysis passes. Passenger analysis reports seven existing unused-element warnings, no compile errors.
- Live device delivery, complete holiday-editor interaction and staging walkthrough remain release checks. No real database or email was used for verification.
- Existing Loading records lack the timestamp: new reservations fail closed, while boarding/departure remain possible. Prefer releasing with no jeeps loading; do not backfill from terminal check-in because it includes waiting time. Skip/restore followed by a new promotion starts a fresh timer under existing queue rules.
- Deploy backend/client changes together after controlled testing. Do not roll back to a backend that drops coding or transactional deadline enforcement. Keep session security and queue indexes intact.
