// Actual web UIs with disposable records and Chromium GPS; never loads live data.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
process.env.UI_LAB_ARTIFACT_DIR ||= 'artifacts/road_markers_waiting_2026-10-11';
process.env.UI_LAB_AUTOMATIC_LIFECYCLE = 'false';
const { createLab } = require('./fixture.cjs');
const { chromium } = require('../../.tools/playwright/node_modules/playwright');
const out = path.resolve(__dirname, '../..', process.env.UI_LAB_ARTIFACT_DIR);
const results = [], errors = [], gpsUploads = [];
let lab, browser, passenger, driver, admin, pc;
async function check(name, fn, evidence) {
  await fn(); results.push({name, status:'PASS', evidence}); console.log('PASS: ' + name);
}
async function seen(page, text) {
  await page.getByText(text, {exact:false}).or(page.getByLabel(text, {exact:false})).first().waitFor();
}
async function shot(page, file) { await page.screenshot({path:path.join(out, file)}); }
async function type(page, label, value) {
  const field = page.getByRole('textbox', {name:label, exact:true});
  await field.click(); await page.waitForTimeout(150); await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace'); await page.waitForTimeout(80);
  await page.keyboard.type(value, {delay:35}); assert.equal(await field.inputValue(), value);
}
async function login(page, role, port) {
  page.on('pageerror', e => errors.push({role, error:e.message}));
  page.on('console', m => { if (/overflowed by|RenderFlex|EXCEPTION CAUGHT BY/i.test(m.text())) errors.push({role, error:m.text()}); });
  await page.goto('http://127.0.0.1:' + port);
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await type(page, 'Email address', lab.accounts[role].email);
  await type(page, 'Password', lab.password);
  await page.getByRole('button', {name:'LOGIN', exact:true}).click();
  if (role === 'admin') {
    await page.getByRole('textbox', {name:'Email verification code'}).waitFor();
    await type(page, 'Email verification code', lab.mailbox.at(-1).text.match(/\b\d{6}\b/)[0]);
    await page.getByRole('button', {name:'Verify and sign in'}).click();
    await page.getByText('Live fleet map', {exact:true}).first().click();
    await seen(page, 'Live connection');
  } else await seen(page, role === 'driver' ? 'Drive' : 'SAKAY');
}
async function refresh(page) {
  await page.getByRole('button', {name:'More', exact:true}).click();
  await page.getByRole('menuitem', {name:'Refresh', exact:true}).click(); await page.waitForTimeout(800);
}
async function gps(latitude, accuracy = 5) {
  await pc.setGeolocation({latitude, longitude:121.05, accuracy});
  await passenger.waitForTimeout(5500);
}
async function trigger(latitude) {
  for (let i = 0; i < 6; i++) {
    await gps(latitude);
    if (await passenger.getByText('Still waiting?', {exact:true}).count()) return;
  }
  await seen(passenger, 'Still waiting?');
}
async function zoomEvidence(page, role) {
  const marker = page.getByRole('button', {name:/Jeep PW 123/}).first();
  await marker.waitFor();
  await shot(page, `${role}-normal.png`);
  const b = await marker.boundingBox(); assert.ok(b);
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  for (let i = 0; i < 3; i++) { await page.mouse.wheel(0, -250); await page.waitForTimeout(350); }
  await shot(page, `${role}-zoom-in.png`);
  for (let i = 0; i < 4; i++) { await page.mouse.wheel(0, 250); await page.waitForTimeout(350); }
  await shot(page, `${role}-zoom-out.png`);
  assert.deepEqual(errors, []);
}
(async () => {
  try {
    lab = await createLab();
    const trip = await lab.models.Trip.create({flowVersion:2, driverId:lab.ids.driver,
      jeepneyId:lab.ids.jeepney, routeId:lab.ids.route, status:'active', active:true,
      acceptRequests:true, startedAt:new Date(), operatingMode:'route', terminalQueueStatus:'departed'});
    browser = await chromium.launch({headless:true});
    pc = await browser.newContext({viewport:{width:390, height:844},
      geolocation:{latitude:14.898, longitude:121.05, accuracy:5}, permissions:['geolocation']});
    const dc = await browser.newContext({viewport:{width:390, height:844},
      geolocation:{latitude:14.9, longitude:121.05, accuracy:5}, permissions:['geolocation']});
    const ac = await browser.newContext({viewport:{width:1440, height:1000}});
    passenger = await pc.newPage(); driver = await dc.newPage(); admin = await ac.newPage();
    passenger.on('response', response => {
      if (response.request().method() === 'POST' && response.url().endsWith('/passengers/me/location')) {
        gpsUploads.push({status: response.status(), at: new Date().toISOString()});
      }
    });
    await login(passenger, 'passenger', 8772); await login(driver, 'driver', 8773); await login(admin, 'admin', 8771);
    // Chromium retains the timestamp of a geolocation override until it is
    // updated. Login to three apps can age that synthetic fix past 15 seconds.
    // Provide a fresh observation, as a real GPS device would, before map QA.
    await pc.setGeolocation({latitude:14.898, longitude:121.05, accuracy:5});
    await passenger.getByRole('button', {name:'Recenter', exact:true}).click();
    await passenger.waitForTimeout(1000);
    await check('Passenger jeep remains selectable across zoom levels', () => zoomEvidence(passenger, 'passenger'), 'passenger-zoom-in.png');
    await check('Driver uses the same road-scaled jeep marker across zoom levels', async () => {
      // Driver marker is informational rather than an action.
      await shot(driver, 'driver-normal.png');
      // Follow mode places the jeep in the lower center. Zoom around that point
      // so the screenshot keeps the informational marker in view.
      await driver.mouse.move(195, 540);
      for (let i=0;i<3;i++) { await driver.mouse.wheel(0,-250); await driver.waitForTimeout(350); }
      await shot(driver, 'driver-zoom-in.png');
      for (let i=0;i<4;i++) { await driver.mouse.wheel(0,250); await driver.waitForTimeout(350); }
      await shot(driver, 'driver-zoom-out.png'); assert.deepEqual(errors,[]);
    }, 'driver-zoom-in.png');
    await check('Admin uses the shared jeep marker and preserves fleet details', async () => {
      await admin.getByRole('button', {name:/Jeep PW 123/}).first().click();
      await seen(admin, 'Driver: Playwright driver'); await zoomEvidence(admin, 'admin');
    }, 'admin-zoom-in.png');
    const Pickup = require('../../src/models/pickupRequest'), Ride = require('../../src/models/rideSession');
    async function booking() {
      return Pickup.create({flowVersion:2, members:[{memberId:'1', organizer:true,label:'You',
        destinationStopRef:'College', destinationLocation:lab.point(14.915),
        fareSnapshot:{boardingStopRef:'Playwright Terminal',boardingStopOrder:0,boardingFare:0,
          destinationStopRef:'College',destinationStopOrder:1,destinationFare:17,amount:17},status:'reserved'}],
        passengerId:lab.ids.passenger, tripSessionId:trip._id, routeId:lab.ids.route,
        status:'pending', pickupType:'roadside', stopRef:'Playwright Terminal', pickupLocation:lab.point(),
        destinationStopRef:'College', destinationLocation:lab.point(14.915), expiresAt:new Date(Date.now()+3600000)});
    }
    const first = await booking(); await refresh(passenger); await gps(14.898);
    await check('A poor-accuracy jump does not show the waiting reminder', async () => {
      await gps(14.891, 100);
      assert.equal(await passenger.getByText('Still waiting?', {exact:true}).count(), 0);
      await gps(14.898); await shot(passenger, 'waiting-no-false-prompt.png');
    }, 'waiting-no-false-prompt.png');
    await check('Moving away opens Waiting and Cancel; Waiting keeps the booking and pickup', async () => {
      await trigger(14.895); await seen(passenger, 'Waiting'); await shot(passenger, 'waiting-moved-away.png');
      assert.ok(gpsUploads.filter(r => r.status === 200).length >= 3,
        'Pending v2 bookings must continue uploading fresh GPS for automatic boarding');
      await passenger.getByRole('button', {name:'Waiting', exact:true}).click();
      await passenger.getByText('Still waiting?', {exact:true}).waitFor({state:'hidden'});
      const saved = await Pickup.findById(first._id).lean();
      assert.equal(saved.status, 'pending'); assert.deepEqual(saved.pickupLocation.coordinates, [121.05,14.9]);
      await gps(14.895); assert.equal(await passenger.getByText('Still waiting?', {exact:true}).count(),0);
      await shot(passenger, 'waiting-confirmed.png');
    }, 'waiting-moved-away.png');
    await check('Onboard passengers do not receive the waiting reminder', async () => {
      first.status='completed'; await first.save();
      const ride = await Ride.create({flowVersion:2, members:first.members.map(m=>({...m.toObject(),status:'onboard',boardedAt:new Date()})),
        passengerId:lab.ids.passenger,tripSessionId:trip._id,pickupRequestId:first._id,status:'onboard',boardedAt:new Date(),
        boardingMethod:'auto_proximity',boardingStopRef:'Playwright Terminal',boardingLocation:lab.point(),
        destinationStopRef:'College',destinationLocation:lab.point(14.915),canSendStopAlert:true});
      await refresh(passenger); await gps(14.891);
      assert.equal(await passenger.getByText('Still waiting?',{exact:true}).count(),0);
      await shot(passenger,'onboard-no-waiting-prompt.png');
      await Ride.updateOne({_id:ride._id}, {$set:{status:'completed',remainingCount:0,endedAt:new Date(), 'members.0.status':'completed'}});
    }, 'onboard-no-waiting-prompt.png');
    const second = await booking(); await refresh(passenger); await gps(14.891);
    await check('Cancel in the reminder cancels the actual pending booking at 320 pixels', async () => {
      await passenger.setViewportSize({width:320,height:740}); await trigger(14.887);
      await shot(passenger,'waiting-320.png');
      const request = passenger.waitForResponse(r => r.request().method()==='PATCH' && r.url().includes(`/pickup-requests/${second._id}/cancel`));
      await passenger.getByRole('button',{name:'Cancel',exact:true}).first().click();
      assert.equal((await request).status(),200);
      await passenger.getByText('Still waiting?',{exact:true}).waitFor({state:'hidden'});
      assert.equal((await Pickup.findById(second._id).lean()).status,'cancelled');
      await shot(passenger,'waiting-cancelled.png'); assert.deepEqual(errors,[]);
    }, 'waiting-320.png');
  } catch (e) {
    console.error(e.stack); results.push({name:e.message,status:'FAIL'}); process.exitCode=1;
    for (const [role,page] of [['passenger',passenger],['driver',driver],['admin',admin]]) if (page && !page.isClosed()) {
      await shot(page, `failure-${role}.png`);
      fs.writeFileSync(path.join(out, `failure-${role}-aria.txt`), await page.locator('body').ariaSnapshot());
    }
  } finally {
    fs.writeFileSync(path.join(out,'browser-results.json'),JSON.stringify(results,null,2));
    fs.writeFileSync(path.join(out,'page-errors.json'),JSON.stringify(errors,null,2));
    fs.writeFileSync(path.join(out,'gps-upload-results.json'),JSON.stringify(gpsUploads,null,2));
    if (browser) await browser.close(); if (lab) await lab.stop();
  }
})();
