require('dotenv').config = () => ({ parsed: {} });
Object.assign(process.env, { NODE_ENV: process.env.BOOKING_FLOW_TEST_PROFILE === 'staging' ? 'production' : 'test',
  DEPLOYMENT_ENV: process.env.BOOKING_FLOW_TEST_PROFILE === 'staging' ? 'staging' : 'test', MONGO_URI: 'mongodb://127.0.0.1/unused',
  CORS_ALLOWED_ORIGINS: 'http://127.0.0.1:8768',
  JWT_SECRET: 'isolated-driver-lifecycle-test-access-secret', JWT_REFRESH_SECRET: 'isolated-driver-lifecycle-test-refresh-secret',
  REDIS_URL: '', AUTOMATIC_GROUP_FLOW_ENABLED: 'true', AUTOMATIC_DRIVER_LIFECYCLE_ENABLED: 'true', RUN_API_JOBS: 'false',
  AUTH_EMAIL_ENABLED: 'false', FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '', GOOGLE_APPLICATION_CREDENTIALS: '',
  TOMTOM_API_KEY: '', GOOGLE_ROUTES_API_KEY: '', ASYNC_LOCATION_PROCESSING_ENABLED: 'false' });
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const mongoose = require('mongoose');
const path = require('node:path'), os = require('node:os'), crypto = require('node:crypto');
const User = require('../src/models/user'), Driver = require('../src/models/driver'), Jeep = require('../src/models/jeepney');
const Route = require('../src/models/route'), Trip = require('../src/models/tripSession'), Pickup = require('../src/models/pickupRequest');
const Ride = require('../src/models/rideSession'), Passenger = require('../src/models/passenger');
const { processAutomaticDriverLifecycle: progress } = require('../src/services/automaticDriverLifecycle.service');
const point = (lat = 14.9) => ({ type: 'Point', coordinates: [121.05, lat] });
let repl, server, origin;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { version: '8.2.6', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1, ip: '127.0.0.1' } });
  const uri = repl.getUri('driver_information_lifecycle_isolated');
  if (!/^mongodb:\/\/127\.0\.0\.1:/.test(uri)) throw Error('Loopback DB required');
  await mongoose.connect(uri);
  const app = require('../src/app');
  await Promise.all(Object.values(mongoose.models).map(m => m.init()));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  origin = `http://127.0.0.1:${server.address().port}/api/v1`;
});
after(async () => { if (server) await new Promise(r => server.close(r)); await mongoose.disconnect(); if (repl) await repl.stop(); });
async function fixture(sharedRoute) {
  const actor = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Synthetic driver', role: 'DRIVER', status: 'active' });
  const route = sharedRoute || await Route.create({ name: 'Synthetic route', code: crypto.randomUUID(), status: 'active',
    path: { type: 'LineString', coordinates: [[121.05, 14.9], [121.05, 14.93]] },
    terminal: { enabled: true, stopRef: 'Terminal', name: 'Terminal', location: point(), radiusMeters: 75 },
    stops: [{ name: 'Terminal', order: 0, location: point() }, { name: 'End', order: 1, location: point(14.93) }] });
  const driver = await Driver.create({ userId: actor._id, status: 'active', assignedRouteId: route._id });
  const jeep = await Jeep.create({ currentDriverId: driver._id, plateNumber: `PW-${crypto.randomUUID()}-8`, capacity: 6, status: 'active' });
  driver.assignedJeepneyId = jeep._id; await driver.save();
  return { actor, driver, jeep, route };
}
async function sample(f, seconds, latitude = 14.9, speed = 0, changes = {}, phase = 'progress') {
  const at = new Date(Date.UTC(2026, 9, 10, 1) + seconds * 1000); // Saturday: no coding restriction.
  return progress({ actor: f.actor, jeepneyId: f.jeep._id, now: at, phase, observation: {
    streamId: 'stream-a', sequence: seconds + 1, capturedAt: at, latitude, longitude: 121.05,
    accuracyMeters: 5, speedMetersPerSecond: speed, ...changes } });
}
async function start(f) { for (const seconds of [0, 5, 10]) await sample(f, seconds); return Trip.findOne({ driverId: f.driver._id, status: 'active' }); }

