const { test, expect } = require('../../.tools/playwright/node_modules/@playwright/test');
const crypto = require('node:crypto');
const path = require('node:path');
const { io } = require('socket.io-client');
const { createLab } = require('./fixture.cjs');
let lab, api;
const sessions = {};
const output = path.resolve(__dirname, '../..', process.env.SYSTEM_TEST_ARTIFACT_DIR || 'artifacts/playwright_system_test_2026-10-06');

async function call(method, route, actor, data, status = 200) {
  const response = await api[method]('/api/v1' + route, {
    headers: actor ? { Authorization: 'Bearer ' + (actor === 'admin' ? lab.adminToken : sessions[actor].token) } : {},
    ...(data === undefined ? {} : { data }),
  });
  const body = await response.json();
  expect(response.status(), `${method.toUpperCase()} ${route}: ${JSON.stringify(body)}`).toBe(status);
  return body;
}
async function connect(actor) {
  const socket = io(lab.apiOrigin, { transports: ['websocket'], auth: { token: sessions[actor].token }, reconnection: false });
  await new Promise((resolve, reject) => {
    socket.once('connect', resolve); socket.once('connect_error', reject);
    setTimeout(() => reject(Error('Socket connection timed out')), 10000).unref();
  });
  return socket;
}
test.beforeAll(async ({ playwright }) => {
  test.setTimeout(120000);
  lab = await createLab();
  api = await playwright.request.newContext({ baseURL: lab.apiOrigin });
  for (const actor of ['driver', 'otherDriver', 'passenger', 'otherPassenger']) {
    const login = await call('post', '/auth/login-email', null, { email: lab.accounts[actor].email, password: lab.password, role: lab.accounts[actor].role });
    sessions[actor] = login.data;
    expect(sessions[actor].token).toBeTruthy();
  }
});
test.afterAll(async () => { if (api) await api.dispose(); if (lab) await lab.stop(); });

test('API health and database readiness', async () => {
  const health = await api.get('/health'); expect(health.status()).toBe(200);
  const ready = await api.get('/ready'); expect(ready.status()).toBe(200);
  expect((await ready.json()).dependencies.mongodb).toBe('healthy');
});

test('authentication rejects wrong passwords and protected anonymous requests', async () => {
  await call('post', '/auth/login-email', null, { email: lab.accounts.passenger.email, password: 'Incorrect-Password-Only', role: 'PASSENGER' }, 401);
  await call('get', '/auth/me', null, undefined, 401);
  await call('get', '/admin/dashboard', 'passenger', undefined, 403);
});

test('registration rejects admin/driver privilege escalation', async () => {
  for (const role of ['ADMIN', 'DRIVER']) await call('post', '/auth/register-email', null, {
    email: 'invalid-role.playwright@example.test', password: lab.password, fullName: 'Rejected role', role,
    termsVersion: '2026-10-03', privacyVersion: '2026-10-03',
  }, 403);
  expect(await lab.models.User.countDocuments({ email: 'invalid-role.playwright@example.test' })).toBe(0);
});

test('passenger registration validates legal acceptance and creates a profile', async () => {
  const body = { email: 'registered.playwright@example.test', password: lab.password, fullName: 'Registered Playwright Passenger' };
  await call('post', '/auth/register-email', null, body, 400);
  await call('post', '/auth/register-email', null, { ...body, termsVersion: '2026-10-03', privacyVersion: '2026-10-03' }, 201);
  const user = await lab.models.User.findOne({ email: body.email });
  expect(await lab.models.Passenger.countDocuments({ userId: user._id })).toBe(1);
});

