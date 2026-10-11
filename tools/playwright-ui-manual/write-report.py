"""Publish documentation from the captured manual Playwright review, not a test runner."""
from pathlib import Path
from collections import OrderedDict, Counter
import json
import html
import subprocess
import hashlib

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/playwright_ui_manual_2026-10-09'
raw = json.loads((OUT / 'manual-results.json').read_text(encoding='utf-8-sig'))
latest = OrderedDict()
for row in raw['results']:
    latest[row['name']] = row
counts = Counter(row['status'] for row in latest.values())
assert len(latest) == 56 and counts == {'PASS': 54, 'FAIL': 2}, counts
errors = json.loads((OUT / 'final-browser-errors.json').read_text(encoding='utf-8-sig'))

findings = [
    dict(id='UI-01', severity='High', title='New terminal booking form cannot be opened',
         reproduce='Put the assigned v2 jeep into terminal loading with six free seats. In Passenger, select a terminal pickup and a later route destination, then open booking.',
         observed='The app displays “No seats are available on this route.” The group form never opens, although the loading jeep has seats. The v2 branch skips the older Terminal/Roadside selector and retains the default roadside mode.',
         impact='The new passenger terminal booking journey is blocked.',
         fix='Expose Terminal/Roadside selection before checking trip eligibility. Carry the selected mode into quote and booking requests, then repeat both terminal and roadside UI journeys.',
         source='parago_passenger/lib/screens/passenger/passenger_home_screen.dart', line=1614,
         evidence='passenger-terminal-booking-blocked.png'),
    dict(id='UI-02', severity='Medium', title='Changed price discards the group draft',
         reproduce='Review a three-person quote for College, Market and Nearby Stop, totaling ₱59. Change the fixture fare after review, then press Book now and dismiss the changed-price message.',
         observed='The backend correctly rejects the old quote and creates no booking. Reopening the form resets it to one blank “You” row, losing the companion destinations. The dialog closes before the network submission finishes.',
         impact='Passengers must enter the group again instead of reviewing the updated quote.',
         fix='Keep the draft until submission succeeds. On price conflict, show the new individual fares and total with the existing destinations, then require another explicit review.',
         source='parago_passenger/lib/widgets/group_booking_dialog.dart', line=130,
         evidence='passenger-price-changed.png'),
    dict(id='UI-03', severity='Medium', title='Default report end time freezes at login',
         reproduce='Log into Admin, keep the default date range, complete a ride later the same morning, and refresh Reports.',
         observed='The range ended at 08:01:54 Manila, when the dashboard was opened. The later boarding at about 08:09 was excluded: Reports showed zero. Reselecting the same displayed dates expanded the end to the end of the day and showed three boarded.',
         impact='New activity can be absent from the default report even after refresh.',
         fix='Normalize the initial range to the intended full days, or advance its end when refreshing a range that includes today. Use the same rule as the date picker.',
         source='parago_admin_web/lib/screens/admin/admin_home_screen.dart', line=62,
         evidence='admin-reports-organizer-dropoff.png'),
    dict(id='UI-04', severity='Medium', title='Daily chart shows a day outside the selected Manila range',
         reproduce='Select October 2–9 in Admin Reports and inspect the daily chart labels.',
         observed='The chart starts at October 1. The API floors the supplied Manila start boundary to a UTC day, while the UI labels the chosen dates in local time.',
         impact='The chart period is confusing and daily totals can be assigned to an unexpected local date.',
         fix='Define one reporting timezone, such as Asia/Manila, and use it consistently for date boundaries, aggregation buckets and labels. Verify events on both sides of local midnight.',
         source='src/routes/reports.routes.js', line=18,
         evidence='admin-final-destination-reports.png'),
    dict(id='UI-05', severity='Medium', title='Pickup and destination labels overlap on a narrow map',
         reproduce='At 390px width, display the three-destination group near closely spaced route stops and tap its pickup label.',
         observed='The pickup label showing College, Market and +1 more overlaps destination flags. The center tap can hit the College destination marker. The complete group list is reachable through an exposed part of the marker or by adjusting the map.',
         impact='Some text is obscured and the intended pickup marker is harder to select.',
         fix='Avoid marker label collisions, separate pickup and destination hit areas, or provide an expandable grouped marker. Verify the full destination list on narrow screens.',
         source='parago_passenger/lib/screens/passenger/passenger_home_screen.dart', line=3580,
         evidence='passenger-map-label-overlap.png'),
    dict(id='UI-06', severity='Low', title='Ineligible trip is described as having no seats',
         reproduce='Try a roadside booking while the six-seat jeep is still loading in the terminal.',
         observed='The request is correctly blocked, but the message says no seats are available rather than explaining that no roadside trip is currently eligible.',
         impact='Passengers may interpret the problem as a full jeep.',
         fix='Distinguish no eligible trip, no available seats and no loading terminal jeep in the booking messages.',
         source='parago_passenger/lib/screens/passenger/passenger_home_screen.dart', line=1623,
         evidence='passenger-ineligible-trip-message.png'),
    dict(id='UI-07', severity='Low', title='Driver guidance still says to accept requests',
         reproduce='Depart the terminal in a v2 trip and inspect the next-action message on the Driver map.',
         observed='The message says “Accept pickup requests or end the trip.” New v2 requests correctly have no acknowledgement or boarding-count action.',
         impact='The instruction conflicts with the new automatic boarding flow.',
         fix='Return guidance appropriate to the trip flow version, explaining automatic boarding for v2 and retaining legacy guidance for older trips.',
         source='src/services/terminalQueue.service.js', line=320,
         evidence='driver-map-remaining-destination.png'),
    dict(id='UI-08', severity='Low', title='Registration screen is headed Login',
         reproduce='Switch Passenger authentication to Create passenger account.',
         observed='The identity and consent fields appear, but the large heading still says “Login.” Registration validation and successful synthetic registration both passed.',
         impact='The heading does not describe the current action.',
         fix='Change the heading with the selected authentication mode.',
         source='parago_passenger/lib/screens/auth_screen.dart', line=269,
         evidence='passenger-registration-consent-validation.png'),
]

