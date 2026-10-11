"""Format captured fleet test results and build hashes; does not run tests."""
from pathlib import Path
import html
import json
import hashlib
import zipfile

out = Path(__file__).resolve().parents[2] / 'artifacts/admin_live_fleet_2026-10-09'
for log in out.glob('*.log'):
    raw = log.read_bytes()
    if raw.startswith((b'\xff\xfe', b'\xfe\xff')):
        log.write_text(raw.decode('utf-16'), encoding='utf-8')
rows = json.loads((out / 'browser-results.json').read_text(encoding='utf-8'))
passed = sum(r['status'] == 'PASS' for r in rows)
failed = len(rows) - passed
zip_path = out / 'SAKAY-Admin-LiveFleet-Web.zip'
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for file in (out / 'admin-release').rglob('*'):
        if file.is_file():
            bundle.write(file, file.relative_to(out / 'admin-release').as_posix())
builds = {}
for name in ['admin-web/main.dart.js', 'admin-release/main.dart.js', zip_path.name]:
    data = (out / name).read_bytes()
    builds[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
(out / 'build-manifest.json').write_text(json.dumps(builds, indent=2), encoding='utf-8')
report = f'''# Admin live fleet map

Created 9 October 2026. Open **Admin → Live fleet map** to view all registered jeeps, search plates/drivers, filter routes, fit visible vehicles and inspect individual vehicle details. Nearby markers group when zoomed out. Jeeps with no GPS remain listed; old/offline markers show their last known location with an age indicator.

Accepted driver GPS reaches an Admin-only socket feed, including jeeps with no active trip. Updates are batched on the server and applied together in the browser, without refreshing the full dashboard for every point. The screen refreshes its metadata every 20 seconds and after reconnect/resume. A failed refresh preserves previous locations and shows an error. Older packets and slow snapshots cannot move a displayed jeep back to an earlier observation.

GPS labels mean **Live** within 30 seconds, **Old GPS** from 31–120 seconds, **Offline** after 120 seconds (or a clock excessively ahead), and **No GPS** when location/time is missing or invalid. Location freshness does not prove a phone's GPS is physically accurate. Phones must remain connected and supplying GPS for moving locations.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Fleet API and socket integration | 4 passed, 0 failed | [Log](backend-tests.log) |
| Booking and automatic-trip regressions | 49 passed, 0 failed | [Log](flow-regression.log) |
| Admin Flutter suite | 38 passed, 0 failed | [Log](admin-tests.log) |
| Admin analysis | No issues | [Log](admin-analysis.log) |
| Browser follow-up | {passed} passed, {failed} failed | [Results](browser-results.json), [log](browser-run.log), [page errors](page-errors.json) |
| Admin test and release web builds | Both succeeded | [Local build](admin-web-build.log), [release build](admin-release-build.log), [hashes](build-manifest.json) |

The fleet backend checks cover all 100 registered vehicles, idle-driver metadata, missing GPS, excluded account secrets, non-Admin access rejection, actual accepted GPS delivered only to Admin sockets, duplicate ordering rejection, and 100-vehicle batching without loss. The existing 61 realtime characterization checks also passed in the first combined run; that run had one new-test failure caused by a non-UUID test stream ID. Correcting the fixture input produced the clean four-test fleet result above. [Original combined log](backend-initial-calibration.log).

The browser review uses the actual compiled Flutter Admin UI, Chromium at 1440 × 1000 and 390 × 844, real loopback API and Socket.IO, a temporary MongoDB replica set and dedicated Redis. All 100 vehicles, accounts and routes are synthetic. The selected idle driver's movement is supplied through the real authenticated location endpoint. Email transport is captured locally while the login/OTP logic remains real. Flutter accessibility is enabled for locators; canvas pointer input is used where needed. Earlier input/locator calibration attempts are retained in `browser-calibration-*.log`. A missing accessible fleet-count summary was fixed before the final review.

This validates a basic 100-vehicle display and batched updates. It does **not** certify sustained production traffic from 100 phones, native background GPS, every device/browser, internet loss during driving, or a multi-server deployment. Maps use OpenStreetMap tiles and require tile connectivity.

## Builds and rollout

Download the [prepared Admin web build](SAKAY-Admin-LiveFleet-Web.zip). It contains the production-URL build with realtime enabled. The `admin-web` folder targets loopback port 5069 and is only for isolated testing. Serve build folders over HTTP; opening the app directly as a local file is not a supported application preview. Deploy the updated backend before publishing the Admin release, because it adds `GET /api/v1/admin/fleet` and the fleet socket event.

No production deployment, GitHub push, real account change, historical migration or live data seeding was performed. No mobile rebuild is needed for this fleet-map change. Local test services are shut down after review. [Implementation notes](../../docs/ADMIN_LIVE_FLEET.md) describe the data and update behavior. [Open screenshot dashboard](index.html).
'''
(out / 'REPORT.md').write_text(report, encoding='utf-8')
table = ''.join(f'<tr><td>{html.escape(r["name"])}</td><td>{r["status"]}</td><td><a href="{html.escape(r["evidence"])}">Evidence</a></td></tr>' for r in rows)
gallery = ''.join(f'<figure><a href="{p.name}"><img src="{p.name}" loading="lazy" alt="{p.stem}"></a><figcaption>{html.escape(p.stem)}</figcaption></figure>' for p in sorted(out.glob('0[1-8]-*.png')))
page = f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SAKAY Admin live fleet map</title>
<style>*{{box-sizing:border-box}}body{{margin:0;background:#edf3f5;color:#173343;font:16px/1.55 system-ui,sans-serif}}main{{max-width:1200px;margin:auto;padding:28px 20px}}section{{background:white;border:1px solid #d8e3e8;border-radius:12px;padding:24px;margin-bottom:22px}}h1{{font-size:32px;line-height:1.2}}a{{color:#087c74}}.stats,.links{{display:flex;flex-wrap:wrap;gap:18px}}.stats p{{background:#e4f4ed;padding:16px;border-radius:8px}}b{{font-size:22px}}table{{border-collapse:collapse;width:100%}}td,th{{border-bottom:1px solid #dce6eb;padding:12px;text-align:left}}.scroll{{overflow:auto}}.gallery{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}}figure{{margin:0;padding:12px;background:#f1f6f8;border-radius:10px}}img{{width:100%;height:auto;max-height:700px;object-fit:contain}}figcaption{{font-size:13px;margin-top:8px}}@media(max-width:700px){{.gallery{{grid-template-columns:1fr}}main{{padding:12px}}section{{padding:16px}}}}</style><main>
<section><p>9 October 2026 · Isolated local testing</p><h1>Admin live fleet map</h1><p>Admin → Live fleet map now displays all registered jeeps with route filters, plate/driver search, grouped markers, vehicle details and GPS age indicators.</p>
<div class="stats"><p><b>100</b><br>Synthetic jeeps displayed</p><p><b>{passed}/{len(rows)}</b><br>Browser checks passed</p><p><b>4 + 49</b><br>Fleet and journey tests passed</p><p><b>38</b><br>Admin Flutter tests passed</p></div>
<p>Location events move markers without fetching the entire dashboard. Old and missing GPS are shown clearly. Metadata refreshes every 20 seconds as a fallback.</p><p><strong>Prepared and tested locally; not deployed.</strong> The 100-jeep fixture is basic verification, not a sustained production capacity test.</p><nav class="links"><a href="REPORT.md">Detailed report</a><a href="browser-results.json">Browser results</a><a href="backend-tests.log">Fleet API/socket tests</a><a href="SAKAY-Admin-LiveFleet-Web.zip">Download Admin web build</a><a href="build-manifest.json">Build hashes</a></nav></section>
<section><h2>Browser scenarios</h2><div class="scroll"><table><thead><tr><th>Check</th><th>Result</th><th>Evidence</th></tr></thead><tbody>{table}</tbody></table></div></section>
<section><h2>Screenshots</h2><div class="gallery">{gallery}</div></section>
<section><h2>Available builds</h2><p>Deploy the updated backend before publishing the Admin build. The prepared release uses production URLs and has realtime enabled. The browser test build uses loopback URLs. App builds must be served over HTTP; their links here identify artifacts, not a running live preview.</p><p>No live records or deployment were changed. Phones need GPS and connectivity; offline markers are last known positions.</p></section></main></html>'''
(out / 'index.html').write_text(page, encoding='utf-8')
print(f'Fleet report: {passed} passing browser checks; {failed} failures.')
