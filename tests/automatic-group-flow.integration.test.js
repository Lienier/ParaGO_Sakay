require('dotenv').config = () => ({ parsed: {} });
Object.assign(process.env, {
  NODE_ENV: process.env.BOOKING_FLOW_TEST_PROFILE === 'staging' ? 'production' : 'test',
  DEPLOYMENT_ENV: process.env.BOOKING_FLOW_TEST_PROFILE === 'staging' ? 'staging' : 'test',
  MONGO_URI: 'mongodb://127.0.0.1/unused', JWT_SECRET: 'isolated-automatic-flow-access-secret-2026',
  JWT_REFRESH_SECRET: 'isolated-automatic-flow-refresh-secret-2026', REDIS_URL: '',
  CORS_ALLOWED_ORIGINS: 'http://127.0.0.1:8768', AUTH_EMAIL_ENABLED: 'false',
  FIREBASE_PROJECT_ID: '', FIREBASE_CLIENT_EMAIL: '', FIREBASE_PRIVATE_KEY: '',
  GOOGLE_APPLICATION_CREDENTIALS: '', TOMTOM_API_KEY: '', GOOGLE_ROUTES_API_KEY: '',
});
process.env.AUTOMATIC_GROUP_FLOW_ENABLED = 'true';
process.env.RUN_API_JOBS = 'false';
process.env.ASYNC_LOCATION_PROCESSING_ENABLED = 'false';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path'), os = require('node:os');
const Passenger = require('../src/models/passenger'), Driver = require('../src/models/driver');
const User = require('../src/models/user'), Trip = require('../src/models/tripSession'), Jeep = require('../src/models/jeepney');
const Pickup = require('../src/models/pickupRequest'), Ride = require('../src/models/rideSession');
const { createTripRecord, endTrip } = require('../src/services/tripLifecycle.service');
const { processRequest: autoBoard } = require('../src/services/automaticGroupBoarding.service');
const { processRide: autoUnload } = require('../src/services/memberUnloading.service');
const { quoteBooking, requireReviewedQuote } = require('../src/services/bookingV2.service');
const point = lng => ({ type: 'Point', coordinates: [lng, 14] });
let repl;
before(async () => {
  repl = await MongoMemoryReplSet.create({ binary: { version: '8.2.6', downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries') }, replSet: { count: 1 } });
  const uri = repl.getUri('automatic_group_isolated_staging');
  assert.match(uri, /^mongodb:\/\/127\.0\.0\.1:/);
  await mongoose.connect(uri);
  await Promise.all([Pickup.init(), Ride.init()]);
  await require('../src/models/codingHoliday').create({ date: require('../src/services/operatingRules.service').manilaDate(), name: 'Isolated flow tests' });
});
after(async () => { await mongoose.disconnect(); await repl?.stop(); });
const now = () => new Date();
async function fixture(destinations = [121.01, 121.02, 121.02], capacity = 6, terminal = false) {
  const user = await User.create({ email: `${new mongoose.Types.ObjectId()}@isolated.test`, fullName: 'Test organizer', role: 'PASSENGER' });
  const passenger = await Passenger.create({ userId: user._id, lastKnownLocation: point(121), lastSeenAt: now() });
  const driverUser = await User.create({ email: `${new mongoose.Types.ObjectId()}@isolated.test`, fullName: 'Test driver', role: 'DRIVER' });
  const driver = await Driver.create({ userId: driverUser._id, status: 'active' });
  const jeep = await Jeep.create({ plateNumber: `TEST-${new mongoose.Types.ObjectId()}`, capacity, lastKnownLocation: point(121), lastSeenAt: now(), latestLocationOrder: { streamId: 'stream-test', sequence: 1, capturedAt: now(), serverReceivedAt: now() } });
  const route = await require('../src/models/route').create({ name: 'Automatic test route', code: String(new mongoose.Types.ObjectId()), status: 'active', path: { type: 'LineString', coordinates: [[121, 14], [121.1, 14]] } });
  const trip = await Trip.create({ flowVersion: 2, driverId: driver._id, jeepneyId: jeep._id, routeId: route._id, status: 'active', acceptRequests: true,
    operatingMode: terminal ? 'terminal_queue' : 'route', terminalQueueStatus: terminal ? 'loading' : 'off_queue', terminalCheckedInAt: now(), terminalLoadingStartedAt: terminal ? now() : undefined });
  const members = destinations.map((lng, i) => ({ memberId: `member-${i + 1}`, organizer: i === 0, label: i ? `Passenger ${i + 1}` : 'You', destinationLocation: point(lng), destinationStopRef: `Stop ${lng}`, fareSnapshot: { amount: 17 + i }, status: 'reserved' }));
  const booking = { flowVersion: 2, members, regularTotal: members.reduce((s, m) => s + m.fareSnapshot.amount, 0),
    passengerId: passenger._id, tripSessionId: trip._id, routeId: trip.routeId, partySize: members.length, pickupType: terminal ? 'terminal' : 'roadside',
    pickupLocation: point(121), terminalLocation: terminal ? point(121) : undefined, destinationLocation: members[0].destinationLocation,
    destinationStopRef: members[0].destinationStopRef, fareSnapshot: members[0].fareSnapshot, status: 'pending', expiresAt: new Date(Date.now() + 600000) };
  const request = await createTripRecord(Pickup, booking, { accepting: true });
  return { passenger, user, driver, jeep, trip, request, booking };
}
async function boardingSample(f, at) {
  await Passenger.updateOne({ _id: f.passenger._id }, { lastSeenAt: at });
  await Jeep.updateOne({ _id: f.jeep._id }, { 'latestLocationOrder.capturedAt': at, lastSeenAt: at });
  return autoBoard({ pickupRequest: f.request, now: at });
}
async function boarded(f) {
  const at = now(); await boardingSample(f, at);
  assert.equal(await boardingSample(f, new Date(+at + 5000)), null);
  return boardingSample(f, new Date(+at + 10000));
}
async function arrive(ride, lng, start, changes = {}) {
  let result;
  for (const seconds of [0, 5, 10]) {
    const at = new Date(+start + seconds * 1000);
    result = await autoUnload({ rideId: ride._id, now: at, observation: { longitude: lng, latitude: 14,
      accuracyMeters: 10, speedMetersPerSecond: 0, streamId: 'arrival-test', sequence: +at, capturedAt: at, ...changes } });
  }
  return result;
}
test('pending group boards automatically; organizer gets off first and companions finish with driver GPS only', async () => {
  const f = await fixture(); const ride = await boarded(f);
  assert.equal(ride.boardedCount, 3); assert.equal(ride.regularTotal, 54);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 3);
  await Passenger.updateOne({ _id: f.passenger._id }, { $unset: { lastKnownLocation: 1, lastSeenAt: 1 } });
  const partial = await arrive(ride, 121.01, new Date(Date.now() + 20000));
  assert.equal(partial.remainingCount, 2); assert.equal(partial.members[0].status, 'completed');
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 2);
  const complete = await arrive(ride, 121.02, new Date(Date.now() + 40000));
  assert.equal(complete.remainingCount, 0); assert.equal(complete.status, 'completed');
  assert.equal(complete.unloadMutations.length, 2); assert.equal(complete.unloadMutations[1].count, 2);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
  const booking = await Pickup.findById(f.request._id);
  assert.ok(booking.members.every(m => m.status === 'completed' && m.completedAt));
  const flow = require('../src/services/passengerFlow.service');
  const rows = await Ride.aggregate([...flow.unloadingPipeline({ tripIds: [f.trip._id], from: new Date(0), to: new Date(Date.now() + 100000) }), { $group: { _id: '$unloadEvents.destinationStopRef', count: { $sum: '$seatCount' } } }]);
  assert.deepEqual(rows.map(r => r.count).sort(), [1, 2]);
});
test('solo v2 uses destination arrival; missing speed and drive-by never unload', async () => {
  const f = await fixture([121.01]); const ride = await boarded(f);
  assert.equal((await arrive(ride, 121.01, new Date(Date.now() + 20000), { speedMetersPerSecond: null })).remainingCount, 1);
  assert.equal((await arrive(ride, 121.01, new Date(Date.now() + 40000), { speedMetersPerSecond: 10 })).remainingCount, 1);
  assert.equal((await arrive(ride, 121.01, new Date(Date.now() + 60000))).remainingCount, 0);
});
test('concurrent repeated boarding/unloading converts and releases each seat once', async () => {
  const f = await fixture([121.01, 121.01]); const at = now(); await boardingSample(f, at);
  await Passenger.updateOne({ _id: f.passenger._id }, { lastSeenAt: new Date(+at + 10000) });
  await Jeep.updateOne({ _id: f.jeep._id }, { 'latestLocationOrder.capturedAt': new Date(+at + 10000) });
  const results = await Promise.all([autoBoard({ pickupRequest: f.request, now: new Date(+at + 10000) }), autoBoard({ pickupRequest: f.request, now: new Date(+at + 10000) })]);
  const ride = results.find(Boolean); assert.equal(await Ride.countDocuments({ pickupRequestId: f.request._id }), 1);
  await arrive(ride, 121.01, new Date(+at + 20000));
  await Promise.all([arrive(ride, 121.01, new Date(+at + 40000)), arrive(ride, 121.01, new Date(+at + 40000))]);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
  assert.equal((await Ride.findById(ride._id)).unloadMutations.length, 1);
});
test('cancelled or expired reservation cannot board; early trip ending closes only remaining members', async () => {
  const f = await fixture(); await Pickup.updateOne({ _id: f.request._id }, { status: 'cancelled' });
  assert.equal(await boarded(f), null); assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
  const active = await fixture(); const ride = await boarded(active);
  await arrive(ride, 121.01, new Date(Date.now() + 20000));
  await endTrip(active.trip._id);
  const closed = await Ride.findById(ride._id); assert.equal(closed.remainingCount, 0);
  assert.equal(closed.members.filter(m => m.completionMethod === 'trip_ended').length, 2);
});
test('terminal boarding requires current loading jeep; independent group reservations cannot exceed capacity', async () => {
  const f = await fixture([121.01, 121.02], 3, true);
  await Trip.updateOne({ _id: f.trip._id }, { terminalQueueStatus: 'waiting' });
  assert.equal(await boarded(f), null);
  await Trip.updateOne({ _id: f.trip._id }, { terminalQueueStatus: 'loading' });
  assert.equal((await boarded(f)).boardedCount, 2);
  const second = await Passenger.create({ userId: new mongoose.Types.ObjectId() });
  await assert.rejects(createTripRecord(Pickup, { ...f.booking, passengerId: second._id }, { accepting: true }), e => e.code === 'INSUFFICIENT_SEATS');
});
test('quotes use existing fare rules per destination and require a reviewed quote on price change', () => {
  const route = { _id: new mongoose.Types.ObjectId(), path: { coordinates: [[121, 14], [121.1, 14]] }, stops: [], fareConfig: { baseAmount: 17, baseDistanceKm: 4, additionalAmountPerKm: 2 } };
  const payload = { pickupLocation: point(121), members: [{ destinationLocation: point(121.01), destinationStopRef: 'Near' }, { destinationLocation: point(121.09), destinationStopRef: 'Far' }] };
  const quote = quoteBooking(route, payload); assert.ok(quote.members[1].fareSnapshot.amount > quote.members[0].fareSnapshot.amount);
  assert.equal(quote.regularTotal, quote.members.reduce((s, m) => s + m.fareSnapshot.amount, 0));
  requireReviewedQuote(quote, { quoteToken: quote.quoteToken }); route.fareConfig.baseAmount = 20;
  assert.throws(() => requireReviewedQuote(quoteBooking(route, payload), { quoteToken: quote.quoteToken }), e => e.code === 'QUOTE_REVIEW_REQUIRED');
  assert.throws(() => quoteBooking(route, { ...payload, members: [{ destinationLocation: point(120.9), destinationStopRef: 'Before' }] }));
});

async function apiFor(user) {
  const sid = require('node:crypto').randomUUID();
  await require('../src/models/authSession').create({ _id: sid, userId: user._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  const token = require('../src/utils/jwt').signToken({ sub: String(user._id), sid });
  const express = require('express'); const app = express(); app.use(express.json());
  app.use('/api/v1/pickup-requests', require('../src/routes/pickupRequests.routes'));
  app.use('/api/v1/reports', require('../src/routes/reports.routes'));
  app.use('/api/v1/drivers', require('../src/routes/drivers.routes'));
  app.use(require('../src/middlewares/error.middleware').errorHandler);
  return { app, request: require('supertest')(app), token };
}
test('authenticated quote/create requires current prices and updated app; failed notification still returns the created booking', async () => {
  const f = await fixture(); await Pickup.updateOne({ _id: f.request._id }, { status: 'cancelled' });
  await require('../src/models/route').deleteOne({ _id: f.trip.routeId });
  const route = await require('../src/models/route').create({ _id: f.trip.routeId, name: 'Isolated route', code: `TEST-${Date.now()}`, direction: 'up', status: 'active',
    path: { type: 'LineString', coordinates: [[121, 14], [121.1, 14]] }, fareConfig: { baseAmount: 17, baseDistanceKm: 4, additionalAmountPerKm: 2 } });
  const api = await apiFor(f.user);
  const payload = { routeId: String(route._id), flowVersion: 2, pickupLocation: point(121.001), pickupType: 'roadside', stopRef: 'Shared pickup', members: f.booking.members.slice(0, 2) };
  const quoted = await api.request.post('/api/v1/pickup-requests/quote').auth(api.token, { type: 'bearer' }).send(payload);
  assert.equal(quoted.status, 200, JSON.stringify(quoted.body)); payload.quoteToken = quoted.body.data.quoteToken;
  assert.equal((await api.request.post('/api/v1/pickup-requests').auth(api.token, { type: 'bearer' }).send(payload)).status, 426);
  await require('../src/models/route').updateOne({ _id: route._id }, { 'fareConfig.baseAmount': 20 });
  const outdated = await api.request.post('/api/v1/pickup-requests').auth(api.token, { type: 'bearer' }).set('X-App-Build', '21').send(payload);
  assert.equal(outdated.body.code, 'QUOTE_REVIEW_REQUIRED'); assert.equal(await Pickup.countDocuments({ passengerId: f.passenger._id }), 1);
  const reviewed = await api.request.post('/api/v1/pickup-requests/quote').auth(api.token, { type: 'bearer' }).send(payload);
  payload.quoteToken = reviewed.body.data.quoteToken;
  const Notification = require('../src/models/notification'); const originalCreate = Notification.create;
  Notification.create = async () => { throw Error('Isolated notification failure'); };
  try {
    const created = await api.request.post('/api/v1/pickup-requests').auth(api.token, { type: 'bearer' }).set('X-App-Build', '21').send(payload);
    assert.equal(created.status, 201, JSON.stringify(created.body)); assert.equal(created.body.data.flowVersion, 2);
    assert.equal(created.body.data.partySize, 2);
  } finally { Notification.create = originalCreate; }
});
test('authenticated ordered driver GPS drives boarding and destination unloading through the API', async () => {
  const f = await fixture([121.01, 121.01]);
  const streamId = require('node:crypto').randomUUID(); const initial = now();
  await Jeep.updateOne({ _id: f.jeep._id }, { 'latestLocationOrder.streamId': streamId, 'latestLocationOrder.capturedAt': new Date(+initial - 1000) });
  await Pickup.updateOne({ _id: f.request._id }, { autoBoarding: { streamId, tripId: String(f.trip._id), proximityStartedAt: new Date(+initial - 10000), lastCheckedAt: initial } });
  const driverUser = await User.findById(f.driver.userId); const api = await apiFor(driverUser);
  let sequence = 1;
  const send = async (longitude, speed = 0) => {
    const response = await api.request.post('/api/v1/drivers/me/location').auth(api.token, { type: 'bearer' }).set('X-App-Build', '21').send({
      latitude: 14, longitude, accuracyMeters: 10, speedMetersPerSecond: speed, streamId, sequence: ++sequence, capturedAt: new Date().toISOString(),
    });
    assert.equal(response.status, 200, JSON.stringify(response.body));
  };
  await send(121);
  const ride = await Ride.findOne({ pickupRequestId: f.request._id }); assert.ok(ride);
  await send(121.01, null);
  assert.equal((await Ride.findById(ride._id)).remainingCount, 2);
  await send(121.01);
  for (let i = 0; i < 2; i++) { await new Promise(resolve => setTimeout(resolve, 5100)); await send(121.01); }
  const completed = await Ride.findById(ride._id);
  assert.equal(completed.status, 'completed'); assert.equal(completed.unloadMutations.length, 1);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
});

test('old driver GPS cannot activate a new terminal journey but can continue an existing trip', async () => {
  const f = await fixture([121.01], 4, true);
  await Trip.updateOne({ _id: f.trip._id }, { status: 'scheduled', active: false, terminalQueueStatus: 'off_queue', terminalLocation: point(121), terminalRadiusMeters: 75 });
  await Driver.updateOne({ _id: f.driver._id }, { assignedJeepneyId: f.jeep._id });
  const api = await apiFor(await User.findById(f.driver.userId));
  const body = { latitude: 14, longitude: 121, accuracyMeters: 10, speedMetersPerSecond: 0, streamId: require('node:crypto').randomUUID(), sequence: 1, capturedAt: now().toISOString() };
  const blocked = await api.request.post('/api/v1/drivers/me/location').auth(api.token, { type: 'bearer' }).set('X-App-Build', '20').send(body);
  assert.equal(blocked.body.code, 'APP_UPDATE_REQUIRED'); assert.equal((await Trip.findById(f.trip._id)).status, 'scheduled');
  await Trip.updateOne({ _id: f.trip._id }, { status: 'active', flowVersion: 1, terminalQueueStatus: 'loading' });
  await require('../src/services/activeDriverContext.service').invalidateDriverActiveContext(f.driver._id);
  const existing = await api.request.post('/api/v1/drivers/me/location').auth(api.token, { type: 'bearer' }).set('X-App-Build', '20').send(body);
  assert.equal(existing.status, 200, JSON.stringify(existing.body));
});

test('manual member correction is authorized, revision checked and idempotent', async () => {
  const f = await fixture(); const ride = await boarded(f);
  const manual = { actorRole: 'driver', actorId: String(f.driver.userId), memberIds: ['member-2'], requestId: 'manual-correction', revision: 0 };
  await assert.rejects(autoUnload({ rideId: ride._id, manual: { ...manual, actorId: String(new mongoose.Types.ObjectId()) } }), e => e.statusCode === 403);
  await Promise.all([autoUnload({ rideId: ride._id, manual }), autoUnload({ rideId: ride._id, manual })]);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 2);
  await assert.rejects(autoUnload({ rideId: ride._id, manual: { ...manual, requestId: 'stale-correction' } }), e => e.code === 'RIDE_REVISION_CONFLICT');
});

test('cancel racing auto-boarding cannot leave a cancelled booking with onboard seats', async () => {
  const f = await fixture(); const at = now(); await boardingSample(f, at);
  const next = new Date(+at + 10000); await Passenger.updateOne({ _id: f.passenger._id }, { lastSeenAt: next });
  await Jeep.updateOne({ _id: f.jeep._id }, { 'latestLocationOrder.capturedAt': next });
  await Promise.allSettled([autoBoard({ pickupRequest: f.request, now: next }), Pickup.findOneAndUpdate({ _id: f.request._id, status: 'pending' }, { status: 'cancelled' })]);
  const booking = await Pickup.findById(f.request._id); const count = await Ride.countDocuments({ pickupRequestId: booking._id });
  assert.equal(booking.status === 'cancelled' ? count : 1, booking.status === 'cancelled' ? 0 : count);
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, count ? 3 : 0);
});
test('expiry and reconnect reset prevent boarding from an old proximity window', async () => {
  const f = await fixture(); const at = now(); await boardingSample(f, at);
  await Jeep.updateOne({ _id: f.jeep._id }, { 'latestLocationOrder.streamId': 'new-stream' });
  assert.equal(await boardingSample(f, new Date(+at + 10000)), null);
  await Pickup.updateOne({ _id: f.request._id }, { expiresAt: new Date(+at + 5000) });
  assert.equal(await boardingSample(f, new Date(+at + 20000)), null);
});
test('nearby destinations require separate arrivals even after the organizer gets off', async () => {
  const f = await fixture([121.01, 121.0103]); const ride = await boarded(f); const at = new Date(Date.now() + 20000);
  await arrive(ride, 121.01, at);
  assert.equal((await arrive(ride, 121.01, new Date(+at + 20000))).remainingCount, 1);
  const next = new Date(+at + 40000);
  const first = await autoUnload({ rideId: ride._id, now: next, observation: { longitude: 121.0103, latitude: 14, accuracyMeters: 10, speedMetersPerSecond: 0,
    capturedAt: next, sequence: +next, streamId: 'arrival-test' } });
  assert.equal(first.remainingCount, 1);
  assert.equal((await arrive(ride, 121.0103, new Date(+at + 45000))).remainingCount, 0);
});
test('legacy acknowledgement and group confirmation endpoints cannot alter a v2 booking', async () => {
  const f = await fixture(); const ownerApi = await apiFor(f.user); const driverApi = await apiFor(await User.findById(f.driver.userId));
  const ready = await ownerApi.request.post(`/api/v1/pickup-requests/${f.request._id}/group-ready`).auth(ownerApi.token, { type: 'bearer' }).send({});
  assert.equal(ready.body.code, 'AUTO_BOARDING_PENDING');
  assert.equal((await driverApi.request.patch(`/api/v1/pickup-requests/${f.request._id}/acknowledge`).auth(driverApi.token, { type: 'bearer' }).send({})).status, 409);
  assert.equal((await driverApi.request.post(`/api/v1/pickup-requests/${f.request._id}/group-board`).auth(driverApi.token, { type: 'bearer' }).send({ count: 3, requestId: 'obsolete-confirmation' })).status, 409);
  assert.equal((await Pickup.findById(f.request._id)).status, 'pending');
  assert.equal(await Ride.countDocuments({ pickupRequestId: f.request._id }), 0);
});

test('notification failures after boarding or unloading never undo seats or member completion', async () => {
  const f = await fixture([121.01, 121.01]);
  const Notification = require('../src/models/notification'); const originalCreate = Notification.create;
  Notification.create = async () => { throw Error('Isolated notification failure'); };
  try {
    const ride = await boarded(f);
    assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 2);
    const completed = await arrive(ride, 121.01, new Date(Date.now() + 20000));
    assert.equal(completed.remainingCount, 0);
    assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
    assert.equal(completed.unloadMutations.length, 1);
  } finally { Notification.create = originalCreate; }
});

