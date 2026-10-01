# Terminal-first driver operation status

Updated 2026-09-26.

## Phase 1: baseline and validation — passed

- Admin driver creation, terminal loading, booking revision, and realtime capacity checks passed.
- Driver CP validation requires `09` followed by nine digits.
- License numbers are trimmed, uppercased, whitespace-normalized, and checked for duplicates.
- Admin forms show field-level CP and license errors before submission.

## Phase 2: terminal-first enforcement — passed in backend tests

- New driver trips are terminal intents.
- Direct `operatingMode: route` trip creation is rejected.
- A scheduled terminal intent cannot be manually started.
- Departure is the transition that changes a terminal trip to route operation.
- The driver UI no longer offers “Direct to route”.

## Phase 3: automatic terminal arrival — passed in backend tests

- GPS arrival requires two ordered, fresh, accurate fixes inside the configured terminal radius.
- Poor-accuracy, stale, out-of-radius, or unordered fixes do not check in a driver.
- Check-in is idempotent and uses the existing queue transaction.
- The driver UI shows “Await terminal arrival” while the scheduled intent is off queue.

## Cutover audit

Run the read-only audit before enforcement:

```text
npm run audit:terminal-first
npm run audit:terminal-first:staging
```

It reports active direct-route trips, passenger-impacting rides and pending requests, invalid or missing CP numbers, missing licenses, and duplicate normalized licenses. It returns `readyForEnforcement: false` while any blocker remains. It never edits records or creates indexes.

## Remaining release work

- Resolve audit findings and clear active passenger journeys during a maintenance window.
- Reconcile existing MongoDB indexes before enabling the new partial unique license and terminal indexes in production.
- Run Flutter formatting, analysis, and device walkthroughs when the local Flutter toolchain responds; the commands were attempted but hung without output in this environment.
- Perform deployment only after the audit and client/device checks pass.