test('main terminal/group flow: arrival, booking, boarding, para, unload, trip end', async () => {
  const notifications = [];
  const driverSocket = await connect('driver');
  driverSocket.on('notification.created', data => notifications.push(data));
  let tripId, pickupId, rideId;
  const baseTrip = { jeepneyId: lab.ids.jeepney, routeId: lab.ids.route, status: 'active' };
  try {
    await test.step('Enforce terminal-first operation and prevent manual arrival bypass', async () => {
      const rejected = await call('post', '/trips', 'driver', { ...baseTrip, operatingMode: 'route' }, 409);
      expect(rejected.code).toBe('DIRECT_ROUTE_NOT_ALLOWED');
      const created = await call('post', '/trips', 'driver', { ...baseTrip, operatingMode: 'terminal_queue' }, 201);
      tripId = created.data._id;
      expect(created.data.status).toBe('scheduled');
      expect(created.data.terminalQueueStatus).toBe('off_queue');
      const manual = await call('patch', `/trips/${tripId}/start`, 'driver', { requestId: crypto.randomUUID() }, 409);
      expect(manual.code).toBe('TERMINAL_ARRIVAL_PENDING');
    });
    await test.step('Two ordered GPS fixes start the terminal loading trip', async () => {
      const streamId = crypto.randomUUID();
      for (const sequence of [1, 2]) {
        await call('patch', '/drivers/me/location', 'driver', { latitude: 14.9, longitude: 121.05, accuracyMeters: 5, streamId, sequence, capturedAt: new Date().toISOString() });
        if (sequence === 1) expect((await lab.models.Trip.findById(tripId)).status).toBe('scheduled');
      }
      const trip = await lab.models.Trip.findById(tripId);
      expect(trip.status).toBe('active'); expect(trip.terminalQueueStatus).toBe('loading');
    });
    await test.step('Assign a three-person terminal booking to the loading jeepney', async () => {
      const booking = await call('post', '/pickup-requests', 'passenger', {
        routeId: lab.ids.route, pickupType: 'terminal', partySize: 3,
        destinationStopRef: 'PW-END', destinationLocation: lab.point(14.93),
      }, 201);
      pickupId = booking.data._id;
      expect(booking.data.tripSessionId).toBe(tripId);
      expect(booking.data.partySize).toBe(3);
      expect(booking.data.fareSnapshot.amount).toBeGreaterThan(0);
      await expect.poll(() => notifications.some(n => n.type === 'pickup_request_created')).toBe(true);
    });
    await test.step('Reject wrong-driver acknowledgement and stale/missing organizer GPS', async () => {
      await call('patch', `/pickup-requests/${pickupId}/acknowledge`, 'otherDriver', {}, 403);
      const acknowledged = await call('patch', `/pickup-requests/${pickupId}/acknowledge`, 'driver', {});
      expect(acknowledged.data.status).toBe('acknowledged');
      const missingGps = await call('post', `/pickup-requests/${pickupId}/group-ready`, 'passenger', {}, 409);
      expect(missingGps.code).toBe('BOARDING_GPS_REQUIRED');
      await call('post', '/boarding/validate', 'passenger', { tripSessionId: tripId, pickupRequestId: pickupId, lat: 14.9, lng: 121.05 }, 409);
    });
    await test.step('Confirm two actual boarders once despite concurrent retries', async () => {
      await call('patch', '/passengers/me/location', 'passenger', { lat: 14.9, lng: 121.05, capturedAt: new Date().toISOString() });
      await call('post', `/pickup-requests/${pickupId}/group-ready`, 'passenger', {});
      await call('post', `/pickup-requests/${pickupId}/group-board`, 'otherDriver', { count: 2, requestId: crypto.randomUUID() }, 403);
      const mutation = { count: 2, requestId: crypto.randomUUID() };
      const [first, duplicate] = await Promise.all([call('post', `/pickup-requests/${pickupId}/group-board`, 'driver', mutation), call('post', `/pickup-requests/${pickupId}/group-board`, 'driver', mutation)]);
      rideId = first.data._id;
      expect(duplicate.data._id).toBe(rideId);
      expect(first.data.boardedCount).toBe(2); expect(first.data.remainingCount).toBe(2);
      expect(first.data.regularTotal).toBe(first.data.fareSnapshot.amount * 2);
      expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(2);
    });
    await test.step('Terminal departure enables route service', async () => {
      const departed = await call('patch', `/trips/${tripId}/terminal/depart`, 'driver', { requestId: crypto.randomUUID() });
      expect(departed.data.operatingMode).toBe('route');
      expect(departed.data.terminalQueueStatus).toBe('departed');
    });
    await test.step('Para notifies the driver without completing the ride', async () => {
      const body = { tripSessionId: tripId, stopRef: 'PW-END', location: lab.point(14.93) };
      await call('post', '/stop-alerts', 'otherPassenger', body, 403);
      const sent = await call('post', '/stop-alerts', 'passenger', body, 201);
      expect(sent.data.rideSessionId).toBe(rideId); expect(sent.data.status).toBe('sent');
      await expect.poll(() => notifications.some(n => n.type === 'stop_alert_created')).toBe(true);
      await call('post', '/stop-alerts', 'passenger', body, 429);
      expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(2);
      const roster = await call('get', `/ride-sessions/trip/${tripId}`, 'driver');
      expect(roster.data.find(r => r._id === rideId).status).toBe('onboard');
    });
    await test.step('Partial unload releases one seat once and rejects stale revisions', async () => {
      await call('patch', `/ride-sessions/${rideId}/complete`, 'otherDriver', { count: 1, revision: 0, requestId: crypto.randomUUID() }, 403);
      const action = { count: 1, revision: 0, requestId: crypto.randomUUID() };
      const [first, duplicate] = await Promise.all([call('patch', `/ride-sessions/${rideId}/complete`, 'driver', action), call('patch', `/ride-sessions/${rideId}/complete`, 'driver', action)]);
      expect(first.data.remainingCount).toBe(1); expect(duplicate.data.remainingCount).toBe(1);
      expect(first.data.status).toBe('onboard');
      expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(1);
      const stale = await call('patch', `/ride-sessions/${rideId}/complete`, 'driver', { count: 1, revision: 0, requestId: crypto.randomUUID() }, 409);
      expect(stale.code).toBe('RIDE_REVISION_CONFLICT');
    });
    await test.step('Final unload completes ride; trip ends with zero occupancy', async () => {
      const completed = await call('patch', `/ride-sessions/${rideId}/complete`, 'driver', { count: 1, revision: 1, requestId: crypto.randomUUID() });
      expect(completed.data.status).toBe('completed'); expect(completed.data.remainingCount).toBe(0);
      expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(0);
      await call('post', '/stop-alerts', 'passenger', { tripSessionId: tripId, stopRef: 'PW-END' }, 403);
      const ended = await call('patch', `/trips/${tripId}/end`, 'driver', { requestId: crypto.randomUUID() });
      expect(ended.data.status).toBe('completed');
      await call('patch', `/trips/${tripId}/end`, 'driver', { requestId: crypto.randomUUID() }, 409);
    });
  } finally { driverSocket.disconnect(); }
});