test('GPS alone starts one trip at the assigned terminal; repeated/concurrent observations cannot duplicate it', async () => {
  const f = await fixture();
  await sample(f, 0); await sample(f, 5);
  await Promise.all([sample(f, 10), sample(f, 10)]);
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id }), 1);
  const trip = await Trip.findOne({ driverId: f.driver._id });
  assert.equal(trip.flowVersion, 2); assert.equal(trip.automaticLifecycle, true);
  assert.equal(trip.status, 'active'); assert.equal(trip.terminalQueueStatus, 'loading');
});
test('missing speed, stale/poor GPS and a changed stream do not shortcut automatic start', async () => {
  const f = await fixture();
  await sample(f, 0); await sample(f, 5, 14.9, undefined, { speedMetersPerSecond: undefined });
  await sample(f, 10, 14.9, 0, { capturedAt: new Date(Date.UTC(2026, 9, 9)) });
  await sample(f, 15, 14.9, 0, { accuracyMeters: 80 });
  await sample(f, 20); await sample(f, 25, 14.9, 0, { streamId: 'stream-b' });
  await sample(f, 30, 14.9, 0, { streamId: 'stream-b' });
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id }), 0);
  await sample(f, 35, 14.9, 0, { streamId: 'stream-b' });
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id }), 1);
});
test('only the loading jeep departs automatically and advances the waiting queue', async () => {
  const first = await fixture(), second = await fixture(first.route);
  const loading = await start(first), waiting = await start(second);
  assert.equal(waiting.terminalQueueStatus, 'waiting');
  for (const seconds of [20, 25, 30]) await sample(second, seconds, 14.904, 3);
  assert.equal((await Trip.findById(waiting._id)).terminalQueueStatus, 'waiting');
  for (const seconds of [20, 25, 30]) await sample(first, seconds, 14.904, 3);
  assert.equal((await Trip.findById(loading._id)).operatingMode, 'route');
  assert.equal((await Trip.findById(waiting._id)).terminalQueueStatus, 'loading');
});
test('automatic end requires its own stopped arrival, no reservations and no occupants; manual early end remains available', async () => {
  const f = await fixture(); const trip = await start(f);
  for (const seconds of [20, 25, 30]) await sample(f, seconds, 14.904, 3);
  await Trip.updateOne({ _id: trip._id }, { resumedAt: new Date(Date.UTC(2026, 9, 10, 1)) });
  const user = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Synthetic passenger', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id });
  const booking = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: f.route._id, pickupLocation: point(), destinationLocation: point(14.93), expiresAt: new Date(Date.now() + 86400000), status: 'pending' });
  for (const seconds of [100, 105, 110]) await sample(f, seconds, 14.93, 0, {}, 'finish');
  assert.equal((await Trip.findById(trip._id)).status, 'active');
  await Pickup.updateOne({ _id: booking._id }, { status: 'cancelled' });
  await Trip.updateOne({ _id: trip._id }, { occupancyCount: 1, manualOccupancyCount: 1 });
  for (const seconds of [115, 120, 125]) await sample(f, seconds, 14.93, 0, {}, 'finish');
  assert.equal((await Trip.findById(trip._id)).status, 'active');
  await Trip.updateOne({ _id: trip._id }, { occupancyCount: 0, manualOccupancyCount: 0 });
  await sample(f, 130, 14.93, 0, {}, 'finish');
  assert.equal((await Trip.findById(trip._id)).status, 'completed');
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id }), 1);
  const fallback = await Trip.create({ flowVersion: 2, driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: f.route._id, status: 'active', occupancyCount: 1 });
  await require('../src/services/tripLifecycle.service').endTrip(fallback._id, { actor: f.actor });
  assert.equal((await Trip.findById(fallback._id)).status, 'completed');
});
test('legacy active trips are not converted or automatically departed', async () => {
  const f = await fixture(); const legacy = await Trip.create({ flowVersion: 1, driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: f.route._id, status: 'active', operatingMode: 'terminal_queue', terminalQueueStatus: 'loading' });
  for (const seconds of [0, 5, 10]) await sample(f, seconds, 14.904, 3);
  assert.equal((await Trip.findById(legacy._id)).terminalQueueStatus, 'loading');
  assert.equal((await Trip.findById(legacy._id)).flowVersion, 1);
});
test('number coding blocks automatic start without failing accepted GPS processing', async () => {
  const f = await fixture();
  await Jeep.updateOne({ _id: f.jeep._id }, { plateNumber: 'PW 001' });
  let result;
  for (const seconds of [0, 5, 10]) {
    const at = new Date(Date.UTC(2026, 9, 12, 1) + seconds * 1000); // Monday, digit 1 restricted.
    result = await progress({ actor: f.actor, jeepneyId: f.jeep._id, now: at,
      observation: { streamId: 'coding-check', sequence: seconds + 1, capturedAt: at,
        latitude: 14.9, longitude: 121.05, accuracyMeters: 5, speedMetersPerSecond: 0 } });
  }
  assert.equal(result.action, 'blocked');
  assert.equal(result.code, 'NUMBER_CODING_RESTRICTION');
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id }), 0);
  assert.ok(await require('../src/models/activityLog').exists({ action: 'automatic_trip_transition_blocked', entityId: String(f.jeep._id) }));
});
async function token(user) {
  const sid = crypto.randomUUID();
  await require('../src/models/authSession').create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  return require('../src/utils/jwt').signToken({ sub: String(user._id), sid, role: user.role });
}
async function request(user, url, options = {}) {
  const response = await fetch(origin + url, { ...options, headers: { Authorization: `Bearer ${await token(user)}`, 'Content-Type': 'application/json', 'X-App-Build': '21' } });
  return { status: response.status, body: await response.json() };
}
test('same-route drivers see redacted pickup pins; another route cannot read or modify them', async () => {
  const f = await fixture(), same = await fixture(f.route), other = await fixture();
  const trip = await Trip.create({ flowVersion: 2, driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: f.route._id, status: 'active' });
  const user = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Private identity', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id });
  const pickup = await Pickup.create({ flowVersion: 2, members: [{memberId:'member-1', organizer:true, label:'You', status:'reserved', destinationStopRef:'End', destinationLocation:point(14.93), fareSnapshot:{amount:17}}], passengerId: passenger._id, tripSessionId: trip._id, routeId: f.route._id, stopRef: 'Pickup', pickupLocation: point(), destinationLocation: point(14.93), sourceNote: 'Private note', status: 'pending', expiresAt: new Date(Date.now() + 600000) });
  const feed = await request(same.actor, `/pickup-requests/route/${f.route._id}`);
  assert.equal(feed.status, 200); assert.equal(feed.body.data.length, 1);
  assert.equal(feed.body.data[0]._id, String(pickup._id)); assert.ok(feed.body.data[0].assignedJeepneyLabel);
  assert.equal(feed.body.data[0].passengerId, undefined); assert.equal(feed.body.data[0].sourceNote, undefined);
  assert.equal((await request(other.actor, `/pickup-requests/route/${f.route._id}`)).status, 403);
  assert.equal((await request(user, `/pickup-requests/route/${f.route._id}`)).status, 403);
  assert.equal((await request(same.actor, `/pickup-requests/trip/${trip._id}`)).status, 403);
  assert.equal((await request(same.actor, `/pickup-requests/${pickup._id}/acknowledge`, { method: 'PATCH', body: '{}' })).status, 409);
  await Pickup.updateOne({ _id: pickup._id }, { status: 'completed' });
  assert.equal((await request(same.actor, `/pickup-requests/route/${f.route._id}`)).body.data.length, 0);
});
test('report buckets include Manila midnight events and stay within selected local dates', async () => {
  const f = await fixture(); const trip = await Trip.create({ driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: f.route._id });
  const user = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Synthetic passenger', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id });
  const pickup = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: f.route._id, pickupLocation: point(), destinationLocation: point(14.93), expiresAt: new Date() });
  await Ride.create({ passengerId: passenger._id, tripSessionId: trip._id, pickupRequestId: pickup._id, boardingLocation: point(), destinationLocation: point(14.93), status: 'completed', boardedAt: new Date('2026-10-01T16:05:00Z'), endedAt: new Date('2026-10-01T16:15:00Z') });
  const admin = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Synthetic admin', role: 'ADMIN' });
  const report = await request(admin, '/reports/passenger-flow?from=2026-10-01T16:00:00Z&to=2026-10-09T15:59:59.999Z');
  assert.equal(report.status, 200);
  assert.equal(report.body.data.daily[0].day, '2026-10-02');
  assert.equal(report.body.data.daily.at(-1).day, '2026-10-09');
  assert.ok(report.body.data.daily[0].boarded >= 1);
});
