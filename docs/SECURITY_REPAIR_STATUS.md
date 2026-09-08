# Security repair phase report

Updated: 7 September 2026. This report covers local code and validation. The release is not complete until staging verification passes.

## Phase 1: Authentication, sessions and clients

Implemented email OTP for administrators, blocked password-only and implicit social-account bypasses, added SES delivery and password-reset pages, and added recovery navigation to all three clients. OTPs are keyed hashes, reset links carry tokens in fragments, and neither secret is returned by the API.

Implemented purpose-bound access/refresh tokens, server sessions, transactional refresh rotation, session revocation, socket expiry/rechecks, serialized client refresh, and socket reconnection on refreshed credentials. Password reset publishes revocation only after its transaction commits.

Validation: 11 focused database-backed authentication tests pass, including concurrent OTP verification and refresh/reset consumption, expired OTPs, delivery failure, generic outage responses, and rejected legacy tokens. Seven focused Flutter security tests pass across the clients. Tests substitute the email provider; no real mail was sent.

## Phase 2: Transportation and reports

Boarding preserves the booked destination and fare; conflicting legacy destination fields return a conflict. Cancellation now updates only a pending/acknowledged request, preventing it from overwriting a completed boarding operation. Report ranges reject reversed dates and ranges exceeding 366 days, with matching admin-client validation.

Validation: the combined transportation/security run passed 42 tests, including simultaneous boarding/cancellation, capacity boundaries, destination protection and socket revocation. The authentication suite was subsequently expanded and rerun successfully as noted above.

## Phase 3: Limits and deployment preparation

Implemented Redis-backed HTTP and authentication-email counters, separate credential/session allowances, Retry-After handling, sensitive-authentication failure on Redis outage, and bounded transportation fallback. Added SES identity/IAM configuration, a generated origin secret, trusted proxy handling, deployment configuration guards, and the cutover script.

Validation: bootstrap and staging Terraform validation passed. Shared-counter adapter and Redis-outage regression tests pass. Real Redis Lua execution, cross-instance behavior and the deployed CloudFront/Nginx origin boundary still require staging verification.

## Overall local results and outstanding checks

- The full backend run passed 62 unit tests and 103 additional tests before the latest regression additions. Affected suites were rerun afterward: 42 transportation/security tests and then 11 authentication tests passed.
- Flutter tests excluding baseline screenshot failures: admin 17, driver 21, passenger 36; total 74 passed.
- All six screenshot failures reproduce against isolated baseline source: four admin announcement/support screenshots and one announcement screenshot in each mobile app. Baseline images were not regenerated to conceal the failures.
- Static analysis of the edited admin/driver files passes. Passenger analysis retains seven existing unused-declaration/parameter warnings in the home screen; no new security analysis findings remain.
- Compatible dependency updates removed the two high-severity audit findings. Nine moderate transitive findings remain and require a separate compatibility review.
- Local Node is 24.13.1; repeat release validation on the supported Node 22 runtime.
- ETA ambiguity on overlapping/looping routes remains outside this repair.

## Phase 4: Staging verification and release — pending

Follow [the release and rollback procedure](SECURITY_REPAIR_RELEASE.md). SES domain verification, DKIM and production access, actual delivery/recovery with controlled accounts, Redis integration, proxy spoofing checks, and passenger/driver ride flows must be verified before release acceptance. Browser/mobile end-to-end OTP, reset and socket reconnect behavior also remain staging gates beyond the local widget/service tests.

No infrastructure apply, deployment, real email sending, production database mutation, or forced sign-in cutover was performed. Rollback must retain legacy-token rejection and session revocation.

## Follow-up: Forgotten driver trips

Ending a trip now transactionally completes remaining rides, cancels pending/acknowledged pickups, dismisses active stop alerts and resets occupancy. New pickups and alerts serialize with trip closure, and pickup acknowledgement cannot overwrite cancellation. The driver app asks for confirmation before closing the journey.

An active trip with no driver GPS update for five minutes is flagged and stops accepting new pickups. Checks run every 30 seconds in API compatibility mode, or through the worker scheduler. Recent trip creation/start or explicit resume receives a five-minute grace period. The driver receives a notification and an in-app message to reopen pickups or end the trip. GPS returning alone does not reopen pickups. Stationary vehicles with fresh GPS remain active; passengers are never automatically unloaded merely because the driver loses connectivity.

No automatic trip closure is enabled. Trip end remains an explicit driver/admin decision. No deployment was performed for this follow-up.

Validation: 46 focused backend/worker tests passed. The broader backend run passed the unit suite and 112 of 113 additional tests; the existing AWS deployment-scaffold assertion expects a `sed` command absent from the current deployment script. This unrelated deployment check must be reconciled before release. Driver static analysis passed.

## Terminal repair phases — 7 September 2026

1. **Queue correctness implemented:** route-scoped transactions, one loading jeep, unique active driver/vehicle queue entries, automatic promotion, controlled reorder/skip/restore, atomic seat reservations and audited/idempotent queue actions.
2. **Passenger handling implemented:** terminal departure continues the same trip; fresh-GPS explicit boarding replaces proximity-only terminal boarding; skipped/departed unboarded bookings receive passenger-controlled transfer offers preserving fare, destination and expiry. Terminal GPS absence is advisory, superseding the generic inactivity rule above for terminal-mode trips.
3. **Clients implemented:** driver departure versus end-trip controls, terminal queue/seat/GPS summaries, passenger transfer decisions and full-terminal booking restriction, admin reason capture and controlled dispatch actions. The three client suites passed 77 tests excluding the six previously reproduced baseline screenshot failures.
4. **Release preparation implemented; staging pending:** dry-run conflict inspection and apply migration are available with a maintenance-window runbook in [TERMINAL_QUEUE_RELEASE.md](TERMINAL_QUEUE_RELEASE.md). No real database migration or deployment was performed.

Backend evidence: 52 transportation/worker tests passed, followed by seven focused terminal tests with database indexes enabled. The broader backend run passed the unit suite and 119 of 120 additional tests; the only failure remains the AWS deployment-scaffold assertion described above. Local tests do not certify deployed GPS, web/mobile navigation or reconnect behavior; controlled staging walkthroughs remain required.

Final affected checks: ten terminal/trip-closure tests passed after adding audited terminal closure and reservation conflict protection. Four focused client checks passed, including an additional lost-response retry test that reuses the admin action ID. Driver analysis is clean; admin retains two existing unused-widget warnings and passenger retains seven existing unused-declaration warnings. Terminal booking mode changes now rebuild the complete dialog so seat availability and fare preview update together.