test('roadside solo booking, cancellation, boarding and completion', async () => {
  // Already-departed trip is a precondition; terminal departure is exercised above.
  const trip = await lab.models.Trip.create({ driverId: lab.ids.driver, jeepneyId: lab.ids.jeepney, routeId: lab.ids.route,
    status: 'active', operatingMode: 'route', acceptRequests: true, startedAt: new Date() });
  const tripId = String(trip._id);
  await lab.models.Driver.updateOne({ _id: lab.ids.driver }, { status: 'active', operatingMode: 'route' });
  let sequence = 1;
  const streamId = crypto.randomUUID();
  const location = async latitude => call('patch', '/drivers/me/location', 'driver', { latitude, longitude: 121.05,
    accuracyMeters: 5, streamId, sequence: sequence++, capturedAt: new Date().toISOString() });
  await location(14.9);
  const bookingBody = { routeId: lab.ids.route, pickupType: 'roadside', partySize: 1,
    stopRef: 'Roadside pickup', pickupLocation: lab.point(14.905), destinationStopRef: 'PW-END', destinationLocation: lab.point(14.93) };
  await call('post', '/pickup-requests', 'passenger', { ...bookingBody, destinationLocation: lab.point(14.901) }, 400);
  const tooLarge = await api.post('/api/v1/pickup-requests', { headers: { Authorization: 'Bearer ' + sessions.passenger.token }, data: { ...bookingBody, partySize: 7 } });
  expect(tooLarge.status()).toBe(409);
  const initial = (await call('post', '/pickup-requests', 'passenger', bookingBody, 201)).data;
  await call('patch', `/pickup-requests/${initial._id}/cancel`, 'otherPassenger', {}, 403);
  expect((await call('patch', `/pickup-requests/${initial._id}/cancel`, 'passenger', {})).data.status).toBe('cancelled');
  await call('post', '/boarding/validate', 'passenger', { tripSessionId: tripId, pickupRequestId: initial._id, lat: 14.905, lng: 121.05 }, 409);
  const booked = (await call('post', '/pickup-requests', 'passenger', bookingBody, 201)).data;
  expect(booked.tripSessionId).toBe(tripId);
  await call('patch', `/pickup-requests/${booked._id}/acknowledge`, 'driver', {});
  await location(14.905);
  await call('patch', '/passengers/me/location', 'passenger', { lat: 14.905, lng: 121.05, capturedAt: new Date().toISOString() });
  const payload = { tripSessionId: tripId, pickupRequestId: booked._id, lat: 14.905, lng: 121.05 };
  const ride = (await call('post', '/boarding/validate', 'passenger', payload)).data;
  expect(ride.status).toBe('onboard'); expect(ride.boardedCount).toBe(1);
  expect((await call('post', '/boarding/validate', 'passenger', payload)).data._id).toBe(ride._id);
  expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(1);
  const completed = (await call('patch', `/ride-sessions/${ride._id}/complete`, 'passenger', {})).data;
  expect(completed.status).toBe('completed');
  await call('patch', `/ride-sessions/${ride._id}/complete`, 'passenger', {});
  expect((await lab.models.Trip.findById(tripId)).occupancyCount).toBe(0);
  await call('patch', `/trips/${tripId}/end`, 'driver', { requestId: crypto.randomUUID() });
});

