const { test, expect } = require('../../.tools/playwright/node_modules/@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createLab } = require('./fixture.cjs');
let lab, api;
const sessions = {};
const output = path.resolve(__dirname, '../..', process.env.RELIABILITY_ARTIFACT_DIR || 'artifacts/reliability_staging_2026-10-07', 'observations');
async function observe(name, details) {
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(path.join(output, name + '.json'), JSON.stringify(details, null, 2));
  await test.info().attach(name, { body: Buffer.from(JSON.stringify(details, null, 2)), contentType: 'application/json' });
}
async function call(method, route, actor = 'passenger', data) {
  const response = await api[method]('/api/v1' + route, {
    headers: actor ? { Authorization: 'Bearer ' + (actor === 'admin' ? lab.adminToken : sessions[actor].token) } : {},
    ...(data === undefined ? {} : { data }) });
  return { status: response.status(), body: await response.json() };
}
const models = () => ({ Pickup: require('../../src/models/pickupRequest'), Ride: require('../../src/models/rideSession'),
  Alert: require('../../src/models/stopAlert'), Thread: require('../../src/models/supportThread'),
  Message: require('../../src/models/supportMessage'), Notification: require('../../src/models/notification') });
async function seedRide(count = 1) {
  const { Pickup, Ride } = models();
  const trip = await lab.models.Trip.create({ driverId: lab.ids.driver, jeepneyId: lab.ids.jeepney, routeId: lab.ids.route,
    status: 'active', startedAt: new Date(), operatingMode: 'route', terminalQueueStatus: 'departed',
    acceptRequests: true, occupancyCount: count });
  const pickup = await Pickup.create({ passengerId: lab.ids.passenger, routeId: lab.ids.route,
    tripSessionId: trip._id, status: 'completed', partySize: count, expiresAt: new Date(Date.now() + 600000),
    pickupLocation: lab.point(), destinationLocation: lab.point(14.93), destinationStopRef: 'PW-END' });
  const ride = await Ride.create({ passengerId: lab.ids.passenger, tripSessionId: trip._id, pickupRequestId: pickup._id,
    partySize: count, boardedCount: count, remainingCount: count, status: 'onboard', canSendStopAlert: true,
    boardedAt: new Date(), boardingLocation: lab.point(), destinationLocation: lab.point(14.93), destinationStopRef: 'PW-END' });
  return { trip, pickup, ride };
}
function booking() { return { routeId: lab.ids.route, partySize: 1, pickupType: 'roadside', stopRef: 'PW-START',
  pickupLocation: lab.point(), destinationStopRef: 'PW-END', destinationLocation: lab.point(14.93) }; }
function para(trip) { return { tripSessionId: String(trip._id), stopRef: 'PW-END', location: lab.point(14.93) }; }
test.beforeAll(async ({ playwright }) => {
  test.setTimeout(120000); lab = await createLab();
  api = await playwright.request.newContext({ baseURL: lab.apiOrigin });
  for (const actor of ['passenger', 'otherPassenger', 'driver', 'otherDriver']) {
    const login = await call('post', '/auth/login-email', null, { email: lab.accounts[actor].email, password: lab.password, role: lab.accounts[actor].role });
    expect(login.status).toBe(200); sessions[actor] = login.body.data;
  }
});
test.afterAll(async () => { if (api) await api.dispose(); if (lab) await lab.stop(); });
test.beforeEach(async () => {
  await Promise.all([...Object.values(models()), lab.models.Trip].map(m => m.deleteMany({})));
  await lab.models.Passenger.updateOne({ _id: lab.ids.passenger }, { $unset: { lastKnownLocation: 1, lastSeenAt: 1 } });
  await lab.models.Jeepney.updateOne({ _id: lab.ids.jeepney }, { $set: { status: 'active', capacity: 6, lastKnownLocation: lab.point(), lastSeenAt: new Date() } });
  await lab.models.Route.updateOne({ _id: lab.ids.route }, { $set: { status: 'active' } });
  await lab.models.Driver.updateOne({ _id: lab.ids.driver }, { $set: { status: 'active', operatingMode: 'route' } });
});

for (const [name, coordinates] of [['null', { lat: null, lng: null }], ['empty-string', { lat: '', lng: '' }],
  ['boolean', { lat: false, lng: false }], ['numeric-string', { lat: '14.9', lng: '121.05' }]]) {
  test(`A01 passenger GPS rejects ${name} coordinates`, async () => {
    const result = await call('patch', '/passengers/me/location', 'passenger', { ...coordinates, capturedAt: new Date().toISOString() });
    const stored = await lab.models.Passenger.findById(lab.ids.passenger).lean();
    await observe('A01-' + name, { input: coordinates, result, savedLocation: stored.lastKnownLocation });
    expect(result.status).toBe(400);
  });
}
test('A02 invalid GPS must not automatically complete an onboard ride', async () => {
  const { trip, ride } = await seedRide(); const responses = [];
  for (let i = 0; i < 3; i++) responses.push(await call('patch', '/passengers/me/location', 'passenger', { lat: null, lng: null, capturedAt: new Date().toISOString() }));
  const saved = await models().Ride.findById(ride._id).lean();
  await observe('A02', { responses, ride: saved, occupancy: (await lab.models.Trip.findById(trip._id)).occupancyCount });
  expect(saved.status).toBe('onboard');
});
test('A03 simultaneous para requests respect the cooldown', async () => {
  const { trip } = await seedRide();
  const responses = await Promise.all(Array.from({ length: 4 }, () => call('post', '/stop-alerts', 'passenger', para(trip))));
  const alerts = await models().Alert.countDocuments({ tripSessionId: trip._id });
  await observe('A03', { responses, alerts });
  expect(responses.filter(r => r.status === 201)).toHaveLength(1);
  expect(alerts).toBe(1);
});
test('A04 notification failure must not report a committed para as failed', async () => {
  const { trip } = await seedRide(); const Notification = models().Notification;
  const original = Notification.create; let result;
  try { Notification.create = async () => { throw Error('Injected audit notification-write failure'); };
    result = await call('post', '/stop-alerts', 'passenger', para(trip));
  } finally { Notification.create = original; }
  const retry = await call('post', '/stop-alerts', 'passenger', para(trip));
  await observe('A04', { result, retry, committedAlerts: await models().Alert.countDocuments({ tripSessionId: trip._id }),
    notifications: await Notification.countDocuments({ type: 'stop_alert_created' }) });
  expect([201, 202]).toContain(result.status);
});
test('A05 rejected empty support message leaves no orphan thread', async () => {
  const result = await call('post', '/support/threads', 'passenger', { category: 'general_help', message: '   ' });
  const threads = await models().Thread.countDocuments(); const messages = await models().Message.countDocuments();
  await observe('A05', { result, threads, messages });
  expect(result.status).toBe(400); expect(threads).toBe(0);
});
test('A06 support lifecycle enforces ownership, close and reopen', async () => {
  const created = await call('post', '/support/threads', 'passenger', { message: 'Audit general help' });
  expect(created.status).toBe(201); const id = created.body.data.thread._id;
  expect((await call('get', `/support/threads/${id}/messages`, 'otherPassenger')).status).toBe(403);
  expect((await call('post', `/support/threads/${id}/messages`, 'otherDriver', { body: 'Unauthorized' })).status).toBe(403);
  expect((await call('post', `/support/threads/${id}/messages`, 'admin', { body: 'Admin reply' })).status).toBe(201);
  expect((await call('patch', `/support/threads/${id}/read`)).status).toBe(200);
  expect((await call('patch', `/support/threads/${id}/close`, 'passenger', {})).status).toBe(200);
  expect((await call('post', `/support/threads/${id}/messages`, 'passenger', { body: 'Closed reply' })).status).toBe(409);
  expect((await call('patch', `/support/threads/${id}/reopen`, 'passenger', {})).status).toBe(200);
  expect((await call('post', `/support/threads/${id}/messages`, 'passenger', { body: 'Reopened reply' })).status).toBe(201);
});
test('A07 simultaneous support messages preserve unread counts', async () => {
  const created = await call('post', '/support/threads', 'passenger', { message: 'Start' });
  const id = created.body.data.thread._id;
  const responses = await Promise.all(Array.from({ length: 5 }, (_, i) => call('post', `/support/threads/${id}/messages`, 'passenger', { body: 'Concurrent message ' + i })));
  const saved = await models().Thread.findById(id).lean(); const messages = await models().Message.countDocuments({ threadId: id });
  await observe('A07', { statuses: responses.map(r => r.status), messages, unreadAdminCount: saved.unreadAdminCount });
  expect(responses.every(r => r.status === 201)).toBe(true); expect(messages).toBe(6); expect(saved.unreadAdminCount).toBe(6);
});
test('A08 support notification outage must not produce retry duplicates', async () => {
  const Notification = models().Notification; const original = Notification.create; let result;
  const payload = { subject: 'Notification outage', message: 'Save this support request once' };
  try { Notification.create = async () => { throw Error('Injected audit notification-write failure'); };
    result = await call('post', '/support/threads', 'passenger', payload);
  } finally { Notification.create = original; }
  // A successful 201 must not provoke a client retry. Reposting a new support
  // request without an idempotency key intentionally creates a new thread.
  const retry = result.status >= 500 ? await call('post', '/support/threads', 'passenger', payload) : null;
  await observe('A08', { result, retryStatus: retry?.status, threads: await models().Thread.countDocuments(), messages: await models().Message.countDocuments() });
  expect([201, 202]).toContain(result.status);
  expect(await models().Thread.countDocuments()).toBe(1);
});
test('A09 active vehicle capacity cannot be reduced below onboard count', async () => {
  const { trip } = await seedRide(4);
  const result = await call('put', `/jeepneys/${lab.ids.jeepney}`, 'admin', { capacity: 1 });
  await observe('A09', { result, occupancy: (await lab.models.Trip.findById(trip._id)).occupancyCount,
    capacity: (await lab.models.Jeepney.findById(lab.ids.jeepney)).capacity });
  expect(result.status).toBe(409);
});
test('A10 passenger stale/future GPS is rejected and duplicates do not move location', async () => {
  const at = new Date();
  expect((await call('patch', '/passengers/me/location', 'passenger', { lat: 14.9, lng: 121.05, capturedAt: at.toISOString() })).status).toBe(200);
  const duplicate = await call('patch', '/passengers/me/location', 'passenger', { lat: 14.91, lng: 121.05, capturedAt: at.toISOString() });
  expect(duplicate.body.data.accepted).toBe(false);
  for (const capturedAt of [new Date(Date.now() - 60000), new Date(Date.now() + 60000)])
    expect((await call('patch', '/passengers/me/location', 'passenger', { lat: 14.9, lng: 121.05, capturedAt: capturedAt.toISOString() })).status).toBe(409);
  expect((await lab.models.Passenger.findById(lab.ids.passenger)).lastKnownLocation.coordinates).toEqual([121.05, 14.9]);
});
test('A11 unavailable or inactive transport cannot receive a booking', async () => {
  expect((await call('post', '/pickup-requests', 'passenger', booking())).status).toBe(409);
  await seedRide(); await models().Ride.deleteMany({}); await models().Pickup.deleteMany({});
  for (const [model, id, fields] of [[lab.models.Jeepney, lab.ids.jeepney, { status: 'maintenance' }],
    [lab.models.Driver, lab.ids.driver, { status: 'inactive' }], [lab.models.Route, lab.ids.route, { status: 'inactive' }]]) {
    await model.updateOne({ _id: id }, { $set: fields });
    const result = await call('post', '/pickup-requests', 'passenger', booking());
    await observe('A11-' + model.modelName, { state: fields, result });
    expect([400, 403, 404, 409]).toContain(result.status);
    await model.updateOne({ _id: id }, { $set: { status: 'active' } });
  }
});
test('A12 expired bookings cannot be acknowledged or boarded', async () => {
  const { trip, pickup } = await seedRide(); await models().Ride.deleteMany({});
  await models().Pickup.updateOne({ _id: pickup._id }, { $set: { status: 'pending', expiresAt: new Date(Date.now() - 1000) } });
  const ack = await call('patch', `/pickup-requests/${pickup._id}/acknowledge`, 'driver', {});
  expect([404, 409]).toContain(ack.status);
  const board = await call('post', '/boarding/validate', 'passenger', { tripSessionId: String(trip._id), pickupRequestId: String(pickup._id), lat: 14.9, lng: 121.05 });
  expect([404, 409]).toContain(board.status); expect(await models().Ride.countDocuments()).toBe(0);
});
test('A13 malformed resource IDs return client errors rather than server errors', async () => {
  const routes = [['patch', '/pickup-requests/bad/acknowledge', 'driver'], ['patch', '/pickup-requests/bad/cancel', 'passenger'],
    ['patch', '/trips/bad/end', 'driver'], ['patch', '/ride-sessions/bad/complete', 'passenger'],
    ['patch', '/stop-alerts/bad/acknowledge', 'driver'], ['get', '/support/threads/bad/messages', 'passenger'],
    ['put', '/jeepneys/bad', 'admin'], ['put', '/routes/bad', 'admin'], ['patch', '/users/bad/status', 'admin']];
  const results = [];
  for (const [method, route, actor] of routes) { const result = await call(method, route, actor, method === 'get' ? undefined : { status: 'active' });
    results.push({ method, route, status: result.status }); expect(result.status).toBe(400); }
  await observe('A13', results);
});
test('A14 other users cannot read or modify trip, ride, para and notifications', async () => {
  const { trip, ride } = await seedRide(); const alert = await call('post', '/stop-alerts', 'passenger', para(trip)); expect(alert.status).toBe(201);
  for (const route of [`/ride-sessions/trip/${trip._id}`, `/stop-alerts/trip/${trip._id}`, `/notifications/para/${alert.body.data._id}`])
    expect((await call('get', route, 'otherDriver')).status).toBe(403);
  expect((await call('patch', `/ride-sessions/${ride._id}/complete`, 'otherPassenger', {})).status).toBe(403);
  const notification = await models().Notification.findOne({ userId: lab.accounts.driver._id });
  expect((await call('patch', `/notifications/${notification._id}/read`, 'passenger', {})).status).toBe(403);
});
test('A15 driver push tokens cannot be claimed by other accounts', async () => {
  const token = 'AuditPushToken_' + crypto.randomUUID();
  expect((await call('put', '/notifications/push-device', 'passenger', { token })).status).toBe(403);
  expect((await call('put', '/notifications/push-device', 'driver', { token })).status).toBe(200);
  expect((await call('put', '/notifications/push-device', 'otherDriver', { token })).status).toBe(409);
  expect((await call('delete', '/notifications/push-device', 'driver')).status).toBe(200);
});
test('A16 blank/malformed request bodies do not cause internal server errors', async () => {
  const routes = [['post', '/pickup-requests', 'passenger'], ['post', '/boarding/validate', 'passenger'],
    ['post', '/stop-alerts', 'passenger'], ['post', '/routes', 'admin'], ['post', '/jeepneys', 'admin'],
    ['put', '/passengers/me', 'passenger'], ['post', '/support/threads', 'passenger']];
  for (const [method, route, actor] of routes) { const result = await call(method, route, actor, {});
    expect(result.status, route + ': ' + JSON.stringify(result.body)).toBeLessThan(500);
    expect(result.status).toBeGreaterThanOrEqual(400); }
});
test('A17 driver general support before starting a trip is usable', async () => {
  const result = await call('post', '/support/threads', 'driver', { category: 'general_help', message: 'Cannot start trip; need admin help with assignment' });
  await observe('A17', result); expect(result.status).toBe(201);
});
test('A18 ending a trip closes rides, reservations and para together', async () => {
  const { trip, ride } = await seedRide(3);
  expect((await call('post', '/stop-alerts', 'passenger', para(trip))).status).toBe(201);
  expect((await call('patch', `/trips/${trip._id}/end`, 'driver', { requestId: crypto.randomUUID() })).status).toBe(200);
  const saved = await models().Ride.findById(ride._id); expect(saved.status).toBe('completed'); expect(saved.remainingCount).toBe(0);
  expect((await lab.models.Trip.findById(trip._id)).occupancyCount).toBe(0);
  expect(await models().Alert.countDocuments({ tripSessionId: trip._id, status: { $ne: 'dismissed' } })).toBe(0);
  expect((await call('post', '/stop-alerts', 'passenger', para(trip))).status).toBe(403);
});

test('A19 notification failure must not leave an apparently failed active booking', async () => {
  const { trip, ride, pickup } = await seedRide();
  await models().Ride.deleteOne({ _id: ride._id }); await models().Pickup.deleteOne({ _id: pickup._id });
  await lab.models.Trip.updateOne({ _id: trip._id }, { $set: { occupancyCount: 0 } });
  const Notification = models().Notification; const original = Notification.create; let result;
  try { Notification.create = async () => { throw Error('Injected audit notification-write failure'); };
    result = await call('post', '/pickup-requests', 'passenger', booking());
  } finally { Notification.create = original; }
  const retry = await call('post', '/pickup-requests', 'passenger', booking());
  await observe('A19', { result, retry, committedRequests: await models().Pickup.countDocuments({ status: 'pending' }),
    notifications: await Notification.countDocuments({ type: 'pickup_request_created' }) });
  expect([201, 202]).toContain(result.status);
});
test('A20 admin route editing preserves an onboard passenger destination', async () => {
  const { trip } = await seedRide();
  const result = await call('put', `/routes/${lab.ids.route}`, 'admin', { path: { type: 'LineString', coordinates: [[121.06, 14.9], [121.06, 14.93]] } });
  if (result.status === 409) return; // Blocking unsafe live edits is also acceptable.
  expect(result.status).toBe(200);
  const alert = await call('post', '/stop-alerts', 'passenger', para(trip));
  await observe('A20', { updateStatus: result.status, alert, tripSnapshot: (await lab.models.Trip.findById(trip._id)).routePathSnapshot,
    bookedDestination: [121.05, 14.93], newPath: result.body.data.path });
  expect(alert.status).toBe(201);
});
test('A21 daily reports put early morning rides on their Manila operating day', async () => {
  const { ride } = await seedRide();
  await models().Ride.updateOne({ _id: ride._id }, { $set: { boardedAt: new Date('2026-10-05T17:00:00Z') } });
  const report = await call('get', '/reports/passenger-flow?from=2026-10-05T16:00:00Z&to=2026-10-06T15:59:59Z', 'admin');
  expect(report.status).toBe(200);
  await observe('A21', { manilaBoardingTime: '2026-10-06 01:00:00 +08:00', report: report.body.data });
  expect(report.body.data.daily.find(day => day.day === '2026-10-06').boarded).toBe(1);
});
test('A22 expired booking history stays available while its linked ride is onboard', async () => {
  const { ride, pickup } = await seedRide();
  const mongoose = require('mongoose');
  expect(mongoose.connection.host).toBe('127.0.0.1');
  // Accelerate only this temporary MongoDB process to observe actual TTL behavior.
  await mongoose.connection.db.admin().command({ setParameter: 1, ttlMonitorSleepSecs: 1 });
  await models().Pickup.updateOne({ _id: pickup._id }, { $set: { expiresAt: new Date(Date.now() - 60000) } });
  const indexes = await models().Pickup.collection.indexes();
  expect(indexes.filter(i => i.key.expiresAt === 1 && i.expireAfterSeconds != null)).toHaveLength(0);
  await new Promise(resolve => setTimeout(resolve, 2500));
  expect(await models().Pickup.countDocuments({ _id: pickup._id })).toBe(1);
  const saved = await models().Ride.findById(ride._id).lean();
  const context = await call('post', '/support/threads', 'passenger', { message: 'Historical pickup concern', pickupRequestId: String(pickup._id) });
  await observe('A22', { retainedPickup: String(pickup._id), rideStatus: saved.status, linkedPickup: String(saved.pickupRequestId), supportResult: context });
  expect(saved.status).toBe('onboard'); expect(context.status).toBe(201);
});
test('A23 expired reservations release the passenger waiting state without deleting history', async () => {
  const { trip } = await seedRide();
  await models().Ride.deleteMany({}); await models().Pickup.deleteMany({});
  const pickup = await models().Pickup.create({ passengerId: lab.ids.passenger,
    routeId: lab.ids.route, tripSessionId: trip._id, status: 'pending', partySize: 1,
    expiresAt: new Date(Date.now() - 60000), pickupLocation: lab.point(),
    destinationLocation: lab.point(14.93), destinationStopRef: 'PW-END' });
  const mine = await call('get', '/pickup-requests/mine');
  expect(mine.status).toBe(200);
  expect(mine.body.data.find(item => item._id === String(pickup._id)).status).toBe('expired');
  expect(await models().Pickup.countDocuments({ _id: pickup._id })).toBe(1);
});
