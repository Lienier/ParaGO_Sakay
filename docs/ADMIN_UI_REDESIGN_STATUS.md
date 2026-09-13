# Admin redesign - local review

## Number Coding module (2026-09-09)

The deferred module is now implemented locally. Administration > Number Coding replaces the Terminal dispatch holiday button. The page separates the read-only weekday plate schedule from Holiday exemptions, retaining GET/PUT/DELETE `/admin/coding-holidays` and existing backend permissions/rules. Added strict calendar-date and required-name validation, removal confirmation, disabled controls during requests and explicit refresh/error feedback. The preview now includes a holiday fixture; real writes remain blocked. Desktop and phone captures were inspected with no browser page errors. A regression test verifies invalid dates cause no mutation, saving uses the existing endpoint, cancelling removal is harmless and confirmed removal updates the list. No deployment performed.

## Executive-light refresh - Phase 3 (2026-09-09)

Local verification found and corrected two presentation problems: activity cards now distinguish initial loading/unavailable data from a real stale snapshot; fare settings distinguish failed loading from a successfully empty route list and identify default values after initial failure. API calls, validation and business rules remain unchanged.

The browser walkthrough captured all eight workspace pages in Empty, Error, Loading and Dispatch error modes, plus driver creation, announcement editing, report dates and coding-holiday dialogs at desktop and phone sizes. Representative captures were inspected, including empty/full/partial errors and all four phone dialogs. No browser page errors occurred. Tab navigation reached driver fields in order, announcement title/message/audience controls, report controls and holiday fields. This is a sampled keyboard check, not a full screen-reader accessibility audit. Phase 2 already captured populated pages at all four planned viewport sizes; existing regression tests cover long messages and stale responses.

Full `flutter analyze` and all 26 admin tests pass after the corrections. Production `lib/main.dart` and sample preview are built separately; the production check output is `parago_admin_web/build/production-check`. JavaScript builds retain the existing socket dependency WebAssembly dry-run warning. No screenshot baselines changed in Phase 3.

The final targeted browser assertion for the corrected labels timed out on Flutter semantics; those final text changes have build/test verification, but their browser assertion is not counted as passed. The earlier complete state/dialog capture run completed without page errors.

Local review remains at http://127.0.0.1:8088. The Coding Holidays preview has no GET fixture, so its dialog shows the load-error treatment; live holiday editing was not tested or moved into its deferred standalone module. The preview blocks mutations, and this review does not certify real email, authentication or database operations. User visual acceptance and controlled live-flow verification remain release gates. No push or deployment performed.

## Executive-light refresh - Phase 2 (2026-09-09)

Implemented locally: shared white Material panels with restrained shadows on Drivers, Routes, Fare Settings, Announcements and Support; matching report surfaces; navy headings and shared table header/hover/selection styles scoped to the authenticated workspace. Announcement selection now uses neutral teal independently of severity badges. Driver/route spacing is aligned. Login and operational behavior remain unchanged.

Verification: `flutter analyze lib` clean; all 26 admin tests pass. Three changed screenshot baselines were individually inspected before regeneration (the fourth remained unchanged). JavaScript sample preview built successfully. All eight workspace pages were captured at 1440x900, 1024x768, 768x1024 and 390x844, with zero browser page errors; representative layouts across the six Phase 2 pages and login were visually inspected. Local browser opened at http://127.0.0.1:8088. Existing socket dependency WebAssembly dry-run warning remains.

Next: local user design review, then Phase 3 detailed state/keyboard/dialog walkthrough and a separate production-entrypoint build. Preview checks do not verify live API mutations. No commit, push or deployment performed.

Deferred by user request: move Coding Holidays into its own administration module later, reusing the current holiday editor and API permissions. Its working Terminal dispatch button remains available until that follow-up.

## Executive-light refresh — Phase 1 (2026-09-09)

New local review checkpoint: Overview and Terminal dispatch now use a cooler workspace background, white bordered panels with subtle depth, navy detail text, clearer metric hierarchy and aligned queue fields. Tablet/phone rows stack their labels; loading countdowns are separated from mutation controls. The sidebar uses a light Material surface so selection and hover feedback remain visible. Login styling and backend behavior are unchanged.

The local preview includes sample loading deadlines and supports `?mode=Empty`, `?mode=Error`, `?mode=Loading` and `?mode=Dispatch%20error` for reviewing unavailable states. It uses sample data and blocks real writes.

