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

test('manual route choice updates the profile and rejects switching before cancelling', async () => {
  const f = await fixture(), other = await fixture();
  const create = routeId => request(f.actor, '/trips', { method: 'POST', body: JSON.stringify({ jeepneyId: String(f.jeep._id), routeId: String(routeId) }) });
  const chosen = await create(other.route._id);
  assert.equal(chosen.status, 201, JSON.stringify(chosen.body));
  assert.equal(chosen.body.data.routeId._id || chosen.body.data.routeId, String(other.route._id));
  assert.equal(String((await Driver.findById(f.driver._id)).assignedRouteId), String(other.route._id));
  const blocked = await create(f.route._id);
  assert.equal(blocked.status, 409);
  assert.equal(String((await Driver.findById(f.driver._id)).assignedRouteId), String(other.route._id));
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id, status: { $in: ['active', 'scheduled'] } }), 1);
});

test('a pending terminal intent can be cancelled and another route selected', async () => {
  const f = await fixture(), other = await fixture();
  const service = require('../src/services/terminalIntent.service');
  const pending = await service.createTerminalIntent({ driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: f.route._id, selectRoute: true });
  const result = await request(f.actor, `/trips/${pending._id}/terminal/cancel`, { method: 'PATCH', body: JSON.stringify({ requestId: 'cancel-pending-test' }) });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.data.status, 'cancelled');
  const profile = await Driver.findById(f.driver._id);
  assert.equal(profile.automaticJourneyPaused, true);
  assert.equal(profile.terminalQueueStatus, 'off_queue');
  assert.equal(profile.operatingMode, 'route');
  assert.equal(profile.terminalStopRef, undefined);
  const next = await service.createTerminalIntent({ driverId: f.driver._id, jeepneyId: f.jeep._id, routeId: other.route._id, selectRoute: true });
  assert.equal(next.status, 'scheduled');
  assert.equal(String((await Driver.findById(f.driver._id)).assignedRouteId), String(other.route._id));
  assert.equal((await Driver.findById(f.driver._id)).automaticJourneyPaused, false);
  assert.equal((await Trip.findById(pending._id)).status, 'cancelled');
});

test('cancelled queues cannot reappear through automatic GPS or old arrival updates', async () => {
  const f = await fixture();
  const trip = await start(f);
  await require('../src/services/terminalQueue.service').cancel({ tripId: trip._id, actor: f.actor, requestId: 'pause-requeue-test' });
  for (const seconds of [20, 25, 30]) await sample(f, seconds);
  assert.equal(await Trip.countDocuments({ driverId: f.driver._id, status: { $in: ['active', 'scheduled'] } }), 0);
  const arrived = await require('../src/services/terminalArrival.service').processTerminalArrival({ actor: f.actor, jeepneyId: f.jeep._id,
    latitude: 14.9, longitude: 121.05, accuracyMeters: 5, streamId: 'late-update', sequence: 1, capturedAt: new Date() });
  assert.equal(arrived, null);
});

test('cancelling a loading jeep promotes the next waiting jeep and repeated cancellations are safe', async () => {
  const f = await fixture(), next = await fixture(f.route);
  const loading = await start(f), waiting = await start(next);
  const queue = require('../src/services/terminalQueue.service');
  const call = () => queue.cancel({ tripId: loading._id, actor: f.actor, requestId: 'repeat-cancel-test' });
  const results = await Promise.all([call(), call(), call()]);
  assert.ok(results.every(trip => trip.status === 'cancelled'));
  assert.equal((await Trip.findById(waiting._id)).terminalQueueStatus, 'loading');
  assert.equal(await require('../src/models/terminalQueueAction').countDocuments({ tripId: loading._id, action: 'cancel_queue' }), 1);
  assert.equal((await Driver.findById(f.driver._id)).terminalQueueNumber, undefined);
});

test('only the owning driver or an admin can cancel a queue; on-road trips remain intact', async () => {
  const f = await fixture(), other = await fixture();
  const trip = await start(f);
  const call = actor => request(actor, `/trips/${trip._id}/terminal/cancel`, { method: 'PATCH', body: JSON.stringify({ requestId: 'ownership-cancel-test' }) });
  assert.equal((await call(other.actor)).status, 403);
  await require('../src/services/terminalQueue.service').change({ tripId: trip._id, actor: f.actor, action: 'depart', requestId: 'depart-before-cancel' });
  assert.equal((await call(f.actor)).status, 409);
  assert.equal((await Trip.findById(trip._id)).status, 'active');
  assert.equal((await Trip.findById(trip._id)).operatingMode, 'route');
});

test('onboard and walk-in passengers block queue cancellation without changing records', async () => {
  const f = await fixture();
  const trip = await start(f), queue = require('../src/services/terminalQueue.service');
  await Trip.updateOne({ _id: trip._id }, { $set: { occupancyCount: 2, manualOccupancyCount: 2 } });
  await assert.rejects(queue.cancel({ tripId: trip._id, actor: f.actor, requestId: 'occupied-cancel-test' }), error => error.code === 'QUEUE_HAS_PASSENGERS');
  assert.equal((await Trip.findById(trip._id)).occupancyCount, 2);
  assert.equal((await Trip.findById(trip._id)).status, 'active');
  assert.equal((await Driver.findById(f.driver._id)).automaticJourneyPaused, false);
});

