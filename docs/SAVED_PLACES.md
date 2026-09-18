# Passenger Saved Places

Implemented locally on 2026-09-16. Backend deployment and a new passenger APK are still required before installed applications can use this feature.

## Passenger flow

1. Pin a pickup or unload location on the existing map.
2. Open Saved Places from the passenger menu and choose Add a place.
3. Enter a name such as Home or Work and choose the pinned location. The last known passenger location is also available when present.
4. Saved locations can be selected as pickup or unload points for a future booking, or removed after confirmation.

Selecting a place does not submit a booking. Select the appropriate route first; the existing route proximity, pickup GPS distance and destination order checks still apply. Set pickup before unload. An active booking or ride prevents changing pins through this flow. Saving/removing a place does not change existing bookings or fare snapshots.

## Storage and safeguards

- Authenticated passenger-only GET/POST `/passengers/me/saved-places` and DELETE `/passengers/me/saved-places/:placeId`, under the existing API prefix and general limiter.
- Embedded passenger records are scoped to the authenticated user. Client-supplied owner IDs are ignored.
- Maximum 20 places; name length 1–60 characters; finite numeric latitude/longitude within geographic bounds.
- Atomic insertion enforces both the limit and case-insensitive name uniqueness, including concurrent requests. Retrying an identical name/location returns the existing list. A name used for another location returns a conflict.
- Removal is idempotent and owner-scoped. Older profiles work without a backfill.
- The saved-place screen bypasses client response caching. GET responses specify no-store. Account changes clear displayed places and discard late responses.
- Failed requests show an error and allow retry. No successful-save state is fabricated while offline.

## Verification

- `npm run test:saved-places`: 6 passing database/HTTP tests, including concurrent duplicate/limit checks, input validation, missing profiles, old profiles, authentication, roles and ownership.
- `node test.js`: 62 passing backend unit checks.
- Boarding-notification and manual-unloading integration suites: 7 passing tests.
- Passenger `flutter test --no-pub`: all 51 tests pass, including 5 Saved Places tests for saving/removal, validation, offline recovery, account changes, selection and narrow layout with enlarged text.
- Analysis of the new screen and tests has no findings. The existing home screen retains 7 unused-code warnings; the combined analyzer command exits with warnings.

Manual code review covered route/pickup validation reuse, account changes during asynchronous location lookup, duplicate/lost-response saves, removal ownership and preservation of existing journeys.

Physical-device GPS and live API walkthroughs have not been performed for this feature. No production deployment, APK publication or live passenger data changes were made. Passing checks do not establish absence of every possible bug.
