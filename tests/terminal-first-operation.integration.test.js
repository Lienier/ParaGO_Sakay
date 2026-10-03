const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const express = require('express');
const request = require('supertest');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const path = require('node:path');
const os = require('node:os');

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'terminal-first-access-test-only';
process.env.JWT_REFRESH_SECRET = 'terminal-first-refresh-test-only';
process.env.REDIS_URL = '';

const User = require('../src/models/user');
const Driver = require('../src/models/driver');
const Jeepney = require('../src/models/jeepney');
const Route = require('../src/models/route');
const Trip = require('../src/models/tripSession');
const AuthSession = require('../src/models/authSession');
const { signToken } = require('../src/utils/jwt');
const { processTerminalArrival } = require('../src/services/terminalArrival.service');
const terminalQueue = require('../src/services/terminalQueue.service');

let repl;
let app;
let user;
let driver;
let jeepney;
let route;
let token;

const point = (longitude, latitude) => ({
  type: 'Point',
  coordinates: [longitude, latitude],
});

before(async () => {
  repl = await MongoMemoryReplSet.create({
    binary: {
      version: '8.0.28',
      downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries'),
    },
    replSet: { count: 1 },
  });
  await mongoose.connect(repl.getUri('terminal-first-test'));

  user = await User.create({
    email: 'terminal-first-driver@example.test',
    fullName: 'Terminal First Driver',
    role: 'DRIVER',
    status: 'active',
  });
  driver = await Driver.create({ userId: user._id, status: 'active' });
  jeepney = await Jeepney.create({
    plateNumber: 'TERMINAL-FIRST-1',
    capacity: 20,
    currentDriverId: driver._id,
    status: 'active',
  });
  await Driver.updateOne(
    { _id: driver._id },
    { $set: { assignedJeepneyId: jeepney._id } }
  );
  route = await Route.create({
    name: 'Terminal First Route',
    code: 'TERMINAL-FIRST',
    direction: 'up',
    status: 'active',
    path: {
      type: 'LineString',
      coordinates: [
        [121, 14],
        [121.01, 14.01],
      ],
    },
    terminal: {
      enabled: true,
      name: 'Terminal First Gate',
      stopRef: 'TF-GATE',
      location: point(121, 14),
      radiusMeters: 100,
    },
    stops: [
      { name: 'Terminal First Gate', order: 0, location: point(121, 14) },
      { name: 'Terminal First End', order: 1, location: point(121.01, 14.01) },
    ],
  });

  const sid = crypto.randomUUID();
  await AuthSession.create({
    _id: sid,
    userId: user._id,
    authVersion: 0,
    expiresAt: new Date(Date.now() + 600000),
  });
  token = signToken({ sub: String(user._id), role: user.role, sid });

  app = express();
  app.use(express.json());
  app.use('/trips', require('../src/routes/trips.routes'));
  app.use('/admin', require('../src/routes/admin.routes'));
  await Promise.all(Object.values(mongoose.models).map(model => model.init()));
  app.use((error, _req, res, _next) =>
    res.status(error.statusCode || 500).json({
      message: error.message,
      code: error.code,
      action: error.action,
    })
  );
});

after(async () => {
  await mongoose.disconnect();
  if (repl) await repl.stop();
});

test('direct route starts are rejected and terminal intent waits for arrival', async () => {
  const direct = await request(app)
    .post('/trips')
    .set('Authorization', `Bearer ${token}`)
    .send({
      jeepneyId: String(jeepney._id),
      routeId: String(route._id),
      operatingMode: 'route',
      status: 'active',
    });
  assert.equal(direct.status, 409);
  assert.equal(direct.body.code, 'DIRECT_ROUTE_NOT_ALLOWED');
  assert.match(direct.body.action, /terminal/i);
  assert.match(direct.body.message, /terminal/i);

  const intent = await request(app)
    .post('/trips')
    .set('Authorization', `Bearer ${token}`)
    .send({
      jeepneyId: String(jeepney._id),
      routeId: String(route._id),
      operatingMode: 'terminal_queue',
      status: 'active',
    });
  assert.equal(intent.status, 201, intent.text);
  assert.equal(intent.body.data.status, 'scheduled');
  assert.equal(intent.body.data.terminalQueueStatus, 'off_queue');
  assert.equal(intent.body.data.driverStatus.state, 'driving_to_terminal');
  const synchronizedDriver = await Driver.findById(driver._id);
  assert.equal(synchronizedDriver.operatingMode, 'terminal_queue');
  assert.equal(synchronizedDriver.terminalQueueStatus, 'off_queue');

  const manualStart = await request(app)
    .patch(`/trips/${intent.body.data._id}/start`)
    .set('Authorization', `Bearer ${token}`)
    .send({ requestId: 'manual-terminal-start' });
  assert.equal(manualStart.status, 409);
  assert.equal(manualStart.body.code, 'TERMINAL_ARRIVAL_PENDING');
  assert.match(manualStart.body.message, /automatically|fresh GPS/i);
});

