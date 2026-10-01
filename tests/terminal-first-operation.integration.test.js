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
  app.use((error, _req, res, _next) =>
    res.status(error.statusCode || 500).json({
      message: error.message,
      code: error.code,
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

  const manualStart = await request(app)
    .patch(`/trips/${intent.body.data._id}/start`)
    .set('Authorization', `Bearer ${token}`)
    .send({ requestId: 'manual-terminal-start' });
  assert.equal(manualStart.status, 409);
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
  assert.equal(await Trip.findById(pending._id).then((trip) => trip.terminalArrivalFixCount), 0);

  const outside = await processTerminalArrival({
    ...base,
    latitude: 14.01,
    longitude: 121.01,
    sequence: 2,
    capturedAt: new Date(),
  });
  assert.equal(outside.detected, false);
  assert.equal(await Trip.findById(pending._id).then((trip) => trip.terminalArrivalFixCount), 0);

  const first = await processTerminalArrival({
    ...base,
    sequence: 3,
    capturedAt: new Date(),
  });
  assert.equal(first.detected, false);
  assert.equal(first.fixes, 1);

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

  const departed = await terminalQueue.change({
    tripId: pending._id,
    actor,
    action: 'depart',
    requestId: 'terminal-first-depart',
  });
  assert.equal(departed.operatingMode, 'route');
  assert.equal(departed.terminalQueueStatus, 'departed');
});
