# Admin redesign - local review

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