summary = {
    'date': '2026-10-09', 'timezone': 'Asia/Manila',
    'method': 'Manual scenario execution through Playwright Chromium against real Flutter web UIs and a loopback backend.',
    'environment': 'Isolated local UI lab; NODE_ENV=test and DEPLOYMENT_ENV=test; not deployed cloud staging.',
    'uniqueChecks': len(latest), 'counts': dict(counts), 'rawRows': len(raw['results']),
    'adjudication': 'Latest result per identical scenario name. Two earlier input/GPS calibration attempts were rerun successfully; original rows remain in manual-results.json.',
    'browserPageErrors': {k: len(v) for k, v in errors.items()},
    'productionReady': False, 'results': list(latest.values()), 'findings': findings,
    'gitBase': 'cbd64b9f569c22a5d2046675a9e73665899d41d1',
    'branch': 'codex/multi-destination-bookings',
    'testedSource': 'Uncommitted workspace implementation; see prior automatic_group_flow report. This UI review changed only test tooling/documentation.',
}
(OUT / 'summary-results.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding='utf-8')

video_specs = [
    ('Driver', 'Main scenarios — recovered', 'earlier-session-1-recovered.webm', True),
    ('Admin', 'Main scenarios — recovered', 'earlier-session-2-recovered.webm', True),
    ('Passenger', 'Main scenarios — recovered', 'earlier-session-3-recovered.webm', True),
    ('Passenger', 'Resumed final scenarios', 'page@a8274889e85d53bba05a5b1fb30a80fa.webm', False),
    ('Driver', 'Resumed final scenarios', 'page@5c54bf370ad60692e5fee2aa04a5af32.webm', False),
    ('Admin', 'Resumed final scenarios', 'page@2530ddd85a09207895acad3215b1af90.webm', False),
]
videos = []
for role, phase, filename, recovered in video_specs:
    p = OUT / 'videos' / filename
    probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(p)], capture_output=True, text=True, check=True)
    seconds = float(json.loads(probe.stdout)['format']['duration'])
    assert seconds > 0
    videos.append(dict(role=role, phase=phase, path='videos/' + filename, seconds=seconds, bytes=p.stat().st_size, recovered=recovered))
(OUT / 'video-manifest.json').write_text(json.dumps({'videos': videos, 'note': 'The earlier browser session was interrupted. These three clips were recovered by stream-copy remux from partial original WebM files; original files are retained. No frames were fabricated. Final-session contexts closed cleanly. Durations verified with ffprobe.'}, indent=2), encoding='utf-8')
(OUT / 'video-validation.json').write_text(json.dumps(videos, indent=2), encoding='utf-8')