test('two fresh in-geofence fixes check in once and departure enables route operation', async () => {
  const pending = await Trip.findOne({
    driverId: driver._id,
    status: 'scheduled',
    operatingMode: 'terminal_queue',
  });
  assert.ok(pending);
  const actor = { _id: user._id, role: 'DRIVER' };
  const base = {
    actor,
    jeepneyId: jeepney._id,
    latitude: 14,
    longitude: 121,
    accuracyMeters: 8,
    streamId: crypto.randomUUID(),
  };
  assert.equal(
    await processTerminalArrival({
      actor,
      jeepneyId: jeepney._id,
      latitude: 14,
      longitude: 121,
      accuracyMeters: 5,
      capturedAt: new Date(),
    }),
    null,
    'legacy location updates do not auto-check in'
  );
  const poorAccuracy = await processTerminalArrival({
    ...base,
    accuracyMeters: 100,
    sequence: 1,
    capturedAt: new Date(),
  });
  assert.equal(poorAccuracy.detected, false);
  assert.equal(poorAccuracy.status, 'poor_accuracy');
  assert.equal(poorAccuracy.code, 'TERMINAL_GPS_POOR_ACCURACY');
  assert.equal(poorAccuracy.reason, 'GPS accuracy is too low');
  assert.equal(await Trip.findById(pending._id).then((trip) => trip.terminalArrivalFixCount), 0);
  assert.equal(await Trip.findById(pending._id).then((trip) => trip.terminalArrivalStatus), 'poor_accuracy');

  const outside = await processTerminalArrival({
    ...base,
    latitude: 14.01,
    longitude: 121.01,
    sequence: 2,
    capturedAt: new Date(),
  });
  assert.equal(outside.detected, false);
  assert.equal(outside.status, 'outside_terminal_radius');
  assert.match(outside.reason, /meters from the terminal/);
  assert.equal(await Trip.findById(pending._id).then((trip) => trip.terminalArrivalFixCount), 0);

  const first = await processTerminalArrival({
    ...base,
    sequence: 3,
    capturedAt: new Date(),
  });
  assert.equal(first.detected, false);
  assert.equal(first.fixes, 1);
  assert.equal(first.status, 'insufficient_valid_fixes');
  assert.equal(first.reason, 'Only one valid GPS fix received');
  const awaiting = await Trip.findById(pending._id);
  assert.equal(awaiting.status, 'scheduled');
  assert.equal(awaiting.terminalQueueNumber, undefined);

  const second = await processTerminalArrival({
    ...base,
    sequence: 4,
    capturedAt: new Date(),
  });
  assert.equal(second.terminalArrivalDetected, true);
  assert.equal(await Trip.countDocuments({ driverId: driver._id }), 1);
  const queued = await Trip.findById(pending._id);
  assert.equal(queued.status, 'active');
  assert.equal(queued.terminalQueueStatus, 'loading');
  const loadingDescription = await terminalQueue.describe(queued);
  assert.equal(loadingDescription.driverStatus.state, 'loading');

  const departed = await terminalQueue.change({
    tripId: pending._id,
    actor,
    action: 'depart',
    requestId: 'terminal-first-depart',
  });
  assert.equal(departed.operatingMode, 'route');
  assert.equal(departed.terminalQueueStatus, 'departed');
  const departedDescription = await terminalQueue.describe(departed);
  assert.equal(departedDescription.driverStatus.label, 'On route');
});

test('arrival survives stream restart, rejects duplicate time and serializes concurrent fixes', async () => {
  await Trip.updateMany({ driverId: driver._id }, { $set: { status: 'completed', active: false } });
  const pending = await Trip.create({ driverId: driver._id, jeepneyId: jeepney._id,
    routeId: route._id, status: 'scheduled', active: false, acceptRequests: false,
    operatingMode: 'terminal_queue', terminalQueueStatus: 'off_queue',
    terminalLocation: point(121, 14), terminalRadiusMeters: 100 });
  const base = { actor: { _id: user._id, role: 'DRIVER' }, jeepneyId: jeepney._id,
    latitude: 14, longitude: 121, accuracyMeters: 8, streamId: crypto.randomUUID() };
  const now = new Date();
  const at = seconds => new Date(now.getTime() - seconds * 1000);
  const send = overrides => processTerminalArrival({ ...base, now, ...overrides });
  assert.equal((await send({ sequence: 90, capturedAt: at(70) })).status, 'stale_location');
  assert.equal((await send({ sequence: 91, capturedAt: at(10) })).fixes, 1);
  assert.equal((await send({ sequence: 92, capturedAt: at(10) })).ignored, true);
  // Restarting the app resets its sequence, but not to an older GPS sample.
  base.streamId = crypto.randomUUID();
  assert.equal((await send({ sequence: 1, capturedAt: at(9) })).fixes, 1);
  assert.equal((await send({ sequence: 2, capturedAt: at(8), latitude: null })).status, 'invalid_coordinates');
  assert.equal((await send({ sequence: 3, capturedAt: at(7), accuracyMeters: -1 })).status, 'poor_accuracy');
  assert.equal((await send({ sequence: 4, capturedAt: at(6) })).fixes, 1);
  await Promise.all([5, 6, 7].map(sequence => send({ sequence, capturedAt: at(10 - sequence) })));
  const queued = await Trip.findById(pending._id);
  assert.equal(queued.status, 'active');
  assert.equal(queued.terminalQueueStatus, 'loading');
  const Action = require('../src/models/terminalQueueAction');
  assert.equal(await Action.countDocuments({ tripId: pending._id, action: 'check_in' }), 1);
  assert.equal(await Action.countDocuments({ tripId: pending._id, action: 'promote' }), 1);
  assert.equal(await Trip.countDocuments({ driverId: driver._id, status: 'active' }), 1);
});