test('refresh token rotation rejects reused refresh tokens and logout revokes access', async () => {
  const first = (await call('post', '/auth/login-email', null, { email: lab.accounts.otherPassenger.email, password: lab.password, role: 'PASSENGER' })).data;
  const second = (await call('post', '/auth/refresh', null, { refreshToken: first.refreshToken })).data;
  expect(second.refreshToken).not.toBe(first.refreshToken);
  await call('post', '/auth/refresh', null, { refreshToken: first.refreshToken }, 401);
  await call('post', '/auth/logout', null, { refreshToken: second.refreshToken });
  const me = await api.get('/api/v1/auth/me', { headers: { Authorization: 'Bearer ' + second.token } });
  expect(me.status()).toBe(401);
});

test('admin route/vehicle creation, update and deactivation enforce roles', async () => {
  const routeBody = { name: 'Playwright CRUD Route', code: 'PW-CRUD', direction: 'up', status: 'active',
    path: { type: 'LineString', coordinates: [[121.05, 14.9], [121.05, 14.93]] },
    stops: [{ name: 'Start', order: 0, fare: 0, location: lab.point() }, { name: 'End', order: 1, fare: 20, location: lab.point(14.93) }] };
  await call('post', '/routes', 'passenger', routeBody, 403);
  const route = (await call('post', '/routes', 'admin', routeBody, 201)).data;
  await call('get', '/routes', 'admin');
  const updated = (await call('put', `/routes/${route._id}`, 'admin', { name: 'Playwright Updated Route' })).data;
  expect(updated.name).toBe('Playwright Updated Route');
  expect((await call('get', '/routes', 'passenger')).data.find(r => r._id === route._id).name).toBe(updated.name);
  const vehicle = (await call('post', '/jeepneys', 'admin', { plateNumber: 'PW 456', capacity: 12, status: 'active' }, 201)).data;
  expect((await call('put', `/jeepneys/${vehicle._id}`, 'admin', { capacity: 14 })).data.capacity).toBe(14);
  expect((await call('delete', `/jeepneys/${vehicle._id}`, 'admin')).data.status).toBe('inactive');
  expect((await call('delete', `/routes/${route._id}`, 'admin')).data.status).toBe('inactive');
});

