"""Format captured follow-up evidence; does not execute browser scenarios."""
import hashlib
import html
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / 'artifacts/driver_information_flow_2026-10-09'
for log in out.glob('*.log'):
    raw = log.read_bytes()
    if raw.startswith((b'\xff\xfe', b'\xfe\xff')):
        log.write_text(raw.decode('utf-16'), encoding='utf-8')
results = json.loads((out / 'browser-results.json').read_text(encoding='utf-8'))
passed = sum(row['status'] == 'PASS' for row in results)
failed = len(results) - passed
manifest = {}
for name in ['SAKAY-Driver-1.1.0-21.apk', 'SAKAY-Passenger-1.1.0-21.apk',
             'driver-web/main.dart.js', 'passenger-web/main.dart.js', 'admin-web/main.dart.js']:
    path = out / name
    manifest[name] = {'bytes': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
(out / 'build-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
(out / 'apk-sha256.json').write_text(json.dumps({name: data for name, data in manifest.items()
                                              if name.endswith('.apk')}, indent=2), encoding='utf-8')
rows = ''.join(f'<tr><td>{html.escape(row["name"])}</td><td class="pass">{row["status"]}</td>'
               f'<td><a href="{html.escape(row["evidence"])}">Evidence</a></td></tr>' for row in results)
shots = [
    ('30-other-driver-visible-jeep-and-count.png', 'Other driver: destination names, group size and assigned jeep'),
    ('33-other-driver-pin-clears-after-boarding.png', 'Other driver: pending pickup clears automatically after boarding'),
    ('31-passenger-narrow-group-map.png', 'Passenger: compact destinations and readable pickup label'),
    ('32-passenger-full-members.png', 'Passenger: all three destinations and individual fares'),
    ('15-changed-price-draft.png', 'Changed-price rejection keeps both member selections'),
    ('34-driver-manual-fallback.png', 'Optional manual corrections and trip controls'),
    ('24-admin-default-range-after-rides.png', 'Admin: new rides appear in the unchanged default date range'),
    ('36-passenger-signup-heading.png', 'Registration uses the correct heading'),
]
cards = ''.join(f'<figure><a href="{name}"><img src="{name}" alt="{html.escape(title)}" loading="lazy"></a>'
                f'<figcaption>{html.escape(title)}</figcaption></figure>' for name, title in shots)
page = f'''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SAKAY driver information and automatic trips — follow-up results</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#f1f5f7;color:#182e3d;font:16px/1.55 system-ui,sans-serif}}
main{{max-width:1160px;margin:auto;padding:30px 20px}}h1{{line-height:1.2;font-size:32px;margin:12px 0}}h2{{font-size:23px}}
header,section{{background:white;border:1px solid #dce5eb;border-radius:14px;padding:24px;margin:0 0 22px}}
a{{color:#096d69}}.stats{{display:flex;gap:14px;flex-wrap:wrap}}.stat{{background:#e9f5f0;padding:12px 20px;border-radius:10px}}
.stat strong{{display:block;font-size:25px}}.links{{display:flex;gap:20px;flex-wrap:wrap;margin-top:16px}}
table{{width:100%;border-collapse:collapse}}td,th{{text-align:left;border-bottom:1px solid #e2e9ed;padding:12px 8px}}th{{background:#eef4f6}}
.pass{{color:#096b50;font-weight:700}}.scroll{{overflow-x:auto}}.gallery{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}}
figure{{margin:0;background:#f4f7f9;border:1px solid #dce5eb;border-radius:10px;padding:12px}}
figure img{{display:block;max-width:100%;height:auto;max-height:680px;margin:auto}}figcaption{{padding:14px 3px 2px;font-weight:600}}
.muted{{color:#526879}}code{{background:#edf3f6;padding:2px 5px;border-radius:3px}}
@media(max-width:650px){{.gallery{{grid-template-columns:1fr}}main{{padding:14px 10px}}header,section{{padding:18px}}h1{{font-size:26px}}}}
</style><main>
<header><p class="muted">9 October 2026 · Asia/Manila · Isolated local testing</p>
<h1>Driver information and automatic trips</h1>
<p>Drivers on the same route see pending passenger pickup pins. One assigned jeep retains the booking and seats.
Automatic start, departure, boarding, separate drop-offs and empty-trip completion are prepared, with manual fallbacks.</p>
<div class="stats"><div class="stat"><strong>{passed} / {len(results)}</strong>Targeted browser checks passed</div>
<div class="stat"><strong>{failed}</strong>Failed final checks</div><div class="stat"><strong>49 + 49</strong>Local and staging-profile flow tests</div>
<div class="stat"><strong>51 / 63</strong>Driver / Passenger Flutter tests passed</div></div>
<p><b>No production deployment or live record change.</b> Native phone GPS/background behavior and deployed cloud staging still need acceptance testing.</p>
<nav class="links"><a href="REPORT.md">Detailed report</a><a href="browser-results.json">Scenario results</a><a href="build-manifest.json">Build hashes</a>
<a href="SAKAY-Driver-1.1.0-21.apk">Driver APK</a><a href="SAKAY-Passenger-1.1.0-21.apk">Passenger APK</a></nav>
</header>
<section><h2>Verification</h2><p>All 62 base backend checks and 160 backend regression tests passed. Driver analysis found no issues;
Passenger analysis has no errors and 13 existing warnings/information messages. All three web builds and both Android builds succeeded.</p>
<p>The earlier eight UI findings were addressed and retested. A new stale shared-pin issue was fixed and passed a fresh retest.
The Driver dependency compatibility fix uses the normal package release, without the earlier test-only shim.</p>
<nav class="links"><a href="backend-tests.log">Flow tests</a><a href="backend-staging-tests.log">Staging-profile tests</a>
<a href="backend-regression.log">Backend regressions</a><a href="driver-tests.log">Driver tests</a><a href="passenger-tests.log">Passenger tests</a></nav>
</section>
<section><h2>Targeted browser scenarios</h2><p class="muted">Actual Flutter UIs operated through Playwright; controlled GPS sent through the real loopback API.
These follow-up checks are separate from the earlier 56-check review.</p><div class="scroll"><table><thead><tr><th>Scenario</th><th>Result</th><th>Evidence</th></tr></thead><tbody>{rows}</tbody></table></div></section>
<section><h2>Screenshots</h2><p class="muted">Select an image to inspect it at full size.</p><div class="gallery">{cards}</div></section>
<section><h2>Rollout</h2><p>Both <code>AUTOMATIC_GROUP_FLOW_ENABLED</code> and <code>AUTOMATIC_DRIVER_LIFECYCLE_ENABLED</code> are required for full trip automation.
The lifecycle flag defaults to false. Disabled automation keeps normal trip controls visible; legacy journeys retain their old behavior.</p>
<p>APKs are unpublished version 1.1.0, build 21, rebuilt from the updated workspace. They use the configured production API URLs;
the reviewed browser bundles use the isolated local API. APK compilation does not prove physical-device behavior.</p></section>
</main></html>'''
(out / 'index.html').write_text(page, encoding='utf-8')
report = out / 'REPORT.md'
report.write_text(report.read_text(encoding='utf-8').replace(
    'See final per-scenario results in the dashboard', f'{passed} passed, {failed} failed across {len(results)} targeted checks'), encoding='utf-8')
print(f'Formatted {len(results)} captured checks: {passed} passed, {failed} failed.')