Initial verification: analysis clean, all 26 admin tests passed, JavaScript preview build passed. Overview/dispatch were captured at 1440×900, 1024×768, 768×1024 and 390×844 with no browser JavaScript errors. Existing screenshot baselines were not regenerated. The existing socket dependency WebAssembly dry-run warning remains separate from the successful JavaScript build.

Review http://127.0.0.1:8088 before applying this treatment to the remaining workspace screens (Phase 2). Production-entrypoint build and full shared-screen acceptance follow in Phase 3. No push or deployment in this refresh.

## Current status — Phase 4 local verification (2026-09-08)

Phases 1–3 and the approved login colors were previously pushed as `b2d15fb` on `admin-ui-redesign-20260908`. The user redirected the merge request to Phase 4. No merge or deployment was performed. Older “local only” and “await feedback” statements below describe earlier checkpoints, not current branch status.

Phase 4 fixes: consistent Inter typography for buttons/chips, readable support action labels, bounded account-menu text and single-line phone page titles, wrapping preview controls, removal of unused presentation helpers, and brace-style cleanup. Screenshot tests now load bundled Inter and Material icons. Announcement fixtures use a fixed timestamp rather than the current time. Four desktop/narrow announcement/support baselines were individually inspected and updated; they are Windows/Asia-Manila reference captures.

Validation: `flutter analyze lib` reports no issues; all 26 admin tests pass, including four screenshot tests, OTP presentation, sessions, terminal retry behavior, report validation and stale-response handling. Preview JavaScript build passes. The production `lib/main.dart` entrypoint also built separately to `build/production-check`; the final subsequent edits only affect header layout and unused-code cleanup. Eight workspace screens were captured at 1440×900, 1024×768, 768×1024 and 390×844, plus desktop/phone login, with no browser JavaScript errors. Local captures are under `.tmp/phase4-*` and are not release assets.

Review locally at http://127.0.0.1:8088. The login retains the approved split layout and gray-green background. Phone tables, report charts and filter strips scroll horizontally; map editing remains tablet/desktop only. The preview uses fixtures, so it does not prove real authentication or database mutations.

Release gates still pending: user visual acceptance; a complete keyboard/focus and unsaved-form walkthrough; controlled staging OTP/reset/session-reconnect and terminal/ride flows. The browser automation could not select the preview's Empty dropdown option, so the full empty/loading/error screenshot sweep remains unverified; functional partial-failure/stale-data tests pass. The existing `socket_io_common` WebAssembly dry-run incompatibility remains; the JavaScript builds succeed. No claim of WebAssembly support or live SES delivery is made.

Release procedure: after review, commit Phase 4 to the feature branch, run the same tests, and obtain release authorization before merging/deploying. Build `lib/main.dart` with the deployment's real configuration; never upload `build/web` from this local preview. Keep the last approved production web artifact for UI rollback. Roll back only the admin UI artifact, preserving backend session security and transactional terminal rules. This phase changes no database schema or backend configuration.

## Phase 1

Implemented the neutral/teal foundation, bundled Inter font and license, text sidebar with tablet drawer, simplified login, neutral metric cards, driver table with existing edit workflow, and reduced dispatch decoration. The production entrypoint and authentication requirements are unchanged.

The dedicated preview entrypoint is lib/preview.dart in parago_admin_web. It uses sample records, rejects non-GET requests, and requires LOCAL_DESIGN_PREVIEW=true. It does not authenticate or connect to the real API. Do not deploy the preview build.

Local preview: http://127.0.0.1:8088

Rebuild from parago_admin_web:

```powershell
flutter build web --target lib/preview.dart --dart-define=LOCAL_DESIGN_PREVIEW=true --dart-define=PARAGO_ENABLE_REALTIME=false
python -m http.server 8088 --bind 127.0.0.1 --directory build/web
```

Use View login / View workspace and the Populated, Empty, Error, Loading selector. Driver details open the existing editor; saves are intentionally blocked in the preview.

Validation: preview web build passed; five targeted admin OTP/session/terminal tests passed. Desktop and tablet browser screenshots are in .tmp locally. Existing route-editor analyzer warnings and existing screenshot baselines remain separate from this review. Realtime transport and real account flows have not been exercised by this sample-data preview.

## Review gate

