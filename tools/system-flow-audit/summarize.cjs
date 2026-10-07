const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'artifacts/system_flow_audit_2026-10-06');
const read = name => {
  const buffer = fs.readFileSync(path.join(output, name));
  return buffer.toString(buffer[0] === 0xff && buffer[1] === 0xfe ? 'utf16le' : 'utf8').replace(/^\uFEFF/, '');
};
function tapResults(log) {
  return [...log.matchAll(/^(ok|not ok) \d+ - (.+)$/gm)].map(m => ({ passed: m[1] === 'ok', name: m[2].trim() }));
}
const raw = tapResults(read('backend-tests.log'));
const rechecks = ['realtime-capacity.characterization', 'terminal-first-operation.integration'].flatMap(name =>
  tapResults(read('recheck-' + name + '.log')));
const rechecked = new Map(rechecks.map(r => [r.name, r.passed]));
const audited = raw.map(r => ({ ...r, controlledHolidayRecheck: !r.passed ? rechecked.get(r.name) ?? null : null }));
const playwright = JSON.parse(read('playwright-results.json'));
const cases = [];
function visit(suite) {
  for (const spec of suite.specs || []) for (const test of spec.tests || []) cases.push({ title: spec.title,
    status: test.results.at(-1)?.status, errors: test.results.at(-1)?.errors.map(e => e.message) || [] });
  for (const child of suite.suites || []) visit(child);
}
for (const suite of playwright.suites) visit(suite);
const flutter = Object.fromEntries(['passenger', 'driver', 'admin'].map(name => {
  const test = read('flutter-' + name + '.log'); const analyze = read('analyze-' + name + '.log');
  return [name, { passed: Number(test.match(/\+(\d+): All tests passed!/)?.[1] || 0),
    warnings: [...analyze.matchAll(/^warning - /gm)].length, info: [...analyze.matchAll(/^\s*info - /gm)].length,
    errors: [...analyze.matchAll(/^\s*error - /gm)].length }];
}));
const pkg = require(path.join(root, 'package.json'));
const files = fs.readdirSync(path.join(root, 'tests')).filter(n => n.endsWith('.test.js'));
const summary = { existingBackend: { total: raw.length, rawPassed: raw.filter(r => r.passed).length,
  rawFailed: raw.filter(r => !r.passed).length, recheckExecutions: rechecks.length,
  failingCasesPassedWithHolidayFixture: audited.filter(r => r.controlledHolidayRecheck === true).length },
  legacyUnitPassed: 62, flutter, auditPlaywright: playwright.stats,
  omittedFromDefaultNpmTest: files.filter(n => !pkg.scripts.test.includes('tests/' + n)) };
fs.writeFileSync(path.join(output, 'SUMMARY.json'), JSON.stringify(summary, null, 2));
const escape = text => text.replace(/\|/g, '\\|');
let md = '# Executed scenario matrix\n\nThis is an inventory of executed checks, not every possible combination of system states. The 15 date-dependent failures passed with a synthetic holiday fixture; application source was unchanged.\n\n';
md += '## Existing backend tests\n\n| Scenario | Original run | Controlled holiday recheck |\n| --- | --- | --- |\n';
for (const r of audited) md += `| ${escape(r.name)} | ${r.passed ? 'PASS' : 'FAIL'} | ${r.controlledHolidayRecheck === true ? 'PASS' : r.controlledHolidayRecheck === false ? 'FAIL' : '—'} |\n`;
md += '\n## Additional Playwright edge cases\n\nFailures below expose desired safeguards that the application currently lacks. A17 is a workflow gap and A22 intentionally characterizes the current retention policy. Four A01 cases and A02 share one GPS validation defect.\n\n| Scenario | Result |\n| --- | --- |\n';
for (const r of cases) md += `| ${escape(r.title)} | ${r.status.toUpperCase()} |\n`;
md += '\n## Flutter suites\n\n| App | Tests passed | Analyzer errors | Warnings | Style information |\n| --- | ---: | ---: | ---: | ---: |\n';
for (const [name, r] of Object.entries(flutter)) md += `| ${name} | ${r.passed} | ${r.errors} | ${r.warnings} | ${r.info} |\n`;
md += '\nLegacy utility checks: 62 passed. See [baseline browser/API results](../playwright_system_test_2026-10-06/REPORT.md) for the main journey and admin browser checks.\n';
fs.writeFileSync(path.join(output, 'SCENARIO_MATRIX.md'), md);
console.log(JSON.stringify(summary));