test('admin assignment is authorized, deduplicated and preserves queued and departed trips', async () => {
  await Trip.updateMany({ driverId: driver._id }, { $set: { status: 'completed', active: false } });
  await Driver.updateOne({ _id: driver._id }, { $set: { assignedRouteId: route._id } });
  const admin = await User.create({ email: 'terminal-admin@example.test', fullName: 'Terminal Admin', role: 'ADMIN', status: 'active' });
  const sid = crypto.randomUUID();
  await AuthSession.create({ _id: sid, userId: admin._id, authVersion: 0, expiresAt: new Date(Date.now() + 600000) });
  const adminToken = signToken({ sub: String(admin._id), role: admin.role, sid });
  const assign = (body = {}, bearer = adminToken) => request(app).post(`/admin/drivers/${driver._id}/terminal-intent`)
    .set('Authorization', `Bearer ${bearer}`).send(body);
  assert.equal((await assign({}, token)).status, 403);
  assert.equal((await assign({ jeepneyId: String(new mongoose.Types.ObjectId()) })).status, 409);
  assert.equal((await assign({ routeId: String(new mongoose.Types.ObjectId()) })).status, 409);
  await User.updateOne({ _id: user._id }, { $set: { status: 'suspended' } });
  assert.equal((await assign()).status, 409);
  await User.updateOne({ _id: user._id }, { $set: { status: 'active' } });
  const responses = await Promise.all([assign(), assign(), assign()]);
  responses.forEach(result => assert.equal(result.status, 200, result.text));
  const id = responses[0].body.data._id;
  assert.ok(responses.every(r => r.body.data._id === id));
  assert.equal(await Trip.countDocuments({ driverId: driver._id, status: 'scheduled' }), 1);
  assert.equal(responses[0].body.data.terminalSummary.queuePosition, null);
  assert.equal(responses[0].body.data.acceptRequests, false);
  const board = await request(app).get('/admin/hybrid-dispatch').set('Authorization', `Bearer ${adminToken}`);
  assert.equal(board.status, 200, board.text);
  assert.equal(board.body.data.awaitingTerminalArrival.length, 1);
  assert.equal(board.body.data.terminalQueue.length, 0);
  assert.equal(board.body.data.awaitingTerminalArrival[0].driverId.userId.fullName, 'Terminal First Driver');
  assert.equal(board.body.data.awaitingTerminalArrival[0].terminalSummary.terminalArrival.endTerminal.name, 'Terminal First End');
  const base = { actor: { _id: user._id, role: 'DRIVER' }, jeepneyId: jeepney._id,
    latitude: 14, longitude: 121, accuracyMeters: 8, streamId: crypto.randomUUID() };
  const now = new Date();
  await processTerminalArrival({ ...base, sequence: 1, capturedAt: new Date(now.getTime() - 1000), now });
  await processTerminalArrival({ ...base, sequence: 2, capturedAt: now, now });
  const retry = await assign();
  assert.equal(retry.status, 200, retry.text);
  assert.equal(retry.body.data.terminalQueueStatus, 'loading');
  assert.equal((await Driver.findById(driver._id)).terminalQueueStatus, 'loading');
  await terminalQueue.change({ tripId: id, actor: base.actor, action: 'depart', requestId: 'admin-test-depart' });
  const departed = await assign();
  assert.equal(departed.status, 200, departed.text);
  assert.equal(departed.body.data.operatingMode, 'route');
  assert.equal((await Driver.findById(driver._id)).operatingMode, 'route');
  assert.equal(await Trip.countDocuments({ driverId: driver._id, status: { $in: ['scheduled', 'active'] } }), 1);
});
