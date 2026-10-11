// Format recorded test evidence. This script does not execute tests or publish.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'artifacts/full_system_release_2026-10-11');
const read = file => {
  const b = fs.readFileSync(path.join(out, file));
  return b[0] === 255 && b[1] === 254 ? b.toString('utf16le').slice(1) : b.toString('utf8');
};
const json = file => JSON.parse(read(file));
const html = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rows = [];
function node(name, file, count) {
  const s = read(file); assert.match(s, new RegExp('pass '+count+'\\b')); assert.match(s, /fail 0\b/);
  rows.push({ name, passed: count, evidence: file });
}
node('Backend regression', 'backend-clean.log', 247);
node('Booking retention migration', 'retention-migration-test.log', 1);
node('Automation with isolated staging configuration (repeat coverage)', 'backend-staging-profile.log', 25);
assert.match(read('backend-unit.log'), /Passed: 62/); assert.match(read('backend-unit.log'), /Failed: 0/);
rows.push({ name: 'Backend unit checks', passed: 62, evidence: 'backend-unit.log' });
for (const [name, file, count, analysis] of [
  ['Driver app', 'driver-tests.log', 60, 'driver-analysis.log'],
  ['Passenger app', 'passenger-tests-final.log', 74, 'passenger-analysis-clean.log'],
  ['Admin app', 'admin-tests.log', 38, 'admin-analysis.log'],
  ['Shared map widgets', 'shared-tests.log', 2, 'shared-analysis.log']]) {
  assert.match(read(file), new RegExp('\\+'+count+': All tests passed'));
  assert.match(read(analysis), /No issues found!/);
  rows.push({ name, passed: count, evidence: file });
}
for (const [name, file, count] of [
  ['Legacy system/API and Admin browser', 'system-final/results.json', 10],
  ['Latest Admin build browser recheck (repeat coverage)', 'system-browser-final/results.json', 2],
  ['Fault and boundary scenarios', 'reliability-final/faults/results.json', 25],
  ['Expired waiting-state regression', 'reliability-final-expiry/faults/results.json', 1],
  ['Ride cycles, contention, recovery and load', 'reliability/reliability/results.json', 63]]) {
  const s = json(file).stats; assert.equal(s.expected, count); assert.equal(s.unexpected, 0); assert.equal(s.skipped, 0);
  rows.push({ name, passed: count, evidence: file });
}
const browser = [];
for (const [name, folder, count] of [
  ['Passenger booking controls', 'booking-final-pass', 13],
  ['Passenger/Driver layout, glass notices and drop-offs', 'mobile-final', 15],
  ['Three-role map markers and Waiting/Cancel', 'markers-final', 7],
  ['Admin fleet with 100 jeeps', 'fleet', 7]]) {
  const checks = json(folder+'/browser-results.json'); assert.equal(checks.length, count);
  assert.ok(checks.every(c=>c.status==='PASS')); assert.deepEqual(json(folder+'/page-errors.json'), []);
  browser.push(...checks.map(c=>({ ...c, suite: name, evidence: folder+'/'+c.evidence })));
  rows.push({ name, passed: count, evidence: folder+'/browser-results.json' });
}
const apks = json('apk-validation-final.json');
for (const a of apks) { assert.equal(a.build, 21); assert.equal(a.version, '1.1.0'); }
const loads = json('reliability/load-samples.json');
const requests = read('reliability/requests.ndjson').trim().split(/\r?\n/).map(JSON.parse)
  .filter(r=>r.scenario==='Five-minute concurrent-user diagnostic: 5, 10, 25 and 50 users');
assert.ok(loads.length); assert.ok(loads.every(l=>l.readyStatus===200)); assert.ok(requests.every(r=>r.status===200));
let offset = 0;
const loadStats = [5,10,25,50].map(users=>{
  const samples = loads.filter(l=>l.users===users), count=samples.length*users*2;
  const group=requests.slice(offset, offset+count); offset+=count;
  const times=group.map(r=>r.ms).sort((a,b)=>a-b);
  return { users, requests: group.length, errors: 0, p95Ms: times[Math.ceil(times.length*.95)-1],
    peakRssMb: Math.max(...samples.map(l=>l.rssMb)) };
});
assert.equal(offset, requests.length);
const recovery=json('reliability/recovery.json');
const proofPath=path.join(out,'publication.json');
const publication=fs.existsSync(proofPath)?JSON.parse(fs.readFileSync(proofPath,'utf8')):null;
const gate={passed:true, generatedAt:new Date().toISOString(), rows, apks, loadStats,
  automationActivation:'Disabled in production pending physical-phone acceptance', publication};
