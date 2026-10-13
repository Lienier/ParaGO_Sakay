# Driver route and queue fixes

Drivers can choose an active route with a configured terminal using their assigned jeepney. The choice now updates the driver profile used for map, GPS progression and realtime route subscriptions. Choose route is visible in the Trip menu when no journey is open.

Cancel queue works for pending terminal arrival, waiting, loading and skipped entries. It closes the terminal intent, cancels unboarded reservations, clears driver queue state and promotes the next eligible jeep. Cancellation is idempotent, serialized with boarding/departure and restricted to the owning driver or an administrator. Onboard or walk-in passengers prevent cancellation. GPS cannot automatically recreate a cancelled trip until a route/trip is explicitly selected again.

On 13 October 2026, one empty live terminal entry was cancelled after a private backup. No historical records were deleted. Queue counter/lock records remain for correct concurrency.

Validation: 42 backend regressions, 60 Driver Flutter tests and six actual browser scenarios passed (108 total). Driver analysis is clean. Browser checks cover route selection, changing routes after cancellation, Stay, actual cancellation and a 320-pixel screen. Isolated test fixture failures were corrected separately. Physical Android/background GPS acceptance remains outstanding.

Driver release: 1.1.0 build 23. Passenger remains 1.1.0 build 22. Automatic group and driver lifecycle rollout settings and the required-update minimum remain unchanged. Detailed local evidence: `artifacts/driver_queue_fix_2026-10-13/index.html`.