test('cancellation releases legacy and v2 reservations and preserves committed success on notification outage', async () => {
  const f = await fixture(), trip = await start(f);
  const user = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Queue passenger', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id });
  const base = { passengerId: passenger._id, tripSessionId: trip._id, routeId: f.route._id, pickupType: 'terminal',
    pickupLocation: point(), destinationLocation: point(14.93), expiresAt: new Date(Date.now() + 600000) };
  const legacy = await Pickup.create({ ...base, status: 'transfer_offered' });
  const group = await Pickup.create({ ...base, flowVersion: 2, status: 'pending', members: [{ memberId: 'queue-member', organizer: true,
    label: 'You', status: 'reserved', destinationStopRef: 'End', destinationLocation: point(14.93), fareSnapshot: { amount: 17 } }] });
  const Notification = require('../src/models/notification'), original = Notification.create;
  try {
    Notification.create = async () => { throw Error('Isolated notification outage'); };
    const result = await request(f.actor, `/trips/${trip._id}/terminal/cancel`, { method: 'PATCH', body: JSON.stringify({ requestId: 'cancel-bookings-test' }) });
    assert.equal(result.status, 200, JSON.stringify(result.body));
  } finally { Notification.create = original; }
  assert.equal((await Pickup.findById(legacy._id)).status, 'cancelled');
  assert.equal((await Pickup.findById(group._id)).members[0].status, 'cancelled');
  assert.equal((await Pickup.findById(group._id)).status, 'cancelled');
  assert.equal(await require('../src/models/terminalQueueAction').countDocuments({ tripId: trip._id, action: 'cancel_queue' }), 1);
});

test('a real onboard ride blocks cancellation even if the cached occupancy is zero', async () => {
  const f = await fixture(), trip = await start(f);
  const user = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Onboard passenger', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id });
  const pickup = await Pickup.create({ passengerId: passenger._id, tripSessionId: trip._id, routeId: f.route._id,
    pickupLocation: point(), destinationLocation: point(14.93), status: 'completed', expiresAt: new Date() });
  const ride = await Ride.create({ passengerId: passenger._id, tripSessionId: trip._id, pickupRequestId: pickup._id,
    boardingLocation: point(), destinationLocation: point(14.93), status: 'onboard', remainingCount: 1 });
  const admin = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Admin', role: 'ADMIN' });
  const result = await request(admin, `/trips/${trip._id}/terminal/cancel`, { method: 'PATCH', body: JSON.stringify({ requestId: 'admin-occupied-guard' }) });
  assert.equal(result.status, 409);
  assert.equal(result.body.code, 'QUEUE_HAS_PASSENGERS');
  assert.equal((await Ride.findById(ride._id)).status, 'onboard');
  assert.equal((await Trip.findById(trip._id)).status, 'active');
});

test('concurrent route choices cannot create two live trips or change the selected route to the loser', async () => {
  const f = await fixture(), other = await fixture();
  const results = await Promise.all([f.route._id, other.route._id].map(routeId => request(f.actor, '/trips', {
    method: 'POST', body: JSON.stringify({ routeId: String(routeId), jeepneyId: String(f.jeep._id) }),
  })));
  assert.deepEqual(results.map(result => result.status).sort(), [201, 409]);
  const trips = await Trip.find({ driverId: f.driver._id, status: { $in: ['active', 'scheduled'] } });
  assert.equal(trips.length, 1);
  assert.equal(String((await Driver.findById(f.driver._id)).assignedRouteId), String(trips[0].routeId));
});

test('concurrent departure and queue cancellation never leave an active cancelled queue', async () => {
  const f = await fixture(), trip = await start(f), queue = require('../src/services/terminalQueue.service');
  const results = await Promise.allSettled([
    queue.cancel({ tripId: trip._id, actor: f.actor, requestId: 'race-cancel-queue' }),
    queue.change({ tripId: trip._id, actor: f.actor, action: 'depart', requestId: 'race-depart-queue' }),
  ]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  const saved = await Trip.findById(trip._id);
  assert.ok(saved.status === 'cancelled' || saved.operatingMode === 'route');
  assert.equal(saved.terminalQueueNumber, undefined);
});

test('admin can cancel an empty unassigned terminal entry without changing another driver', async () => {
  const f = await fixture();
  const trip = await Trip.create({ jeepneyId: f.jeep._id, routeId: f.route._id, status: 'scheduled',
    operatingMode: 'terminal_queue', terminalQueueStatus: 'off_queue', acceptRequests: false });
  const admin = await User.create({ email: `${crypto.randomUUID()}@isolated.test`, fullName: 'Queue admin', role: 'ADMIN' });
  const response = await request(admin, `/trips/${trip._id}/terminal/cancel`, { method: 'PATCH', body: JSON.stringify({ requestId: 'unassigned-cancel-test' }) });
  assert.equal(response.status, 200, JSON.stringify(response.body));
  assert.equal((await Trip.findById(trip._id)).status, 'cancelled');
  assert.equal((await Driver.findById(f.driver._id)).automaticJourneyPaused, false);
});
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