test('inactive driver blocks boarding, records diagnosis and resets the proximity window', async () => {
  const f = await fixture(); const at = now(); await boardingSample(f, at);
  await Driver.updateOne({ _id: f.driver._id }, { status: 'inactive' });
  assert.equal(await boardingSample(f, new Date(+at + 10000)), null);
  assert.equal((await Pickup.findById(f.request._id)).autoBoarding.proximityStartedAt, undefined);
  const log = await require('../src/models/activityLog').findOne({ entityId: String(f.request._id), action: 'gps_boarding_rejected' });
  assert.equal(log.details.reason, 'ineligible_trip_or_missing_fresh_gps');
  assert.equal((await Trip.findById(f.trip._id)).occupancyCount, 0);
});

test('terminal transfer preserves member IDs, fares and deadline and resets proximity', async () => {
  const f = await fixture([121.01, 121.02], 4, true);
  const second = await fixture([121.01], 4);
  await Pickup.updateOne({ _id: second.request._id }, { status: 'cancelled' });
  await Trip.updateOne({ _id: second.trip._id }, { routeId: f.trip.routeId, operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting', terminalQueueNumber: 2 });
  const queue = require('../src/services/terminalQueue.service');
  await queue.change({ tripId: f.trip._id, actor: { role: 'DRIVER', _id: f.driver.userId }, action: 'depart', requestId: 'flow-two-depart' });
  const offer = await Pickup.findById(f.request._id);
  const moved = await queue.transfer({ requestId: offer._id, passengerId: f.passenger._id, offerId: offer.transferOfferId, accept: true });
  assert.equal(String(moved.tripSessionId), String(second.trip._id)); assert.equal(moved.flowVersion, 2);
  assert.equal(+moved.expiresAt, +f.request.expiresAt); assert.equal(moved.regularTotal, f.request.regularTotal);
  assert.deepEqual(moved.members.map(m => m.memberId), f.request.members.map(m => m.memberId));
  assert.equal(moved.autoBoarding?.proximityStartedAt, undefined);
});
