# Verified flow fixes and Android rebuild

The Passenger, Driver and Admin clients include the fixes verified in five phases on 14–15 October 2026 (Asia/Manila). Each phase passed its focused checks before the next phase began.

## Resulting behavior

- Unknown GPS speed remains unknown through browser and native position conversion. It cannot become evidence that a jeep has stopped. A GPS timeout is kept separate from network connectivity; the Driver app can recover its connection without a manual refresh.
- Group members share one pickup and have separate destination maps and individual server-calculated fares. Equivalent saved stops are deduplicated and custom pin choices are identified. Quote review is required again after a destination changes.
- Selected route IDs take precedence over identical route names. A jeep on another route is not selected as a fallback. Same-route pickup visibility remains informational: only the assigned jeep owns reserved seats.
- Pickup labels stay clear of docked Driver map controls. Nearby Admin report locations are grouped with all counts available on tap and a location-specific zoom action.
- Destination/support/route menus and history use readable surfaces. History shows each member's fare and completion status. Admin phone input filters letters and limits input to 11 digits; form helper spacing and authentication messages are corrected.
- Loading countdowns account for the age of the server snapshot, including after a panel is reopened.

Legacy journeys retain their previous completion path. New v2 journeys use automatic boarding and per-destination completion, with manual correction controls retained as fallbacks.

## Validation

Final full Flutter suites: Passenger 83, Driver 69, Admin 42 tests passed. Backend journey regressions passed 74 tests. The baseline backend command passed 62 unit checks and 160 integration tests. These are 490 automated check executions, with zero failures in those final commands. All three `dart analyze lib test` checks reported no issues, and release web builds compiled.

Visible browser sessions exercised real Admin, Driver and Passenger app screens against an isolated loopback API, Socket.IO and temporary MongoDB replica set. Bootstrap created only accounts, routes and vehicles; bookings and rides came through the UI. Controlled browser GPS exercised solo/three-member bookings, shared/different destinations, organizer-first unloading, nearby destinations 33 metres apart, missing speed, drive-bys, cancellation, waiting movement reminders, Para, automatic trip ending, reports and network recovery. Final Admin counts were zero active trips, pending pickups and onboard passengers; reports reconciled four boarded and four unloaded in the final lab session.

Two failed connection recovery attempts are retained in the local evidence and superseded by the final rebuilt Driver retests. Nearby custom pin aliases have widget coverage; the final accessibility-driven browser session did not reproduce that custom map tap and is not counted as another browser pass. Earlier free-map tapping has separate Phase 2 evidence. A licence preview containing a logo reflects stored test data; no uploaded licence documents were replaced.

Detailed local evidence: `artifacts/phased_flow_fixes_2026-10-14/index.html`, including screenshots, semantic snapshots, test logs and the tested source/bundle manifest. Generated artifacts are intentionally not committed to Git.

## Versions and build settings

The published catalog was checked before choosing the next Android build numbers: Driver 23 and Passenger 22 were already published.

| App | Version | New build |
| --- | --- | --- |
| Driver | 1.1.0 | 24 |
| Passenger | 1.1.0 | 23 |
| Admin | 1.1.0 | 3 |

Android release builds preserve the existing Android debug signing identity for direct tester APK upgrades. They use primary API `https://api.sakaygaray.com/api/v1`, CloudFront fallback `https://d3f9uwhh18xrzf.cloudfront.net/api/v1`, and `PARAGO_ENABLE_REALTIME=true`. APKs are placed in ignored `dist/`; the local build record contains file hashes, manifest versions and signature verification.

For each Android project, run `flutter build apk --release --no-pub --build-name=1.1.0 --build-number=<build>` with the API defines above and `PARAGO_ENABLE_REALTIME=true`. Driver uses build 24; Passenger uses build 23. These builds target the production API rather than the isolated test lab.

This change does not enable production automation flags, change required-update minimums, publish APKs to the download catalog, or rewrite historical/presentation records. Pushing `main` triggers the repository's existing staging workflow; connected hosting integrations may deploy the web source. Native installation, permissions, locked-screen/background GPS, real-road behavior and external push delivery still require physical-device acceptance. Passing these tests does not guarantee that no future defect can occur.
