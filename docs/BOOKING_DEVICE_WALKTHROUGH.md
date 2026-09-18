# Booking revision: physical-device acceptance

Status: IN PROGRESS. Use this alongside PASSENGER_BOOKING_REVISION.md; automated passes do not complete this checklist.

## Observed device results — 2026-09-18

Physical phone 2311DRK48G, Android 16; local passenger debug APK using USB reverse to the isolated API on port 5057. Remote input initially failed with INJECT_EVENTS; it now succeeds. No production API or database was used.

- Signed-in map opened. One blank-screen occurrence after returning to the app recovered after force-stop/relaunch without clearing data; cause and reproducibility remain unresolved.
- With location shown as unavailable, selected remote route pickup/destination pins and opened the booking dialog.
- Selected three people: regular fare PHP 17.00 per person, discounted reference PHP 13.60, regular total PHP 51.00. Eligibility disclaimer and unchanged booking-deadline notice appeared.
- Submitted through the physical app: success response displayed. Home then blocked a second booking and showed “My group is ready”.
- Attempting readiness before driver acknowledgement displayed “Acknowledgement required”; no boarding was claimed.
- Driver confirmation, GPS/proximity gate, actual seat counts, partial unloading and movement-camera checks remain unperformed on the device. These observations do not complete the release gate.

## Test boundary

Use an isolated local replica-set database with controlled passenger and driver accounts. Do not load production fixtures or change the live group feature flag. Configure both API base URL settings explicitly for the local API; verify the selected endpoint before signing in. Keep email, push delivery and scheduled external jobs disabled unless separately required for the test.

Use a test phone with USB debugging authorized. Record app revision, phone/Android version, font scale, notification/location permissions and API target. Installing a local build over an existing installation may require matching signing keys; preserve user data and never uninstall silently. A second phone is preferred for observing both roles simultaneously.

## Acceptance records

For each row, record pass/fail, screenshot or recording reference, and observed server booking/ride revision and seat counts. Never include passwords or session tokens.

| Scenario | Expected result | Result |
| --- | --- | --- |
| GPS denied, remote route pins | Booking succeeds; boarding requires fresh GPS | Not run |
| Saved Place outside route / reverse direction | Actionable rejection; selected details retained | Not run |
| Group of three, only two board | Organizer readiness does not occupy seats; driver confirms two; one reservation released | Not run |
| Organizer moves away or closes app | Group seats remain occupied | Not run |
| Driver unloads one of two | One remains; ride active; passenger count updates | Not run |
| Organizer confirms final person got off | Ride completes, one remaining seat released | Not run |
| Lost completion response / retry | Refresh shows authoritative count; no duplicate release | Not run |
| Terminal group transfer to undersized jeep | Offer stays pending without reserving seats | Not run |
| Final trip completion with group onboard | Remaining count released once; all affected rides closed | Not run |
| Booking deadline passes after remote booking | No extended waiting or late boarding | Not run |
| Map pan, pinch and rotation during GPS updates | Free view persists beyond eight seconds and reconnect/resume | Not run |
| Recenter before / after boarding / after unload | Passenger / assigned jeep / passenger target respectively | Not run |
| Heading crosses north; vehicle stops | No long spin or stationary heading jitter | Not run |
| Location becomes stale or unavailable | Camera retains view and shows status; no implied live movement | Not run |
| Large text and narrow screen | Fare labels, counts, confirmation and Recenter remain readable and reachable | Not run |

Do movement checks as a passenger or while safely stopped. A driver must not operate test controls while driving.

## Release decision

Any failed count, authorization, retry or stale-state scenario blocks release. Fix and repeat the affected scenario plus its automated regression. Keep groups disabled until compatible active clients and the complete walkthrough are verified. Record deployment/APK distribution approval separately.
