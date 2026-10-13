// Formats executed evidence; never runs tests or changes live data.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const out = path.resolve(__dirname, '../artifacts/driver_queue_fix_2026-10-13');
const read = name => { const bytes = fs.readFileSync(path.join(out, name)); return bytes[0] === 255 && bytes[1] === 254 ? bytes.toString('utf16le').slice(1) : bytes.toString('utf8'); };
const json = name => JSON.parse(read(name));
assert.match(read('backend-release.log'), /pass 42\b/); assert.match(read('backend-release.log'), /fail 0\b/);
assert.match(read('driver-tests-final.log'), /\+60: All tests passed/);
assert.match(read('driver-analysis-final.log'), /No issues found!/);
const ui = json('browser-results.json'); assert.equal(ui.passed, 6); assert.equal(ui.failed, 0); assert.deepEqual(ui.pageErrors, []);
const reset = json('queue-reset.json'); assert.equal(reset.remainingEntries, 0); assert.equal(reset.historicalRecordsDeleted, 0);
const apk = json('verified-apks.json').apks[0]; assert.equal(apk.build, 23); assert.equal(apk.signatureVerified, true);
const publication = fs.existsSync(path.join(out, 'publication.json')) ? json('publication.json') : null;
const summary = { date: '2026-10-13', passed: 108, failed: 0, backend: 42, driver: 60, browser: 6, queueEntriesCleared: reset.results.length,
  remainingAfterClear: reset.remainingEntries, historicalRecordsDeleted: 0, driverVersion: apk.version, driverBuild: apk.build,
  passengerVersion: '1.1.0', passengerBuild: 22, publication };
fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify(summary, null, 2));
const md = `# Driver route and terminal queue fixes — 13 October 2026

Drivers can select any active route with a configured terminal while using their assigned jeepney. Selecting a route now updates the driver profile used by GPS, pickup visibility, map route and realtime subscriptions. An existing live trip must be cancelled or finished before selecting another route.

The Trip menu shows **Choose route** when there is no live trip, and **Cancel queue** for an empty terminal entry. Cancellation works before terminal arrival and while waiting, loading or skipped. It closes the terminal trip, cancels unboarded reservations, clears driver queue fields and promotes the next eligible waiting jeep. Completed/history records remain. Onboard or walk-in passengers block cancellation; departing trips remain intact. Cancelling pauses automatic re-entry until a new route/trip is explicitly selected, so GPS cannot immediately put the driver back in the queue.

## Live queue cleanup

${reset.results.length} current entry was cancelled after a private backup. There were zero onboard passengers and zero pending bookings in the inspected entry. No live terminal entries remained immediately after cleanup. No historical trip, booking, ride or audit records were deleted. The route queue counter/lock documents are retained for concurrency and history.

## Verification

| Suite | Passed | Failed |
|---|---:|---:|
| Backend queue, route, lifecycle and group-ride regressions | 42 | 0 |
| Driver Flutter tests | 60 | 0 |
| Driver browser scenarios | 6 | 0 |
| **Total** | **108** | **0** |

Driver static analysis is clean. Backend tests cover pending/loading cancellation, promotion, repeated and concurrent actions, route choice races, departure races, ownership, passenger protection, legacy/v2 reservation cancellation, notification outages and prevention of GPS re-entry. The six browser scenarios use real Flutter controls against disposable loopback MongoDB/Redis accounts. Initial failed runs are retained; they identified a weekday-dependent fixture, browser input timing and the hidden route choice after cancellation. No production accounts were used in UI tests.

${ui.cases.map(test => `- **PASS** ${test.name} — [Screenshot](${test.evidence})`).join('\n')}

## Driver APK

Driver **${apk.version}, build ${apk.build}**. Passenger stays **1.1.0, build 22**. Package ID, universal architectures, non-debuggable release mode and v2 signature matching existing installations were verified. SHA-256: \`${apk.sha256}\`.

[Local Driver APK](${path.basename(apk.file)})

${publication ? `[Published Driver APK](${publication.mobile[0].url})\n\nGitHub commit: \`${publication.commit}\`. Deployments and both public mobile catalogs verified; required-update minimum unchanged.` : 'Publication pending.'}

## Limits

Physical Android installation/update and background/real-road GPS acceptance were not executed. Automatic group and driver lifecycle rollout remains disabled pending phone acceptance. This patch preserves the current solo/group rollout setting and old journey behavior. Notification outages are logged after committed cancellation; durable delivery retry is outside this patch.
`;
fs.writeFileSync(path.join(out, 'REPORT.md'), md);
const esc = value => String(value).replace(/[&<>"']/g, character => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[character]));
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Driver route and queue fixes</title><style>body{background:#eff7f3;color:#173b2e;font:17px/1.6 system-ui;margin:0}main{max-width:1000px;margin:auto;padding:26px}section,details{background:white;border:1px solid #cfdfd6;border-radius:12px;padding:20px;margin:20px 0}a{color:#126c50}img{max-width:100%;max-height:800px;display:block;margin:auto}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}h1{line-height:1.2}</style><main><h1>Driver route and queue fixes</h1><p>13 October 2026 · <strong>108 passed · 0 failed</strong></p><section><h2>What changed</h2><p>Choose an active route in the Trip menu. The selected route now updates the profile, GPS context and map. Cancel queue closes an empty terminal entry, releases unboarded bookings and lets the next jeep load. GPS will not rejoin a cancelled queue until the driver chooses a trip again.</p><p>Onboard passengers block queue cancellation. Route changes wait until the current trip is cancelled or finished.</p></section><section><h2>Current queues cleared</h2><p>${reset.results.length} empty entry cancelled after a private backup. No current entries remained immediately after cleanup. No historical records deleted.</p></section><section><h2>Checks</h2><p>42 backend regressions, 60 Driver tests and six browser scenarios passed. Driver analysis is clean. Browser scenarios use synthetic accounts and loopback databases.</p></section>${ui.cases.map(test => `<details><summary>PASS: ${esc(test.name)}</summary><a href="${test.evidence}"><img src="${test.evidence}" alt="${esc(test.name)}"></a></details>`).join('')}<section><h2>Driver APK</h2><p>Version ${apk.version} · Build ${apk.build}. Passenger remains 1.1.0 build 22.</p><p><a href="${publication ? publication.mobile[0].url : path.basename(apk.file)}">Download Driver APK</a></p><pre>SHA-256: ${apk.sha256}</pre><p>Signature, package ID, architectures and release mode verified.</p><pre>${esc(publication ? JSON.stringify({commit:publication.commit,publishedAt:publication.publishedAt,backend:publication.backend,admin:publication.admin},null,2) : 'Publication pending.')}</pre></section><section><h2>Acceptance still needed</h2><p>Physical phone installation, background GPS and real-road acceptance remain unverified. Automatic group and driver lifecycle rollout remains disabled.</p></section><p><a href="REPORT.md">Written report</a></p></main></html>`;
fs.writeFileSync(path.join(out, 'index.html'), page);
console.log(JSON.stringify({ passed: 108, failed: 0, queueEntriesCleared: summary.queueEntriesCleared, published: !!publication }));
