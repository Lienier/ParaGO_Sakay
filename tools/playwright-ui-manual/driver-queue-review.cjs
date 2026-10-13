// Real Driver Flutter controls and API, with disposable loopback records only.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
process.env.UI_LAB_ARTIFACT_DIR = 'artifacts/driver_queue_fix_2026-10-13';
process.env.UI_LAB_BUILD_DIR = process.env.UI_LAB_ARTIFACT_DIR;
process.env.UI_LAB_AUTOMATIC_LIFECYCLE = 'false';
const { createLab } = require('./fixture.cjs');
const { chromium } = require('../../.tools/playwright/node_modules/playwright');
const out = path.resolve(__dirname, '../..', process.env.UI_LAB_ARTIFACT_DIR);
let lab, browser, page;
const cases = [], errors = [];
const seen = text => page.getByText(text, { exact: true }).or(page.getByLabel(text, { exact: true })).first().waitFor();
const click = text => page.getByText(text, { exact: true }).or(page.getByLabel(text, { exact: true })).first().click();
async function check(name, action) {
  await action();
  const evidence = `ui-${cases.length + 1}.png`;
  await page.screenshot({ path: path.join(out, evidence) });
  cases.push({ name, status: 'PASS', evidence }); console.log('PASS: ' + name);
}
async function waitForState(predicate) {
  for (let i = 0; i < 80; i++) { if (await predicate()) return; await page.waitForTimeout(150); }
  throw Error('State did not settle');
}
async function type(label, value) {
  const input = page.getByRole('textbox', { name: label, exact: true });
  await input.click(); await page.waitForTimeout(150); await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace'); await page.waitForTimeout(80);
  await page.keyboard.type(value, { delay: 35 }); assert.equal(await input.inputValue(), value);
}
(async () => {
  try {
    lab = await createLab();
    const alternative = await lab.models.Route.create({ name: 'Alternate Route', code: 'PW-ALT', status: 'active', direction: 'up',
      path: { type: 'LineString', coordinates: [[121.05, 14.905], [121.05, 14.93]] },
      terminal: { enabled: true, name: 'Alternate Terminal', stopRef: 'ALT-START', location: lab.point(14.905), radiusMeters: 100 },
      stops: [{ name: 'Alternate Terminal', order: 0, location: lab.point(14.905) }, { name: 'End', order: 1, location: lab.point(14.93) }] });
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, permissions: ['geolocation'],
      geolocation: { latitude: 14.925, longitude: 121.05, accuracy: 5 } });
    page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (/overflowed by|RenderFlex|EXCEPTION CAUGHT BY/i.test(message.text())) errors.push(message.text()); });
    await page.goto('http://127.0.0.1:8773');
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await type('Email address', lab.accounts.driver.email); await type('Password', lab.password);
    await page.getByRole('button', { name: 'LOGIN', exact: true }).click(); await seen('Drive');
    await check('Route choice is available when the driver has no trip', async () => {
      await click('Trip'); await click('Controls');
      await page.getByRole('button', { name: 'Choose route', exact: true }).click();
      await seen('Choose route');
    });
    await check('Driver selects another route and the profile follows that route', async () => {
      await page.getByRole('button', { name: /Playwright Main Route/ }).first().click();
      await page.getByRole('menuitem', { name: /Alternate Route/ }).first().click();
      await page.getByRole('button', { name: 'Start', exact: true }).last().click();
      await waitForState(async () => !!await lab.models.Trip.exists({ driverId: lab.ids.driver, routeId: alternative._id, status: 'scheduled' }));
      assert.equal(String((await lab.models.Driver.findById(lab.ids.driver)).assignedRouteId), String(alternative._id));
      await seen('Cancel queue');
    });
    const trip = await lab.models.Trip.findOne({ driverId: lab.ids.driver, status: 'scheduled' });
    await check('Stay dismisses queue cancellation without changing the trip', async () => {
      await page.getByRole('button', { name: 'Cancel queue', exact: true }).first().click(); await seen('Cancel queue?');
      await page.getByRole('button', { name: 'Stay', exact: true }).click();
      assert.equal((await lab.models.Trip.findById(trip._id)).status, 'scheduled');
    });
    await check('Cancelling a pending terminal entry returns to route selection', async () => {
      await page.getByRole('button', { name: 'Cancel queue', exact: true }).first().click();
      await page.getByRole('button', { name: 'Cancel queue', exact: true }).last().click();
      await waitForState(async () => (await lab.models.Trip.findById(trip._id)).status === 'cancelled');
      await page.getByRole('button', { name: 'Choose route', exact: true }).waitFor();
      assert.equal(await lab.models.Trip.countDocuments({ driverId: lab.ids.driver, status: { $in: ['active', 'scheduled'] } }), 0);
    });
    await check('The driver can choose the original route after leaving the other queue', async () => {
      await page.getByRole('button', { name: 'Choose route', exact: true }).click();
      await page.getByRole('button', { name: /Alternate Route/ }).first().click();
      await page.getByRole('menuitem', { name: /Playwright Main Route/ }).first().click();
      await page.getByRole('button', { name: 'Start', exact: true }).last().click();
      await waitForState(async () => !!await lab.models.Trip.exists({ driverId: lab.ids.driver, routeId: lab.ids.route, status: 'scheduled' }));
      assert.equal(String((await lab.models.Driver.findById(lab.ids.driver)).assignedRouteId), lab.ids.route);
      await seen('Cancel queue');
    });
    await check('Queue cancellation is readable at 320 pixels without layout errors', async () => {
      await page.setViewportSize({ width: 320, height: 740 }); await page.waitForTimeout(500);
      await page.getByRole('button', { name: 'Cancel queue', exact: true }).first().click(); await seen('Cancel queue?');
      await page.getByRole('button', { name: 'Stay', exact: true }).click();
      assert.deepEqual(errors, []);
    });
    fs.writeFileSync(path.join(out, 'browser-results.json'), JSON.stringify({ passed: cases.length, failed: 0, cases, pageErrors: errors }, null, 2));
  } catch (error) {
    if (page) { await page.screenshot({ path: path.join(out, 'ui-failure.png') }).catch(() => {});
      fs.writeFileSync(path.join(out, 'ui-failure-aria.txt'), await page.locator('body').ariaSnapshot().catch(() => 'Unavailable')); }
    fs.writeFileSync(path.join(out, 'browser-results.json'), JSON.stringify({ passed: cases.length, failed: 1, cases, pageErrors: errors, error: error.message }, null, 2));
    console.error(error.message); process.exitCode = 1;
  } finally { if (browser) await browser.close(); if (lab) await lab.stop(); }
})();
