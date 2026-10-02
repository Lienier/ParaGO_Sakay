# Local UI review â€” 3 October 2026

## Scope and rule

Continue the signed-in driver/passenger emulator walkthrough. Capture defects first; do not edit application code during this review. No deployment or APK distribution is included. This is not a zero-defect certification.

Environment: driver `emulator-5554`, passenger `emulator-5556`, both version `1.0.4+13`; local API `http://localhost:5000`; admin preview `http://localhost:5310`. The API uses the configured Atlas database, so a local API does **not** prove database isolation. Use only the previously controlled BGF route/jeep/account workflow and finish test journeys through normal endpoints. No other accounts or operations are to be changed.

Evidence: `.tmp/ui-review-2026-10-03/` contains timestamped UI XML, extracted labels/bounds, and screenshots. Prior end-to-end evidence is in `.tmp/ui-full/`. Raw credentials are excluded from this report. These local evidence folders are ignored by Git.

## Findings logged before fixes

| ID | Severity | Finding | Evidence and reproduction | Status |
| --- | --- | --- | --- | --- |
| UI-01 | High | Driver Acknowledge and Depart terminal controls overlapped in an earlier loading state; the intended acknowledgement tap opened departure confirmation. | Prior walkthrough: Acknowledge bounds `[95,541][985,677]` overlapped Depart terminal `[63,494][1017,630]`. See `.tmp/ui-full/driver-request-live.xml` and departure-dialog captures. Relaunch changed layout. Reproduce with request while loading and changing sheet state; retain confirmation safety. | Fixed in the driver screen: the actionable toast is shown only on Drive, while Requests and Alerts use their inline action cards. Focused toast tests pass; a fresh request-state reproduction remains desirable. |
| UI-02 | Medium | Driver idle help describes obsolete route-only behavior and excludes direct pickup handling, although the app supports assigned passenger requests and terminal-first entry. | `driver-initial.png/json`; after ending trip, expand controls and scroll. Text: â€œYou can stay online ... while on routeâ€ and â€œhandles route-based ride alerts, not direct passenger pickups.â€ Source strings in `driver_home_screen.dart`. | Fixed: copy now describes terminal entry and post-departure pickup alerts. |
| UI-03 | Low | Previous para-alert success message remains visible after manual unload completes the ride. | `passenger-initial.png/json` shows â€œStop alert sent successfully.â€ alongside Current Ride / Completed. | Fixed: fresh booking loads and ride-completed realtime updates clear the stale para-alert message. |

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| API health/readiness and admin server HTTP reachability | Pass | `/health`, `/ready`, admin preview all returned 200. This does not prove every screen works. |
| Initial cleanup | Pass | `/trips/active` returned no active trips; previous test trip ended through driver confirmation. |
| Missing pickup/destination pins | Pass | Tap Request pickup after prior ride: `Pins required` with corrective instruction, no booking created. `passenger-new-request.json`. |
| Driver terminal-first start dialog | Pass | Start trip shows route/direction and fresh terminal GPS requirement; no direct-route choice. `driver-start-dialog.json`. |
| Admin visual/navigation checks | Partially blocked | Fresh Computer Use session still returned no native/browser surfaces and the in-app browser provider was unavailable. As a fallback, local Chrome headless loaded `http://localhost:5310` and returned the complete Flutter bootstrap/asset document; this verifies serving, not visual interaction, layout, login, or navigation. |
| Focused terminal integration regression | Pass | `node --test tests/terminal-first-operation.integration.test.js`: 4 passed, 0 failed. |
| Driver Flutter suite | Pass | `parago_mobile`: all tests passed (45 tests in this run). |
| Passenger Flutter suite | Pass | `parago_passenger`: all tests passed (59 tests in this run). |

## Infrastructure incident recorded

Before Redis was restarted, the backend log showed repeated `POST /api/v1/auth/refresh` responses with HTTP 503 while the local Redis service was unavailable. Redis was restored, the backend restarted, and `/health`/`/ready` returned 200. Treat this as a recoverable local infrastructure incident; it is not evidence that refresh behavior is correct during a production Redis outage. A separate outage test is still required.

## Pending continuation

Terminal-arrival diagnostics, duplicate entry protection through repeated GPS, cancelled boarding/request recovery, count controls, passenger navigation and app resume, and final cleanup are to be recorded below as performed. Group, push sound, physical-device movement, and complete admin workflows must not be marked passed without their own evidence.
