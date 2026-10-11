// Format actual recorded evidence; does not run tests or publish a release.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const out = path.resolve(__dirname, '../artifacts/release_followup_fixes_2026-10-11');
const read = file => {
  const bytes = fs.readFileSync(path.join(out, file));
  return bytes[0] === 255 && bytes[1] === 254 ? bytes.toString('utf16le').slice(1) : bytes.toString('utf8');
};
const json = file => JSON.parse(read(file));
const esc = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const before = json('before/faults/results.json');
assert.equal(before.stats.unexpected, 4);
const rows = [];
for (const [name, file, count] of [
  ['Fault and boundary checks', 'after/faults/results.json', 30],
  ['Route snapshot and trip-creation race', 'route-races/faults/results.json', 2],
  ['Main API flows and Admin browser', 'browser/baseline/results.json', 10],
]) {
  const result = json(file);
  assert.equal(result.stats.expected, count);
  assert.equal(result.stats.unexpected, 0);
  assert.equal(result.stats.flaky, 0);
  assert.equal(result.stats.skipped, 0);
  rows.push({ name, passed: count, failed: 0, evidence: file });
}
assert.match(read('backend.log'), /pass 89\b/);
assert.match(read('backend.log'), /fail 0\b/);
rows.push({ name: 'Backend journey, queue, GPS and notification regressions', passed: 89, failed: 0, evidence: 'backend.log' });
const fixes = [
  ['Saved stop-alert acknowledgement showed a server error', 'A notification-write outage returned HTTP 500 although the alert was already acknowledged.', 'The fallback returns the saved acknowledgement, even if notification delivery fails; retries remain safe.'],
  ['Ordinary route edits were blocked', 'Saving a name with an unchanged path returned HTTP 409 while a trip existed.', 'Compare the path before rejecting a geometry change; ordinary edits remain available.'],
  ['Support reopen lost an unread message', 'A stale reopen request overwrote an unread count of three with two after another request sent a message.', 'Change a closed thread atomically and increment its unread count once; return the current thread for repeat requests.'],
  ['Repeated support actions duplicated unread events', 'Three reopen requests increased the unread count from one to four.', 'Reopen and resolve only increment when the status actually changes; repeated requests are idempotent.'],
];
const protections = 'Two further regression checks passed: editing a description preserves an existing trip path snapshot, and a route geometry edit shares the terminal route lock with simultaneous trip creation. New trips read the committed path; active or scheduled trips block actual path changes.';
const limitations = 'These backend fixes address the reproduced defects. Physical Android installation, background GPS, battery restrictions and real-road arrival acceptance still require devices. External SMTP/FCM/social-provider delivery, a multi-hour soak, OS recovery and 100 concurrent driver GPS transmitters remain unverified. Notification storage/delivery outages are logged; this patch does not add a durable notification retry outbox. Automatic group and driver lifecycle rollout remains disabled pending real-phone acceptance. No historical or presentation records were rewritten.';
const publication = fs.existsSync(path.join(out, 'publication.json')) ? json('publication.json') : null;
const summary = { date: '2026-10-11', passed: rows.reduce((sum, row) => sum + row.passed, 0), failed: 0, fixes, rows, publication, limitations };
fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify(summary, null, 2));
const md = `# SAKAY release follow-up fixes — 11 October 2026

Four additional defects were reproduced before the fixes. All ${summary.passed} follow-up checks passed after the fixes. The earlier 625-check release results remain historical evidence, not additional tests counted here.

## Fixed defects

| Problem | Before | After |
|---|---|---|
${fixes.map(row => '| ' + row.join(' | ') + ' |').join('\n')}

${protections}

## Verification

| Suite | Passed | Failed | Evidence |
|---|---:|---:|---|
${rows.map(row => `| ${row.name} | ${row.passed} | 0 | [Evidence](${row.evidence}) |`).join('\n')}

[Before-fix failures](before/faults/html-report/index.html) · [After-fix fault report](after/faults/html-report/index.html) · [Route race report](route-races/faults/html-report/index.html) · [Admin browser report](browser/baseline/html-report/index.html)

All tests used isolated loopback databases and synthetic accounts. The Admin browser checks exercised password/OTP login, navigation, reload, logout and a narrow viewport. Other Playwright scenarios exercised real API handlers; they are not all browser interactions. Backend regressions cover legacy/v2 rides, terminal queues, automatic driver lifecycle, ordering, capacity, concurrency and para push receipts.

## Release

${publication ? JSON.stringify(publication, null, 2) : 'Code verification passed. Publication is pending.'}

This is a backend patch. Passenger and Driver remain version **1.1.0, build 21**; Admin remains version **1.1.0, build 2**. No replacement APK is needed for these backend changes.

## Remaining acceptance work

${limitations}
`;
fs.writeFileSync(path.join(out, 'REPORT.md'), md);
const table = (headers, body) => `<div class="scroll"><table><thead><tr>${headers.map(header => `<th>${esc(header)}</th>`).join('')}</tr></thead><tbody>${body.map(row => '<tr>' + row.map(cell => `<td>${cell}</td>`).join('') + '</tr>').join('')}</tbody></table></div>`;
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SAKAY follow-up fixes</title><style>body{margin:0;background:#eff7f3;color:#173b2e;font:17px/1.6 system-ui,sans-serif}main{max-width:1080px;margin:auto;padding:30px}section{margin:24px 0;padding:22px;background:white;border:1px solid #cfdfd6;border-radius:14px}h1{line-height:1.2}a{color:#126c50}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:12px;border-bottom:1px solid #dce7e0;vertical-align:top}.scroll{overflow:auto}pre{overflow:auto;font-size:14px}.pass{color:#126c50;font-weight:700}</style><main><h1>SAKAY follow-up fixes</h1><p>11 October 2026 · <strong class="pass">${summary.passed} passed · 0 failed</strong></p><p>Four additional defects were reproduced before the fixes. The original 625-check release results remain available separately.</p><section><h2>Fixed defects</h2>${table(['Problem', 'Before', 'After'], fixes.map(row => row.map(esc)))}<p>${esc(protections)}</p></section><section><h2>Verification</h2>${table(['Suite', 'Passed', 'Failed', 'Evidence'], rows.map(row => [esc(row.name), row.passed, 0, `<a href="${row.evidence}">Result</a>`]))}<p><a href="before/faults/html-report/index.html">Before-fix failures</a> · <a href="after/faults/html-report/index.html">After-fix faults</a> · <a href="route-races/faults/html-report/index.html">Route races</a> · <a href="browser/baseline/html-report/index.html">Admin browser</a></p><p>Isolated loopback MongoDB and Redis, synthetic accounts. Playwright API scenarios plus two actual Admin browser checks; no production data was seeded or changed.</p></section><section><h2>Release</h2><pre>${esc(publication ? JSON.stringify(publication, null, 2) : 'Code verification passed. Publication pending.')}</pre><p>Passenger and Driver: <strong>1.1.0, build 21</strong>. Admin: <strong>1.1.0, build 2</strong>. Backend patch; no replacement APK needed.</p></section><section><h2>Remaining acceptance work</h2><p>${esc(limitations)}</p></section><p><a href="REPORT.md">Written report</a> · <a href="../full_system_release_2026-10-11/index.html">Original release report</a></p></main></html>`;
fs.writeFileSync(path.join(out, 'index.html'), page);
console.log(JSON.stringify({ passed: summary.passed, failed: 0, report: path.join(out, 'index.html') }));