builds = []
for role in ['admin', 'passenger', 'driver']:
    p = OUT / f'{role}-web/main.dart.js'
    builds.append({'role': role, 'file': str(p.relative_to(OUT)).replace('\\', '/'), 'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
(OUT / 'ui-build-manifest.json').write_text(json.dumps(builds, indent=2), encoding='utf-8')

intro = '''# SAKAY manual Playwright UI review

**Result: 54 passed and 2 failed, across 56 distinct scenario checks.** The new roadside group journey completed successfully, including separate drop-offs after the organizer left. **Do not enable the new flow in production yet:** the passenger terminal booking form is inaccessible in the new flow. Eight UI findings were recorded; only two are failing named checks, while the other findings arose during visual and usability review of otherwise passing checks.

Test date: **9 October 2026, Asia/Manila**, across the initial morning session and the resumed final session. These are manual browser scenarios performed through Playwright, with screenshots, assertions, API responses, synthetic database state and browser recordings. [Open the evidence dashboard](index.html), [machine-readable summary](summary-results.json), or [original results](manual-results.json).

## Environment and method

Passenger and Driver were exercised at 390 × 844 pixels; Admin at 1440 × 844, with an additional 390px dispatch layout check. All three are actual Flutter web builds of the workspace implementation, using Chromium. The API, Mongoose models and Socket.IO handlers are real application code, running at `127.0.0.1:5069`. The UI ports were 8771–8773; fixture controls used 5070. MongoDB was an isolated temporary replica set (8.2.6), database `playwright_ui_manual_isolated_staging`; Redis used port 6398 and a separate test namespace. Only synthetic users, a synthetic route, six-seat jeep and test journeys were used. No production records were changed.

This UI lab used `NODE_ENV=test` and `DEPLOYMENT_ENV=test`. It is **local isolated testing, not deployed cloud staging and not the production configuration**. Email transport was captured in a local mailbox; real OTP creation and validation were exercised. Cloud storage, social authentication, Firebase push and cloud directions integrations were disabled or not exercised. Earlier backend staging-profile tests are documented separately in the [implementation report](../automatic_group_flow_2026-10-09/REPORT.md); they are not counted in these 56 UI checks.

Browser clicks, keyboard input, dialogs, navigation and visual inspection drove the tests. Flutter accessibility semantics were enabled for readable locators. Slow keyboard entry was used where DOM fill did not update Flutter's form state. For exact map pin input, a semantics overlay was made pointer-transparent so the underlying map canvas received the actual click coordinates. This did not alter application data or source. Fresh browser geolocation and ordered GPS requests through the real location API supplied controlled arrival observations. Fixture controls changed fares, reset synthetic journeys and prepared legacy/pagination records. These controls are setup tools, not substitute UI passes.

The final result uses the latest outcome for each identical scenario name. The 58 raw rows contain two unsuccessful input/GPS calibration attempts followed by successful reruns. Those rows remain in the original JSON. **No uncaught browser page exceptions were captured** in Passenger, Driver or Admin. Expected negative-case HTTP failures, such as invalid credentials, changed quotes and the simulated report outage, are not browser crashes.

## Findings and recommended changes
'''
sections = []
for f in findings:
    sections.append(f"### {f['id']} — {f['severity']}: {f['title']}\n\n**Reproduce:** {f['reproduce']}\n\n**Observed:** {f['observed']}\n\n**Effect:** {f['impact']}\n\n**Recommended change:** {f['fix']}\n\n[Evidence]({f['evidence']}) · [Source](../../{f['source']}) (line {f['line']} in the reviewed workspace).\n")
qualification = '''## Driver web build qualification

The first Driver web build failed in `firebase_core_web` 3.11.0 under Dart 3.10.8 / Flutter 3.38.9: `isA<JSObject>()` was called on `Object`. To make the Driver UI available for this review, an isolated copy of that dependency changed the two calls to `(e as JSAny).isA<JSObject>()`. The Driver package configuration was redirected only for the test build, then restored. Application source, pubspec/lockfiles, the global dependency cache and prepared APKs were not changed by this workaround. See [original failure](driver-web-build.log) and [adapted build](driver-web-build-adapted.log).

Driver UI findings therefore apply to this adapted browser test build. This does **not** verify an unmodified Driver web release or a native Android APK. Resolve the dependency compatibility before relying on a normal Driver web build. [Test bundle hashes](ui-build-manifest.json) identify all three reviewed JavaScript bundles.

## Successful main journey evidence

The reviewed three-person booking displayed College ₱17, Market ₱21 and Nearby Stop ₱21, totaling ₱59. It saved one v2 booking and one ride. Automatic boarding counted three seats once, with no driver acknowledgement or boarding-count confirmation. Drive-by, missing speed and poor accuracy checks did not unload members. The organizer completed at College; two companions remained. A stopped arrival at Market completed only its assigned member, leaving Nearby Stop onboard even though the stops were about 33 metres apart. Continuing to stay at the completed Market did not unload Nearby Stop. Its own fresh, stopped arrival completed the last companion using driver GPS, and repeated GPS did not deduct seats again.

Shared-destination testing completed two members in one arrival event. Manual correction completed only the selected member; early trip ending then completed the remaining member once and cleared occupancy. An existing flowVersion 1 journey retained its old unload controls and completed without conversion. Reports, after correcting the date selection, showed three boarded and one actual unload at each destination. See [three-member final state](completed-group-state.json), [shared destination state](shared-destination-state.json), [manual correction and early end](manual-correction-early-end-state.json), and [legacy final state](legacy-completed-state.json).

## Complete scenario results

PASS means the specified behavior was observed in this lab. It does not imply that every related screen, integration or native-device behavior was validated.

| # | Scenario | Result |
| --- | --- | --- |
'''
rows = '\n'.join(f"| {i} | {row['name']} | {row['status']} |" for i, row in enumerate(latest.values(), 1))
limits = '''

## Coverage limits and remaining acceptance work

| Area | Status / limit |
| --- | --- |
| New terminal booking and terminal transfer UI | Terminal booking blocked by UI-01. Terminal transfer was not completed through the UI. Earlier backend tests do not replace these UI journeys. |
| Physical boarding and unloading | GPS was simulated through the real location API. These tests do not prove people physically boarded or got off. |
| Native Passenger and Driver APKs | Not exercised here. Real phone GPS speed/accuracy, background tracking, app termination/resume and battery restrictions remain unverified. |
| Deployed cloud staging / production | Not tested or enabled. Repeat acceptance against an isolated deployed staging backend before rollout. |
| OTP delivery, social login, cloud uploads, push delivery and external directions | Local mailbox exercised OTP handling. External provider delivery and positive document-upload flows were not verified. |
| Route administration | Missing geometry validation was checked. Complete route creation/editing with external road geometry was not exercised. |
| Saved places | Empty-state guidance and disabled Add were checked. Full saved-place CRUD was not exercised. |
| Concurrency, expiry, transfers, changed GPS streams, stale GPS rejection, old-app build rejection and failed notifications | Not all were repeated as UI scenarios. Consult the separate API tests; do not count them as additional UI passes. |
| Responsive behavior | Phone-width Passenger/Driver and Admin dispatch were reviewed. This is not all resolutions, browsers, devices or accessibility modes. |
| Unassigned driver controls | No trip was created; the guard passed. The Start trip action could give clearer inline feedback inside the open controls modal. |

Fix UI-01 before enabling new journeys. Retest price-change recovery, nearby map markers and report boundaries after the other changes. Complete terminal/transfer UI acceptance, real-device GPS/background tests and deployed staging acceptance before production activation. No fixes, deployment or GitHub push were made during this UI review. The loopback servers, temporary database and dedicated Redis process were stopped after testing.

## Evidence and reproducibility

The [dashboard](index.html) contains selected screenshots, all 56 checks and six role-labeled recordings. The initial session was interrupted; its three promoted recordings were recovered by stream-copy remux from partial WebM files. Original files remain in `videos/`. The resumed final-session recordings closed normally. [Video manifest](video-manifest.json) records verified durations and recovery status. Screenshots and synthetic state snapshots provide evidence independent of the video recovery.

[Lab instructions](../../tools/playwright-ui-manual/README.md) explain fixture setup and the manual scenario sequence. They are not a claim that a standalone automated replay suite exists. See also [final browser errors](final-browser-errors.json), [main lab log](lab-staging.log), [resumed lab log](lab-final.log), [Passenger build](passenger-web-build.log), and [Admin build](admin-web-build.log). The repository branch was `codex/multi-destination-bookings`, based on commit `cbd64b9f569c22a5d2046675a9e73665899d41d1`, with the existing implementation still uncommitted.
'''
(OUT / 'REPORT.md').write_text(intro + '\n'.join(sections) + qualification + rows + limits, encoding='utf-8')

esc = html.escape
finding_cards = ''.join(f'''<article class="finding"><div class="finding-text"><span class="tag {f['severity'].lower()}">{esc(f['id'])} · {esc(f['severity'])}</span><h3>{esc(f['title'])}</h3><p><b>Reproduce:</b> {esc(f['reproduce'])}</p><p><b>Observed:</b> {esc(f['observed'])}</p><p><b>Effect:</b> {esc(f['impact'])}</p><p><b>Recommended change:</b> {esc(f['fix'])}</p><a href="../../{esc(f['source'])}">Reviewed source</a> · line {f['line']}</div><a class="shot" href="{f['evidence']}"><img loading="lazy" src="{f['evidence']}" alt="{esc(f['title'])}"></a></article>''' for f in findings)
table = ''.join(f'<tr><td>{i}</td><td>{esc(row["name"])}</td><td><span class="tag {row["status"].lower()}">{row["status"]}</span></td></tr>' for i, row in enumerate(latest.values(), 1))
video_cards = ''.join(f'<article class="video"><h3>{v["role"]}</h3><p>{esc(v["phase"])} · {v["seconds"] / 60:.1f} minutes</p><video controls preload="none" src="{v["path"]}"></video><a href="{v["path"]}">Open recording</a></article>' for v in videos)
gallery_names = ['passenger-group-fare-review.png', 'passenger-full-group-destinations.png', 'driver-onboard-three.png', 'passenger-organizer-first-dropoff.png', 'passenger-completed-group.png', 'passenger-shared-destination-complete.png', 'passenger-manual-correction.png', 'driver-legacy-completed.png', 'admin-driver-page-two.png', 'admin-support-reply.png', 'admin-narrow-dispatch.png', 'admin-report-outage.png']
gallery = ''.join(f'<a href="{name}"><img loading="lazy" src="{name}" alt="{esc(name)}"><span>{esc(name.replace(".png", "").replace("-", " "))}</span></a>' for name in gallery_names)
page = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SAKAY · Manual Playwright UI review</title><style>
*{box-sizing:border-box}body{margin:0;background:#eef3f4;color:#19343d;font:16px/1.6 system-ui,sans-serif}main{max-width:1250px;margin:auto;padding:38px 24px}h1{font-size:clamp(28px,4vw,44px);line-height:1.15;margin:12px 0}h2{font-size:26px;margin-top:44px}h3{font-size:21px;line-height:1.3}a{color:#086c78;overflow-wrap:anywhere}p{margin:12px 0}.eyebrow{font-weight:700;letter-spacing:.08em;color:#51727a}.lead{max-width:900px;font-size:19px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:26px 0}.stat{background:white;padding:18px;border-radius:12px}.stat b{display:block;font-size:34px}.notice{background:#fff0df;border-left:5px solid #bc491c;padding:20px;border-radius:8px}.context{padding:20px;background:white;border-radius:12px;margin-top:20px}.finding{display:grid;grid-template-columns:1fr 340px;gap:25px;background:white;padding:25px;border-radius:12px;margin-bottom:22px}.finding p{font-size:15px}.tag{display:inline-block;border-radius:5px;padding:3px 9px;font-size:12px;font-weight:800}.high,.fail{background:#ffe4df;color:#96290b}.medium{background:#fff0ce;color:#79501b}.low{background:#e7edf2;color:#385767}.pass{background:#d9f2e7;color:#125d40}.shot{display:flex;justify-content:center;align-items:flex-start;background:#f2f5f6;border-radius:8px;padding:10px}.shot img{max-width:100%;max-height:580px;object-fit:contain}.table-wrap{overflow:auto;background:white;border-radius:12px}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:13px;border-bottom:1px solid #e0eaed}th{background:#163d45;color:white}td:first-child{width:45px}.videos{display:grid;grid-template-columns:repeat(3,1fr);gap:20px}.video{background:white;padding:16px;border-radius:12px}.video h3{margin:0}.video p{font-size:13px}video{width:100%;height:280px;background:#14252b;object-fit:contain}.gallery{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}.gallery a{background:white;border-radius:10px;padding:12px;font-size:13px}.gallery img{width:100%;height:240px;object-fit:contain}.gallery span{display:block}.links{display:flex;gap:18px;flex-wrap:wrap;margin:20px 0}footer{margin-top:45px;border-top:1px solid #c9dadd;padding:20px 0;font-size:13px;color:#507079}@media(max-width:850px){.finding{grid-template-columns:1fr}.videos{grid-template-columns:1fr 1fr}.gallery{grid-template-columns:1fr 1fr}.stats{grid-template-columns:1fr 1fr}}@media(max-width:480px){main{padding:24px 14px}.videos,.gallery{grid-template-columns:1fr}.finding{padding:17px}.lead{font-size:17px}td{padding:10px}}</style></head><body><main>
<div class="eyebrow">SAKAY / 9 OCTOBER 2026 / ASIA–MANILA</div><h1>Manual Playwright UI review</h1><p class="lead">Passenger, Driver and Admin were tested together through the main automatic group journey, validation paths and legacy completion.</p>
<div class="stats"><div class="stat"><b>56</b>Distinct checks</div><div class="stat"><b>54</b>Passed</div><div class="stat"><b>2</b>Failed</div><div class="stat"><b>0</b>Uncaught page errors</div></div>
<div class="notice"><b>Rollout is not ready.</b> The new passenger terminal booking form cannot be opened. The roadside group journey passed, including separate companion drop-offs after the organizer left.</div>
<div class="links"><a href="REPORT.md">Full report</a><a href="summary-results.json">Summary JSON</a><a href="manual-results.json">Original results</a><a href="video-manifest.json">Recording manifest</a><a href="../../tools/playwright-ui-manual/README.md">Lab instructions</a></div>
<section class="context"><b>Test environment</b><p>Actual Flutter web screens in Chromium: Passenger and Driver 390 × 844; Admin 1440 × 844 plus a narrow dispatch check. Real local API and Socket.IO, temporary MongoDB and dedicated Redis. Synthetic users and journeys only. This test-profile lab was not deployed cloud staging.</p><p>GPS was simulated through the real location API. Physical boarding, native Android background tracking and cloud delivery were not verified. Driver web required an isolated dependency compatibility adaptation; the original package configuration was restored. See the full report for the build qualification.</p><p>Latest outcomes are shown for 56 distinct checks. Two earlier input/GPS calibration attempts were successfully rerun; all 58 original rows remain available.</p></section>
<h2>Observed issues</h2><p>Eight UI findings include the two failed named checks and additional visual or usability observations.</p>''' + finding_cards + '''
<h2>Scenario results</h2><div class="table-wrap"><table><thead><tr><th>#</th><th>Manual scenario</th><th>Result</th></tr></thead><tbody>''' + table + '''</tbody></table></div>
<h2>Journey screenshots</h2><div class="gallery">''' + gallery + '''</div>
<h2>Browser recordings</h2><p>The three main-session clips were recovered from an interrupted recording by stream-copy remux; originals are retained. The final clips closed normally. Durations were verified with ffprobe.</p><div class="videos">''' + video_cards + '''</div>
<h2>Still to validate</h2><section class="context"><p>Terminal booking and transfer through the UI; real-device GPS and background operation; deployed staging; external OTP, push, uploads and social login; full route and saved-place administration; and remaining concurrency, expiry and version-gating cases. Earlier API tests are separate evidence and are not counted as UI passes.</p><p>Fix the terminal blocker and retest the affected screens before enabling new journeys. No production data, deployment or GitHub push was performed. Local test services were shut down after the review.</p></section>
<footer>Workspace branch: codex/multi-destination-bookings · base cbd64b9f569c22a5d2046675a9e73665899d41d1 · uncommitted implementation reviewed. This dashboard documents captured manual execution; it is not a standalone automated replay suite.</footer></main></body></html>'''
(OUT / 'index.html').write_text(page, encoding='utf-8')
print(f"UI REVIEW: {len(latest)} scenarios | {counts['PASS']} PASS | {counts['FAIL']} FAIL | 8 UI findings | page errors: {sum(map(len, errors.values()))}")
for name, row in latest.items():
    if row['status'] == 'FAIL':
        print('FAIL:', name)
print('Report:', OUT / 'REPORT.md')
print('Dashboard:', OUT / 'index.html')
