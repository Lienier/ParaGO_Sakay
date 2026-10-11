// Actual Admin Flutter UI against a loopback-only temporary fleet of 100 jeeps.
const path = require('node:path'), fs = require('node:fs'), crypto = require('node:crypto');
process.env.UI_LAB_ARTIFACT_DIR ||= 'artifacts/admin_live_fleet_2026-10-09';
process.env.UI_LAB_AUTOMATIC_LIFECYCLE = 'false';
process.env.UI_LAB_SHARED_DRIVERS = 'false';
const { createLab } = require('./fixture.cjs');
const { chromium } = require('../../.tools/playwright/node_modules/playwright');
const out = path.resolve(__dirname, '../..', process.env.UI_LAB_ARTIFACT_DIR);
const assert = require('node:assert/strict');
const results = [], errors = [];
let lab, browser, page;
async function check(name, action, evidence) {
  await action(); results.push({ name, status: 'PASS', evidence }); console.log(`PASS: ${name}`);
}
async function shot(name) { await page.screenshot({ path: path.join(out, name), fullPage: false }); }
async function text(name) { await page.getByText(name, { exact: false }).or(page.getByLabel(name, { exact: false })).or(page.getByRole('group', { name, exact: false })).first().waitFor(); }
async function type(locator, value) {
  await locator.click(); await page.waitForTimeout(150);
  await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace'); await page.waitForTimeout(80);
  await page.keyboard.type(value, { delay: 45 });
  assert.equal(await locator.inputValue(), value, 'Flutter input has the intended value before submission');
}
(async () => {
  try {
    lab = await createLab();
    const { User, Driver, Route, Jeepney } = lab.models;
    const otherRoute = await Route.create({ name: 'Synthetic Second Route', code: 'PW-SECOND', status: 'active' });
    const users = await User.insertMany(Array.from({ length: 99 }, (_, i) => ({ email: `fleet-${i}@synthetic.test`, fullName: `Synthetic Driver ${i + 2}`, role: 'DRIVER', status: 'active' })));
    const drivers = await Driver.insertMany(users.map((u, i) => ({ userId: u._id, status: 'active', ...(i < 89 ? { assignedRouteId: i < 49 ? lab.ids.route : otherRoute._id } : {}) })));
    const at = Date.now();
    const jeeps = await Jeepney.insertMany(drivers.map((d, i) => ({ plateNumber: `FLEET ${String(i + 2).padStart(3, '0')}`, status: 'active', currentDriverId: d._id, capacity: 20,
      ...(i < 90 ? { lastKnownLocation: { type: 'Point', coordinates: [121.04 + (i % 10) * 0.002, 14.89 + Math.floor(i / 10) * 0.002] },
        lastSeenAt: new Date(at - (i < 30 ? 0 : i < 60 ? 70000 : 600000)) } : {}) })));
    await Promise.all(drivers.map((d, i) => Driver.updateOne({ _id: d._id }, { assignedJeepneyId: jeeps[i]._id })));
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    page = await context.newPage(); page.on('pageerror', e => errors.push(e.message));
    const fleetRequests = [];
    page.on('request', r => { if (r.url().includes('/admin/fleet')) fleetRequests.push(Date.now()); });
    await page.goto(lab.webOrigin); await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
    await type(page.getByRole('textbox', { name: 'Email address' }), lab.accounts.admin.email);
    await type(page.getByRole('textbox', { name: 'Password', exact: true }), lab.password);
    await page.getByRole('button', { name: 'LOGIN', exact: true }).click();
    await page.getByRole('textbox', { name: 'Email verification code' }).waitFor();
    await type(page.getByRole('textbox', { name: 'Email verification code' }), lab.mailbox.at(-1).text.match(/\b\d{6}\b/)[0]);
    await page.getByRole('button', { name: 'Verify and sign in' }).click();
    await page.getByText('Live fleet map', { exact: true }).first().click();
    await check('Admin opens live fleet map with all 100 registered jeeps and a live socket', async () => {
      await text('100 jeeps shown'); await text('Live connection'); await shot('01-fleet-100-jeeps.png');
    }, '01-fleet-100-jeeps.png');
    await check('Nearby jeeps are grouped while missing-GPS vehicles remain listed', async () => {
      assert.ok(await page.getByRole('button', { name: /grouped jeeps/ }).count() > 0);
      await text('No GPS: 9'); await shot('02-fleet-clusters.png');
    }, '02-fleet-clusters.png');
    await check('Plate search selects the assigned idle jeep and shows driver and route', async () => {
      await type(page.getByRole('textbox', { name: 'Search plate or driver' }), 'PW 123');
      await text('1 jeeps shown'); await page.getByText('PW 123', { exact: false }).last().click();
      await text('Driver: Playwright driver'); await text('Route: Playwright Main Route'); await shot('03-selected-jeep.png');
    }, '03-selected-jeep.png');
    await check('Real accepted driver GPS moves the selected jeep without a full fleet reload', async () => {
      const count = fleetRequests.length;
      const token = await lab.syntheticToken(lab.accounts.driver);
      const res = await fetch(`${lab.apiOrigin}/api/v1/drivers/me/location`, { method: 'PATCH', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ latitude: 14.911, longitude: 121.051, accuracyMeters: 5, speedMetersPerSecond: 2, streamId: crypto.randomUUID(), sequence: 1, capturedAt: new Date().toISOString() }) });
      assert.equal(res.status, 200, await res.text());
      await text('14.91100, 121.05100');
      assert.equal(fleetRequests.length, count); await page.getByRole('button', { name: 'Fit visible jeeps', exact: true }).click(); await shot('04-live-location-moved.png');
    }, '04-live-location-moved.png');
    await check('Route filter limits the map and missing-GPS jeep details are explicit', async () => {
      await page.getByRole('button', { name: 'Clear fleet search', exact: true }).click();
      await text('100 jeeps shown');
      console.log('Route button bounds:', await page.getByRole('button', { name: 'Route All routes', exact: true }).boundingBox());
      await page.mouse.click(795, 231);
      await page.waitForTimeout(250);
      await shot('route-menu.png');
      await page.mouse.click(650, 375);
      await text('40 jeeps shown'); await shot('05-route-filter.png');
      await page.mouse.click(795, 231); await page.waitForTimeout(200); await page.mouse.click(650, 135);
      await text('10 jeeps shown');
      await type(page.getByRole('textbox', { name: 'Search plate or driver' }), 'FLEET 100');
      await page.getByText('FLEET 100', { exact: false }).last().click(); await text('GPS: No GPS · No location received');
      await shot('06-missing-gps.png');
    }, '05-route-filter.png');
    await check('Failed snapshot refresh preserves the last fleet and a later refresh recovers', async () => {
      await page.route('**/admin/fleet', r => r.fulfill({ status: 503, contentType: 'application/json', body: '{"success":false,"message":"Synthetic offline"}' }));
      await page.getByRole('button', { name: 'Refresh fleet', exact: true }).click();
      await text('Refresh failed. Showing previous locations.'); await text('1 jeeps shown'); await shot('07-refresh-failure.png');
      await page.unroute('**/admin/fleet'); await page.getByRole('button', { name: 'Refresh fleet', exact: true }).click();
      await page.waitForFunction(() => !document.body.innerText.includes('Refresh failed. Showing previous locations.'));
    }, '07-refresh-failure.png');
    await check('Phone-width navigation, search and fleet map remain usable', async () => {
      await page.getByRole('button', { name: 'Clear fleet search', exact: true }).click();
      await page.mouse.click(795, 231); await page.waitForTimeout(200); await page.mouse.click(650, 183);
      await text('100 jeeps shown'); await page.getByRole('button', { name: 'Fit visible jeeps', exact: true }).click();
      await page.setViewportSize({ width: 390, height: 844 }); await page.mouse.move(350, 150); await page.mouse.wheel(0, -3000); await shot('08-narrow-fleet.png');
      await text('100 jeeps shown');
    }, '08-narrow-fleet.png');
    assert.deepEqual(errors, []);
    await context.close();
  } catch (error) {
    console.error(error.stack);
    results.push({ name: 'Review interrupted: ' + error.message, status: 'FAIL', evidence: 'failure.png' });
    if (page) { await shot('failure.png'); fs.writeFileSync(path.join(out, 'failure-dom.txt'), await page.locator('body').innerText()); }
    if (page) fs.writeFileSync(path.join(out, 'failure-accessibility.txt'), await page.locator('body').ariaSnapshot());
    process.exitCode = 1;
  } finally {
    fs.writeFileSync(path.join(out, 'browser-results.json'), JSON.stringify(results, null, 2));
    fs.writeFileSync(path.join(out, 'page-errors.json'), JSON.stringify(errors, null, 2));
    if (browser) await browser.close(); if (lab) await lab.stop();
  }
})();
