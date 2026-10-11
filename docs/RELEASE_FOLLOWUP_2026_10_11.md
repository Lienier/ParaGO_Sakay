# Release follow-up — 11 October 2026

The backend patch fixes a saved stop-alert acknowledgement returning an error during notification outages, unchanged route geometry incorrectly blocking ordinary edits, support reopening overwriting a concurrent unread increment, and repeated support status changes producing duplicate unread events. Route edits also preserve trip path snapshots and share the route lock with trip creation.

Validation: 131 checks passed (89 backend regressions, 30 fault checks, two route snapshot/concurrency checks, and 10 main API/Admin browser checks). Four new regression cases failed before the fixes. Tests used isolated loopback databases and synthetic accounts. The two Admin browser checks exercised password/OTP login, navigation, persistence, logout and narrow layout; the other Playwright checks exercised API handlers.

Detailed local evidence: [follow-up report](../artifacts/release_followup_fixes_2026-10-11/index.html). The original release test counts are preserved separately.

Passenger and Driver remain 1.1.0 build 21, and Admin remains 1.1.0 build 2. These are backend fixes and require no replacement APK. Automatic group and driver lifecycle activation remains disabled pending physical Android/GPS acceptance. External delivery and a durable notification retry outbox are not certified by this patch.
