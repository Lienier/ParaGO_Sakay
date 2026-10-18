# Terminal connection and screen fixes

The Admin dispatch screen now distinguishes a saved jeep position near a terminal from an actual queue entry. Fresh positions and old GPS carry explicit labels and reasons; these hints do not create trips or queue membership. The existing arrival checks remain authoritative.

Driver Trip controls are also available from More for all signed-in drivers. Missing jeep assignments and open trips explain why route selection or starting is unavailable. Passenger legacy booking fare details now use an explicit dark green surface and white text, including the total, route and expiry guidance.

Release versions are Driver 1.1.0 build 25, Passenger 1.1.0 build 24 and Admin 1.1.0 build 4. Mobile releases are optional updates. Production automation settings and minimum required mobile builds remain unchanged.

Validation: 85 Passenger, 69 Driver and 43 Admin tests passed; 39 backend regression tests passed with no failures or skips. Ten focused backend checks passed after the final projection adjustment. All three analyses were clean and all three release web test builds compiled. Ten multi-role UI observations passed with no JavaScript page errors, including live terminal/fleet updates without Refresh, two-fix arrival, queue cancellation, route selection restrictions and fare readability at 320px and 390px. Fare widget tests cover 200% text and contrast of at least 4.5:1.

UI interactions used a local isolated API with real Socket.IO and temporary MongoDB records; browser GPS was controlled. Live diagnostics were read-only. No Android device was connected, so native permissions, background GPS and the particular intermittent handset incident remain unverified. Publication evidence and APK verification are recorded in artifacts/terminal_updates_release_2026-10-18; detailed test evidence is in artifacts/terminal_connection_fix_2026-10-18.