async function enableSemantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached', timeout: 60000 });
  await placeholder.evaluate(el => el.click());
  await page.locator('flt-semantics').first().waitFor({ state: 'attached' });
}

test('admin browser: password/OTP sign-in, navigation, reload persistence and logout', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.goto(lab.webOrigin);
  await enableSemantics(page);
  await page.screenshot({ path: path.join(output, 'admin-login-desktop.png'), fullPage: true });
  await page.getByRole('textbox', { name: 'Email address' }).fill(lab.accounts.admin.email);
  const passwordField = page.getByRole('textbox', { name: 'Password', exact: true });
  await passwordField.click();
  await passwordField.pressSequentially(lab.password, { delay: 15 });
  await page.getByRole('button', { name: 'LOGIN', exact: true }).click();
  await expect(page.getByRole('textbox', { name: /code/i })).toBeVisible();
  const message = lab.mailbox.find(m => m.email === lab.accounts.admin.email && /sign-in code/.test(m.subject));
  expect(message).toBeTruthy();
  const code = message.text.match(/\b\d{6}\b/)[0];
  const codeField = page.getByRole('textbox', { name: /code/i });
  await codeField.click();
  await codeField.pressSequentially(code, { delay: 30 });
  await page.getByRole('button', { name: /verify/i }).click();
  await expect(page.getByText(/overview/i, { exact: true }).first()).toBeVisible();
  await page.screenshot({ path: path.join(output, 'admin-dashboard-desktop.png'), fullPage: true });
  await page.reload();
  await enableSemantics(page);
  await expect(page.getByText(/overview/i, { exact: true }).first()).toBeVisible();
  for (const [label, route] of [['Drivers', '/admin/drivers'], ['Routes', '/routes'],
    ['Reports', '/reports/passenger-flow'], ['Announcements', '/announcements/admin'], ['Support', '/support/admin/threads']]) {
    const loaded = page.waitForResponse(response => response.url().includes('/api/v1' + route) && response.request().method() === 'GET');
    await page.getByRole('button', { name: label, exact: true }).click();
    expect([200, 304]).toContain((await loaded).status());
    await expect(page.getByRole('button', { name: label, exact: true })).toBeVisible();
  }
  await page.screenshot({ path: path.join(output, 'admin-support-desktop.png'), fullPage: true });
  await page.getByRole('button', { name: /^Account menu/ }).click();
  await page.getByRole('menuitem', { name: 'Log out', exact: true }).click();
  const loggedOut = page.waitForResponse(response => response.url().endsWith('/api/v1/auth/logout') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Log out', exact: true }).click();
  expect((await loggedOut).status()).toBe(200);
  await expect(page.getByRole('textbox', { name: 'Email address' })).toBeVisible();
  expect(pageErrors).toEqual([]);
});

test('admin login remains usable at a narrow mobile viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(lab.webOrigin);
  await enableSemantics(page);
  await expect(page.getByRole('textbox', { name: 'Email address' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Password', exact: true })).toBeVisible();
  const dimensions = await page.evaluate(() => ({ width: innerWidth, scroll: document.documentElement.scrollWidth }));
  expect(dimensions.scroll).toBeLessThanOrEqual(dimensions.width);
  await page.screenshot({ path: path.join(output, 'admin-login-mobile.png'), fullPage: true });
});