Phase 1 was approved. Phase 2 is now ready for local review; await feedback before Phase 3. All changes remain local; no commits, pushes, or deployments were performed for this redesign.

## Remaining phases

2. Operations-first organization, dedicated dispatch and reports, independent section loading and accurate freshness state.
3. Complete redesign of the remaining admin screens, editors, OTP, and legal views.
4. Full visual and functional acceptance, including approved screenshot baseline changes and release preparation.

## Phase 2 - ready for review

Added grouped text navigation, operations-first overview, dedicated Terminal dispatch and Reports screens, route filtering, loading/waiting/skipped groups, route creation within Routes, and report date selection with the 366-day limit.

Activity and dispatch requests settle independently. These views request fresh data and retain their in-memory last successful snapshot on failure; timestamps do not advance on failed refresh. Reports load on demand, preserve stale same-range results, and discard late responses for superseded date ranges. A missing dispatch endpoint is an error rather than an empty queue. Realtime connection events trigger an authoritative reload.

Departure confirmation explains preserved onboard passengers and unboarded transfer offers before requiring the existing override reason. Queue mutation retry IDs and backend rules remain unchanged.

Validation: seven targeted tests passed, including new partial-failure, lazy report, stale-report, and range-validation checks. Four operations/terminal tests passed again after reconnect changes. Preview build passed; browser navigation and desktop/tablet screenshots were inspected. Targeted analysis has no errors or warnings, with one brace-style informational lint remaining. Existing broader analyzer and WebAssembly dependency warnings remain outside this phase.

Open http://127.0.0.1:8088 and refresh the tab. Inspect Overview, Terminal dispatch, Reports, and the Dispatch error preview mode. The preview still uses only sample data and rejects writes. Real staging walkthroughs have not been run for this redesign. Nothing was pushed or deployed.

## Phase 3 - local design review

Extended the design to route tables and detail actions, route/landmark editors, fare forms, announcements, support conversations, driver forms, OTP, legal reading pages, dialogs, and the startup screen. Map controls and existing editing actions remain available on tablet/desktop; phones show an explicit map-editing notice.

Support detail navigation now follows the actual inbox layout width, fixing the tablet/sidebar mismatch. Added a regression test for a 1100px viewport with a 224px sidebar. API errors now display readable messages and validation details instead of raw ApiException wrappers.

The local preview includes sample routes, announcements and support messages plus an OTP button. It rejects mutations except an in-memory no-op read acknowledgment so sample support conversations can be inspected; no external requests or real account writes are made by PreviewApi. The legal sync tool retains the admin reading layout while preserving shared policy text.

Validation: all 22 functional admin tests passed using `flutter test --name '^(?!.*review image).*'`. Existing four screenshot baseline tests were deliberately excluded for review in Phase 4. Preview build passed. Desktop routes, fares, announcements, support, OTP and privacy pages were captured and inspected. Targeted analysis has no errors or warnings; one brace-style informational lint remains. Broader existing analyzer findings and WebAssembly dependency warnings remain separate.

Await Phase 3 design feedback before Phase 4. Nothing has been pushed or deployed. Refresh http://127.0.0.1:8088 to review.

## Login design preference

User requested the previous login design after Phase 3. Restored the pre-redesign auth_screen.dart layout; the redesigned workspace and OTP screen remain. Authentication behavior is unchanged.

## Login color refinement

Preserved the previous split login layout with a white panel, dark readable text, teal actions, muted gray-green background (#D5E0DD), and a soft green-tinted shadow for depth. Changes remain local.

## Professional refresh � Phase 1 foundation (2026-09-10)

Implemented responsive shared page headers (actions stack below 600px), header semantics, consistent workspace button sizing/padding and visible keyboard-focus borders, stronger focused input borders, restrained status colors, and Philippine-time timestamp formatting. Missing timestamp labels no longer claim to be current. Login theme remains unchanged; screen-specific layouts and raw labels are scheduled for later phases.

Verification: 25 functional tests passed, including narrow-header action access and UTC-to-Philippine date rollover. Flutter analyze passed with no issues after correcting test imports. Local preview JavaScript build succeeded; existing socket_io_common WebAssembly dry-run warning remains. Screenshot baselines were not updated. Full visual/focus walkthrough remains pending local review.

Preview opened at http://127.0.0.1:8088 using sample data. Nothing committed, pushed or deployed for this phase.