fs.writeFileSync(path.join(out,'release-gate.json'),JSON.stringify(gate,null,2));
const fixes = [
  ['Malformed Passenger GPS', 'Null, blank, boolean and string coordinates could become misleading positions and trigger legacy unloading.', 'Require numeric coordinates before updating the passenger location.'],
  ['Concurrent para alerts', 'Simultaneous taps could bypass the cooldown.', 'Recheck the cooldown inside the trip transaction.'],
  ['Notification outages', 'A saved para or support message could return an error after committing, encouraging retries.', 'Return the saved result; record notification delivery failure separately. Delivery still needs the external service.'],
  ['Support records', 'Empty messages could leave orphan threads; concurrent replies could lose unread increments.', 'Validate before creation; commit thread/message together and update unread counts atomically.'],
  ['Driver support', 'General help could incorrectly require a trip.', 'Allow general help while preserving route/trip ownership checks.'],
  ['Seat and booking eligibility', 'Capacity could be reduced below reserved/onboard seats; inactive assignments could still receive bookings.', 'Serialize capacity changes with trip operations and verify active vehicle, driver and route before reservation.'],
  ['Live route path editing', 'Changing the path during a journey could invalidate its saved destination.', 'Reject path edits while active or scheduled trips use the route.'],
  ['Booking expiry/history', 'The TTL index deleted bookings linked to rides, removing support context.', 'Replace only the booking TTL with a normal expiry index. Expired reservations become expired on roster reads, and history stays available.'],
  ['Passenger analysis', 'Unused code and imports produced analysis warnings.', 'Remove unused private declarations/imports and apply the formatting fixes; rerun all Passenger tests.'],
];
const limitations = 'This is bounded testing, not proof of every possible interaction. Browser checks use real Flutter controls and API handlers against temporary loopback MongoDB/Redis data; some ride-state preconditions are seeded. Email transport, selected failures and GPS observations are controlled in the lab. No physical Android device was available: background GPS, battery restrictions, installation/update, real road arrival detection and actual companion unloading remain unverified. SMTP/FCM delivery, social login providers, multi-hour soak, OS process recovery and production-scale 100-driver GPS load were not certified. The 100-jeep test checks fleet rendering and live updates, not 100 concurrent driver transmitters. Automation rollout flags remain disabled; existing flows remain available. Previously deleted booking records are not recovered by the index migration.';
const rowMd=rows.map(r=>`| ${r.name} | ${r.passed} | 0 | [Evidence](${r.evidence}) |`).join('\n');
const fixesMd=fixes.map(([n,b,a])=>`| ${n} | ${b} | ${a} |`).join('\n');
const loadMd=loadStats.map(l=>`| ${l.users} | ${l.requests} | ${l.errors} | ${l.p95Ms.toFixed(1)} | ${l.peakRssMb.toFixed(1)} |`).join('\n');
const pub = publication ? 'Publication evidence is recorded in [publication.json](publication.json).\n\n```json\n'+JSON.stringify(publication,null,2)+'\n```' : 'Test gate passed. Publication has not yet been recorded.';
const md=`# SAKAY full system release check — 11 October 2026\n\nThe recorded final runs below passed. Earlier failed runs remain in this folder; their defects or fixture errors were corrected and rerun. No unresolved failure was found in the executed checks.\n\n## Results\n\n| Suite | Passed | Failed | Evidence |\n|---|---:|---:|---|\n${rowMd}\n\nAll four Flutter projects have clean analysis. APK package IDs, version, build, universal architectures and matching installation signatures were verified.\n\n## Errors found and fixed\n\n| Area | What went wrong | Correction |\n|---|---|---|\n${fixesMd}\n\n## Scenario coverage\n\nAuthentication covers Admin password/code, empty/wrong credentials, cooldowns, expiry, role/ownership denial, refresh-token reuse, session revocation, persistence and logout. Booking covers solo/group, shared and separate destinations, individual fare totals, changed-price review, cancellation, transfers, capacity contention, duplicate requests and legacy journeys. GPS covers malformed/stale/inaccurate samples, missing speed, ordering, stream changes, drive-bys, automatic start/departure, boarding, nearby stops, organizer-first unloading, repeated/concurrent unloading and early ending. UI covers saved pins, missing selections, quote outage/retry, remaining members, narrow screens, enlarged text in widget tests, walk-in controls, glass dialogs, notice swipe/timeout, map zoom/selection and fleet search/filter/cache recovery. Reports check member destinations and Manila operating dates. Support covers ownership, empty input, close/reopen, concurrent messages and notification failure.\n\n## Reliability measurements\n\n60 completed legacy ride cycles passed: 30 terminal group and 30 roadside solo. Last-seat contention and listener/database-client reconnection also passed. Recovery preserved the ride and occupancy in ${recovery.recoveryMs.toFixed(1)} ms. This was an HTTP listener restart and MongoDB client reconnect, not an OS restart.\n\nThe five-minute diagnostic used four 75-second levels. All measured authenticated load requests and readiness checks returned 200. Numbers describe this local machine and temporary database.\n\n| Concurrent users | Measured requests | Errors | p95 ms | Peak Node RSS MB |\n|---:|---:|---:|---:|---:|\n${loadMd}\n\n## Browser evidence\n\n${browser.map(c=>`- **PASS** ${c.name} — [Screenshot](${c.evidence})`).join('\n')}\n\nFixture corrections were kept separate from product defects: fresh Chromium GPS after multi-role login; Flutter semantic dropdown/card locators; awaiting completed price review before changing prices; restoring draft pins after cancellation; and absolute Flutter web output paths on Windows.\n\n## Versions\n\n| Application | Version | Build |\n|---|---|---:|\n| Passenger APK | 1.1.0 | 21 |\n| Driver APK | 1.1.0 | 21 |\n| Admin web | 1.1.0 | 2 |\n\n${apks.map(a=>`${a.app} SHA-256: \`${a.sha256}\``).join('\n\n')}\n\n## Publication\n\n${pub}\n\n## Limits and rollout\n\n${limitations}\n`;
fs.writeFileSync(path.join(out,'REPORT.md'),md);
const table=(headers,body)=>`<div class="scroll"><table><thead><tr>${headers.map(h=>'<th>'+html(h)+'</th>').join('')}</tr></thead><tbody>${body.map(row=>'<tr>'+row.map(v=>'<td>'+v+'</td>').join('')+'</tr>').join('')}</tbody></table></div>`;
const page=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SAKAY release test report</title><style>body{margin:0;background:#eef4f2;color:#173c35;font:16px/1.6 system-ui}main{max-width:1160px;margin:auto;padding:30px}section{background:white;padding:24px;border-radius:12px;margin:20px 0}h1,h2{line-height:1.25}th,td{text-align:left;padding:12px;border-bottom:1px solid #dce7e3;vertical-align:top}th{background:#e1efea}table{border-collapse:collapse;width:100%}.scroll{overflow:auto}a{color:#006e5e}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(245px,1fr));gap:20px}figure{margin:0}img{max-width:100%;max-height:650px;object-fit:contain;display:block;margin:auto}pre{white-space:pre-wrap;overflow-wrap:anywhere}.pass{font-weight:700;color:#006e5e}summary{cursor:pointer;font-weight:600}small{color:#526b64}</style><main><h1>SAKAY system test & release</h1><p>11 October 2026 · Passenger/Driver <b>1.1.0 +21</b> · Admin <b>1.1.0 +2</b></p><p class="pass">PASS — all recorded final checks below.</p><p><a href="REPORT.md">Full written report</a> · <a href="release-gate.json">Machine-readable gate</a></p><section><h2>Test results</h2>${table(['Suite','Passed','Failed','Evidence'],rows.map(r=>[html(r.name),r.passed,0,`<a href="${r.evidence}">Open</a>`]))}</section><section><h2>Errors fixed before release</h2>${table(['Area','Observed problem','Fix'],fixes.map(r=>r.map(html)))}</section><section><h2>Five-minute load diagnostic</h2>${table(['Users','Requests','Errors','p95 ms','Peak RSS MB'],loadStats.map(l=>[l.users,l.requests,0,l.p95Ms.toFixed(1),l.peakRssMb.toFixed(1)]))}<p>60 ride cycles passed. Listener/client reconnect preserved ride and occupancy in ${recovery.recoveryMs.toFixed(1)} ms.</p></section><section><h2>UI scenario evidence</h2><div class="grid">${browser.map(c=>`<details><summary><span class="pass">PASS</span> ${html(c.name)}</summary><figure><a href="${c.evidence}"><img loading="lazy" src="${c.evidence}" alt="${html(c.name)}"></a><figcaption><small>${html(c.suite)}</small></figcaption></figure></details>`).join('')}</div></section><section><h2>Publication</h2><pre>${html(publication?JSON.stringify(publication,null,2):'Test gate passed. Publication not yet recorded.')}</pre></section><section><h2>What remains unverified</h2><p>${html(limitations)}</p></section></main></html>`;
fs.writeFileSync(path.join(out,'index.html'),page);
const followup = '../release_followup_fixes_2026-10-11/index.html';
if (fs.existsSync(path.resolve(out, followup))) {
  fs.writeFileSync(path.join(out, 'REPORT.md'), md + `\n## Follow-up fixes\n\nAdditional defects found after this release were fixed and checked separately. See the [follow-up report](${followup}); its results do not change these historical release counts.\n`);
  fs.writeFileSync(path.join(out, 'index.html'), page.replace('<main>', `<main><p><a href="${followup}">View the additional fixes and follow-up checks</a></p>`));
}
console.log(JSON.stringify({ gate:'PASS', suites:rows.length, browserScenarios:browser.length, report:path.join(out,'index.html') }));
