const assert = require('node:assert/strict');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const {
  after,
  afterEach,
  before,
  beforeEach,
  test,
} = require('node:test');

const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const request = require('supertest');
const { io: createSocketClient } = require('socket.io-client');

const app = require('../src/app');
const { mongoUri: configuredMongoUri } = require('../src/config/env');
const Driver = require('../src/models/driver');
const Jeepney = require('../src/models/jeepney');
const Passenger = require('../src/models/passenger');
const PickupRequest = require('../src/models/pickupRequest');
const RideSession = require('../src/models/rideSession');
const Route = require('../src/models/route');
const StopAlert = require('../src/models/stopAlert');
const TripSession = require('../src/models/tripSession');
const User = require('../src/models/user');
const {
  attachSocketServer,
  emitJeepneyLocationUpdate,
  emitToRoute,
  emitToTrip,
  getSocketServer,
  getRouteLocationBatcher,
  maxCustomRoomsPerSocket,
  maxSubscriptionEventsPerWindow,
} = require('../src/realtime/socketServer');
const {
  RouteLocationBatcher,
} = require('../src/realtime/routeLocationBatcher');
const {
  clearDriverLocationOrderingState,
  reserveDriverLocationOrder,
} = require('../src/services/driverLocationOrdering.service');
const { signToken } = require('../src/utils/jwt');

let memoryServer;
let httpServer;
let baseUrl;
let memoryUri;
const clients = new Set();

const point = (longitude, latitude) => ({
  type: 'Point',
  coordinates: [longitude, latitude],
});

const routePath = [
  [120.9816, 14.5995],
  [120.9874, 14.6038],
  [120.9938, 14.6091],
  [121.0001, 14.6142],
];

const tokenFor = (user) => signToken({ sub: user._id.toString() });
const auth = (token) => ({ Authorization: `Bearer ${token}` });
const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

const seedCoreFixture = async () => {
  const [adminUser, driverUser, otherDriverUser, passengerUser, otherPassengerUser] =
    await User.create([
      {
        email: 'phase1-admin@example.test',
        fullName: 'Phase 1 Admin',
        role: 'ADMIN',
        status: 'active',
      },
      {
        email: 'phase1-driver@example.test',
        fullName: 'Phase 1 Driver',
        role: 'DRIVER',
        status: 'active',
      },
      {
        email: 'phase1-other-driver@example.test',
        fullName: 'Phase 1 Other Driver',
        role: 'DRIVER',
        status: 'active',
      },
      {
        email: 'phase1-passenger@example.test',
        fullName: 'Phase 1 Passenger',
        role: 'PASSENGER',
        status: 'active',
      },
      {
        email: 'phase1-other-passenger@example.test',
        fullName: 'Phase 1 Other Passenger',
        role: 'PASSENGER',
        status: 'active',
      },
    ]);

  const [route, otherRoute] = await Route.create([
    {
      name: 'Phase 1 Route',
      code: 'PHASE1-A',
      direction: 'up',
      status: 'active',
      path: { type: 'LineString', coordinates: routePath },
      stops: routePath.map(([longitude, latitude], index) => ({
        name: `Phase 1 Stop ${index + 1}`,
        code: `P1-${index + 1}`,
        order: index + 1,
        location: point(longitude, latitude),
      })),
    },
    {
      name: 'Other Phase 1 Route',
      code: 'PHASE1-B',
      direction: 'up',
      status: 'active',
      path: {
        type: 'LineString',
        coordinates: routePath.map(([longitude, latitude]) => [
          longitude + 0.1,
          latitude + 0.1,
        ]),
      },
    },
  ]);

  const [jeepney, otherJeepney] = await Jeepney.create([
    {
      plateNumber: 'P1-0001',
      capacity: 20,
      status: 'active',
      lastKnownLocation: point(routePath[0][0], routePath[0][1]),
      lastSeenAt: new Date(),
    },
    {
      plateNumber: 'P1-0002',
      capacity: 20,
      status: 'active',
      lastKnownLocation: point(routePath[1][0], routePath[1][1]),
      lastSeenAt: new Date(),
    },
  ]);

  const [driver, otherDriver] = await Driver.create([
    {
      userId: driverUser._id,
      assignedJeepneyId: jeepney._id,
      assignedRouteId: route._id,
      status: 'active',
    },
    {
      userId: otherDriverUser._id,
      assignedJeepneyId: otherJeepney._id,
      assignedRouteId: otherRoute._id,
      status: 'active',
    },
  ]);
  jeepney.currentDriverId = driver._id;
  otherJeepney.currentDriverId = otherDriver._id;
  await Promise.all([jeepney.save(), otherJeepney.save()]);

  const [passenger, otherPassenger] = await Passenger.create([
    {
      userId: passengerUser._id,
      defaultRouteId: route._id,
      lastKnownLocation: point(routePath[0][0], routePath[0][1]),
      lastSeenAt: new Date(),
    },
    {
      userId: otherPassengerUser._id,
      defaultRouteId: otherRoute._id,
      lastKnownLocation: point(routePath[1][0], routePath[1][1]),
      lastSeenAt: new Date(),
    },
  ]);

  const [trip, otherTrip] = await TripSession.create([
    {
      jeepneyId: jeepney._id,
      driverId: driver._id,
      routeId: route._id,
      routePathSnapshot: { type: 'LineString', coordinates: routePath },
      status: 'active',
      startedAt: new Date(),
      active: true,
      occupancyCount: 0,
    },
    {
      jeepneyId: otherJeepney._id,
      driverId: otherDriver._id,
      routeId: otherRoute._id,
      routePathSnapshot: {
        type: 'LineString',
        coordinates: routePath.map(([longitude, latitude]) => [
          longitude + 0.1,
          latitude + 0.1,
        ]),
      },
      status: 'active',
      startedAt: new Date(),
      active: true,
      occupancyCount: 0,
    },
  ]);

  return {
    users: {
      admin: adminUser,
      driver: driverUser,
      otherDriver: otherDriverUser,
      passenger: passengerUser,
      otherPassenger: otherPassengerUser,
    },
    tokens: {
      admin: tokenFor(adminUser),
      driver: tokenFor(driverUser),
      otherDriver: tokenFor(otherDriverUser),
      passenger: tokenFor(passengerUser),
      otherPassenger: tokenFor(otherPassengerUser),
    },
    route,
    otherRoute,
    jeepney,
    otherJeepney,
    driver,
    otherDriver,
    passenger,
    otherPassenger,
    trip,
    otherTrip,
  };
};

const createPickupRequest = async ({
  fixture,
  passenger = fixture.passenger,
  trip = fixture.trip,
  status = 'acknowledged',
  autoBoarding,
} = {}) =>
  PickupRequest.create({
    passengerId: passenger._id,
    tripSessionId: trip._id,
    routeId: fixture.route._id,
    stopRef: 'P1-1',
    pickupLocation: point(routePath[0][0], routePath[0][1]),
    destinationStopRef: 'P1-4',
    destinationLocation: point(routePath[3][0], routePath[3][1]),
    pickupType: 'roadside',
    status,
    acknowledgedBy: status === 'acknowledged' ? fixture.driver._id : undefined,
    acknowledgedAt: status === 'acknowledged' ? new Date() : undefined,
    autoBoarding,
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
  });

const connectClient = (
  token,
  { queryToken = false, headerToken = false } = {},
) =>
  new Promise((resolve, reject) => {
    const socket = createSocketClient(baseUrl, {
      path: '/socket.io',
      transports: ['websocket'],
      forceNew: true,
      reconnection: false,
      timeout: 3000,
      ...(queryToken
        ? { query: { token } }
        : headerToken
          ? { extraHeaders: { Authorization: `Bearer ${token}` } }
          : { auth: { token } }),
    });
    clients.add(socket);
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error('Socket connection timed out'));
    }, 4000);
    socket.once('connect', () => {
      clearTimeout(timer);
      resolve(socket);
    });
    socket.once('connect_error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });

const emitWithAck = (socket, eventName, resourceId) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for ${eventName} ack`)),
      3000,
    );
    socket.emit(eventName, resourceId, (payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });

const waitForEvent = (socket, eventName, action) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for ${eventName}`)),
      3000,
    );
    socket.once(eventName, (payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
    Promise.resolve(action()).catch((error) => {
      clearTimeout(timer);
      reject(error);
    });
  });

const expectNoEvent = (socket, eventName, action, timeoutMs = 200) =>
  new Promise((resolve, reject) => {
    const onEvent = (payload) => {
      clearTimeout(timer);
      reject(
        new Error(
          `Unexpected ${eventName}: ${JSON.stringify(payload)}`,
        ),
      );
    };
    const timer = setTimeout(() => {
      socket.off(eventName, onEvent);
      resolve();
    }, timeoutMs);
    socket.once(eventName, onEvent);
    Promise.resolve(action()).catch((error) => {
      clearTimeout(timer);
      socket.off(eventName, onEvent);
      reject(error);
    });
  });

before(async () => {
  memoryServer = await MongoMemoryReplSet.create({
    binary: {
      downloadDir: path.join(os.tmpdir(), 'parago-mongodb-binaries'),
      version: '8.0.28',
    },
    replSet: {
      count: 1,
      storageEngine: 'wiredTiger',
    },
  });
  memoryUri = memoryServer.getUri('parago-phase1-characterization');
  assert.notEqual(memoryUri, configuredMongoUri);
  assert.match(memoryUri, /^mongodb:\/\/127\.0\.0\.1:/);
  await mongoose.connect(memoryUri);

  httpServer = http.createServer(app);
  attachSocketServer(httpServer, { corsOrigins: [] });
  await new Promise((resolve) => httpServer.listen(0, '127.0.0.1', resolve));
  const address = httpServer.address();
  baseUrl = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  for (const client of clients) {
    client.close();
  }
  clients.clear();
  await new Promise((resolve) => getSocketServer().close(resolve));
  if (httpServer.listening) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  await memoryServer.stop();
});

beforeEach(async () => {
  clearDriverLocationOrderingState();
  await mongoose.connection.dropDatabase();
});

afterEach(() => {
  for (const client of clients) {
    client.close();
  }
  clients.clear();
});

test('database isolation refuses configured Atlas and uses localhost only', () => {
  assert.match(memoryUri, /^mongodb:\/\/127\.0\.0\.1:/);
  assert.notEqual(memoryUri, configuredMongoUri);
  assert.equal(mongoose.connection.host, '127.0.0.1');
});

test('readiness reports MongoDB healthy and optional Redis disabled', async () => {
  const response = await request(app).get('/ready');
  assert.equal(response.status, 200, response.text);
  assert.equal(response.body.status, 'ready');
  assert.equal(response.body.dependencies.mongodb, 'healthy');
  assert.equal(response.body.dependencies.redis, 'disabled');
});

test('route batcher coalesces 50 jeep updates into one bounded route event', () => {
  const batches = [];
  let tick = 0;
  const batcher = new RouteLocationBatcher({
    autoStart: false,
    onBatch: (payload) => batches.push(payload),
    now: () => new Date(Date.UTC(2026, 6, 29, 10, 0, tick++)),
  });

  for (let index = 0; index < 50; index += 1) {
    assert.equal(
      batcher.enqueue({
        routeId: 'route-a',
        tripId: `trip-${index}`,
        jeepneyId: `jeep-${index}`,
        latitude: 14.5 + index / 10_000,
        longitude: 120.9 + index / 10_000,
      }),
      true,
    );
  }
  batcher.flushAll();

  assert.equal(batches.length, 1);
  assert.equal(batches[0].routeId, 'route-a');
  assert.equal(batches[0].sequence, 1);
  assert.equal(batches[0].vehicles.length, 50);
  assert.equal(batches[0].vehicles[0].speedMetersPerSecond, 0);
  assert.equal(batches[0].vehicles[0].headingDegrees, 0);
});

test('route batcher keeps the newest jeep sample and monotonic route sequence', () => {
  const batches = [];
  let nowMs = Date.parse('2026-07-29T10:00:00.000Z');
  const batcher = new RouteLocationBatcher({
    autoStart: false,
    onBatch: (payload) => batches.push(payload),
    now: () => new Date(nowMs++),
  });

  batcher.enqueue({
    routeId: 'route-a',
    tripId: 'trip-a',
    jeepneyId: 'jeep-a',
    latitude: 14.5,
    longitude: 120.9,
  });
  batcher.enqueue({
    routeId: 'route-a',
    tripId: 'trip-a',
    jeepneyId: 'jeep-a',
    latitude: 14.6,
    longitude: 121,
    speedMetersPerSecond: 8,
    headingDegrees: 90,
  });
  batcher.flushAll();
  batcher.enqueue({
    routeId: 'route-a',
    tripId: 'trip-a',
    jeepneyId: 'jeep-a',
    latitude: 14.7,
    longitude: 121.1,
  });
  assert.equal(batcher.flushRoute('route-a'), null);
  nowMs += 1000;
  batcher.flushAll();

  assert.deepEqual(
    batches.map((batch) => batch.sequence),
    [1, 2],
  );
  assert.equal(batches[0].vehicles.length, 1);
  assert.equal(batches[0].vehicles[0].latitude, 14.6);
  assert.equal(batches[0].vehicles[0].speedMetersPerSecond, 8);
  const snapshot = batcher.snapshot('route-a');
  assert.equal(snapshot.snapshot, true);
  assert.equal(snapshot.sequence, 2);
  assert.equal(snapshot.vehicles[0].latitude, 14.7);
});

test('route batcher rejects malformed coordinates and bounds retained memory', () => {
  const batcher = new RouteLocationBatcher({
    autoStart: false,
    onBatch: () => {},
    maxBatchSize: 2,
    maxTrackedRoutes: 2,
    now: (() => {
      let nowMs = Date.parse('2026-07-29T10:00:00.000Z');
      return () => new Date(nowMs++);
    })(),
  });

  assert.equal(
    batcher.enqueue({
      routeId: 'route-a',
      tripId: 'trip-a',
      jeepneyId: 'jeep-a',
      latitude: 91,
      longitude: 120,
    }),
    false,
  );
  for (let index = 0; index < 4; index += 1) {
    batcher.enqueue({
      routeId: 'route-a',
      tripId: `trip-${index}`,
      jeepneyId: `jeep-${index}`,
      latitude: 14.5,
      longitude: 120.9,
    });
  }
  batcher.enqueue({
    routeId: 'route-b',
    tripId: 'trip-b',
    jeepneyId: 'jeep-b',
    latitude: 14.5,
    longitude: 120.9,
  });
  batcher.enqueue({
    routeId: 'route-c',
    tripId: 'trip-c',
    jeepneyId: 'jeep-c',
    latitude: 14.5,
    longitude: 120.9,
  });

  assert.equal(batcher.routeActivity.size, 2);
  assert.equal(batcher.latestByRoute.has('route-a'), false);
  assert.equal(batcher.latestByRoute.get('route-c').size, 1);
});

test('route batcher maintains monotonic sequence without growing route state', () => {
  let nowMs = Date.parse('2026-07-29T10:00:00.000Z');
  let lastBatch = null;
  let batchCount = 0;
  const batcher = new RouteLocationBatcher({
    autoStart: false,
    onBatch: (payload) => {
      lastBatch = payload;
      batchCount += 1;
    },
    now: () => {
      const value = new Date(nowMs);
      nowMs += 1000;
      return value;
    },
  });

  for (let sequence = 1; sequence <= 5000; sequence += 1) {
    batcher.enqueue({
      routeId: 'route-long-running',
      tripId: 'trip-a',
      jeepneyId: 'jeep-a',
      latitude: 14.5,
      longitude: 120.9,
    });
    batcher.flushAll();
  }

  assert.equal(batchCount, 5000);
  assert.equal(lastBatch.sequence, 5000);
  assert.equal(batcher.sequenceByRoute.size, 1);
  assert.equal(batcher.latestByRoute.size, 1);
  assert.equal(batcher.latestByRoute.get('route-long-running').size, 1);
  assert.equal(batcher.pendingByRoute.size, 0);
});

test('driver location endpoints preserve authorization and method compatibility', async () => {
  const fixture = await seedCoreFixture();
  const payload = { lat: 14.6001, lng: 120.9821 };

  const missingAuth = await request(app)
    .patch('/api/v1/drivers/me/location')
    .send(payload);
  assert.equal(missingAuth.status, 401);

  const passengerAttempt = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.passenger))
    .send(payload);
  assert.equal(passengerAttempt.status, 403);

  const adminAttempt = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.admin))
    .send(payload);
  assert.equal(adminAttempt.status, 403);

  const invalidCoordinates = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: 100, lng: 120 });
  assert.equal(invalidCoordinates.status, 400);

  for (const method of ['patch', 'post', 'put']) {
    for (const endpoint of [
      '/api/v1/drivers/me/location',
      '/api/v1/drivers/location',
    ]) {
      const response = await request(app)
        [method](endpoint)
        .set(auth(fixture.tokens.driver))
        .send(payload);
      assert.equal(response.status, 200, response.text);
    }
  }

  const saved = await Jeepney.findById(fixture.jeepney._id);
  assert.deepEqual(saved.lastKnownLocation.coordinates, [
    payload.lng,
    payload.lat,
  ]);
  assert.ok(saved.lastSeenAt instanceof Date);
});

test('location update resolves jeepney from an active trip when assignment links are absent', async () => {
  const fixture = await seedCoreFixture();
  fixture.driver.assignedJeepneyId = undefined;
  fixture.jeepney.currentDriverId = undefined;
  await Promise.all([fixture.driver.save(), fixture.jeepney.save()]);

  const response = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: 14.601, lng: 120.983 });
  assert.equal(response.status, 200, response.text);

  const saved = await Jeepney.findById(fixture.jeepney._id);
  assert.deepEqual(saved.lastKnownLocation.coordinates, [120.983, 14.601]);
});

test('ordered driver location returns an acknowledgement and persists motion data', async () => {
  const fixture = await seedCoreFixture();
  const capturedAt = new Date();
  const payload = {
    latitude: 14.601,
    longitude: 120.983,
    accuracyMeters: 7.5,
    speedMetersPerSecond: 8.2,
    headingDegrees: 91,
    streamId: '11111111-1111-4111-8111-111111111111',
    sequence: 1,
    capturedAt: capturedAt.toISOString(),
  };

  const response = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send(payload);

  assert.equal(response.status, 200, response.text);
  assert.deepEqual(
    {
      accepted: response.body.data.accepted,
      streamId: response.body.data.streamId,
      sequence: response.body.data.sequence,
    },
    {
      accepted: true,
      streamId: payload.streamId,
      sequence: 1,
    }
  );
  assert.ok(Date.parse(response.body.data.serverReceivedAt));

  const saved = await Jeepney.findById(fixture.jeepney._id);
  assert.deepEqual(saved.lastKnownLocation.coordinates, [
    payload.longitude,
    payload.latitude,
  ]);
});

test('ordered driver location rejects duplicate and delayed packets before persistence', async () => {
  const fixture = await seedCoreFixture();
  const streamId = '22222222-2222-4222-8222-222222222222';
  const firstCapturedAt = new Date(Date.now() - 2000);
  const acceptedPayload = {
    latitude: 14.601,
    longitude: 120.983,
    accuracyMeters: 5,
    speedMetersPerSecond: 4,
    headingDegrees: 90,
    streamId,
    sequence: 2,
    capturedAt: firstCapturedAt.toISOString(),
  };

  const accepted = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send(acceptedPayload);
  assert.equal(accepted.status, 200, accepted.text);
  clearDriverLocationOrderingState();

  const duplicate = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({
      ...acceptedPayload,
      latitude: 14.7,
      longitude: 121.1,
    });
  assert.equal(duplicate.status, 409, duplicate.text);
  assert.equal(duplicate.body.errors[0].accepted, false);
  assert.equal(duplicate.body.errors[0].sequence, 2);

  const delayed = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({
      ...acceptedPayload,
      latitude: 14.8,
      longitude: 121.2,
      sequence: 3,
      capturedAt: new Date(firstCapturedAt.getTime() - 1000).toISOString(),
    });
  assert.equal(delayed.status, 409, delayed.text);

  const saved = await Jeepney.findById(fixture.jeepney._id);
  assert.deepEqual(saved.lastKnownLocation.coordinates, [
    acceptedPayload.longitude,
    acceptedPayload.latitude,
  ]);
  assert.equal(saved.latestLocationOrder.streamId, streamId);
  assert.equal(saved.latestLocationOrder.sequence, 2);
});

test('new driver stream supersedes an older stream and cannot be moved backward', () => {
  const jeepneyId = new mongoose.Types.ObjectId().toString();
  const serverReceivedAt = new Date();
  const oldStream = '33333333-3333-4333-8333-333333333333';
  const newStream = '44444444-4444-4444-8444-444444444444';
  const oldCapturedAt = new Date(serverReceivedAt.getTime() - 2000);
  const newCapturedAt = new Date(serverReceivedAt.getTime() - 1000);

  reserveDriverLocationOrder({
    jeepneyId,
    streamId: oldStream,
    sequence: 20,
    capturedAt: oldCapturedAt,
    serverReceivedAt,
  });
  const replacement = reserveDriverLocationOrder({
    jeepneyId,
    streamId: newStream,
    sequence: 1,
    capturedAt: newCapturedAt,
    serverReceivedAt: new Date(serverReceivedAt.getTime() + 1),
  });
  assert.equal(replacement.accepted, true);
  assert.equal(replacement.streamId, newStream);

  assert.throws(
    () =>
      reserveDriverLocationOrder({
        jeepneyId,
        streamId: oldStream,
        sequence: 21,
        capturedAt: oldCapturedAt,
        serverReceivedAt: new Date(serverReceivedAt.getTime() + 2),
      }),
    (error) => error.statusCode === 409 && /stream is stale/i.test(error.message)
  );
});

test('higher sequence accepts a repeated capture time without moving backward', () => {
  const jeepneyId = new mongoose.Types.ObjectId().toString();
  const streamId = '66666666-6666-4666-8666-666666666666';
  const capturedAt = new Date();
  const first = reserveDriverLocationOrder({
    jeepneyId,
    streamId,
    sequence: 1,
    capturedAt,
    serverReceivedAt: capturedAt,
  });
  const repeatedFix = reserveDriverLocationOrder({
    jeepneyId,
    streamId,
    sequence: 2,
    capturedAt,
    serverReceivedAt: new Date(capturedAt.getTime() + 5000),
  });

  assert.equal(first.accepted, true);
  assert.equal(repeatedFix.accepted, true);
  assert.equal(repeatedFix.sequence, 2);
});

test('ordered driver location validates protocol metadata and bounds', async () => {
  const fixture = await seedCoreFixture();
  const validPayload = {
    latitude: 14.601,
    longitude: 120.983,
    accuracyMeters: 5,
    speedMetersPerSecond: 4,
    headingDegrees: 90,
    streamId: '55555555-5555-4555-8555-555555555555',
    sequence: 1,
    capturedAt: new Date().toISOString(),
  };
  const invalidBodies = [
    { ...validPayload, streamId: 'not-a-uuid' },
    { ...validPayload, sequence: 0 },
    { ...validPayload, accuracyMeters: 501 },
    { ...validPayload, speedMetersPerSecond: 101 },
    { ...validPayload, headingDegrees: 360 },
    { ...validPayload, capturedAt: 'not-an-iso-date' },
    {
      ...validPayload,
      capturedAt: new Date(Date.now() - 11 * 60 * 1000).toISOString(),
    },
  ];

  for (const body of invalidBodies) {
    clearDriverLocationOrderingState();
    const response = await request(app)
      .patch('/api/v1/drivers/me/location')
      .set(auth(fixture.tokens.driver))
      .send(body);
    assert.equal(response.status, 400, response.text);
  }
});

test('driver location synchronously triggers automatic boarding and offboarding', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({
    fixture,
    autoBoarding: {
      proximityStartedAt: new Date(Date.now() - 20_000),
      lastCheckedAt: new Date(Date.now() - 20_000),
      lastDistanceMeters: 0,
    },
  });

  const boardingResponse = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: routePath[0][1], lng: routePath[0][0] });
  assert.equal(boardingResponse.status, 200, boardingResponse.text);

  const boardedRide = await RideSession.findOne({
    pickupRequestId: pickup._id,
  });
  assert.equal(boardedRide.status, 'onboard');
  assert.equal((await PickupRequest.findById(pickup._id)).status, 'completed');

  fixture.passenger.lastKnownLocation = point(121.5, 15.1);
  fixture.passenger.lastSeenAt = new Date();
  await fixture.passenger.save();
  boardedRide.autoOffboarding = {
    separationStartedAt: new Date(Date.now() - 70_000),
    lastCheckedAt: new Date(Date.now() - 10_000),
    lastDistanceMeters: 1000,
    outsideCount: 2,
  };
  await boardedRide.save();

  const offboardingResponse = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: routePath[1][1], lng: routePath[1][0] });
  assert.equal(offboardingResponse.status, 200, offboardingResponse.text);

  const completedRide = await RideSession.findById(boardedRide._id);
  assert.equal(completedRide.status, 'completed');
  assert.equal(completedRide.offboardingMethod, 'auto_separation');
});

test('passenger ETA enforces role and authoritative location freshness before Google', async () => {
  const fixture = await seedCoreFixture();
  fixture.jeepney.lastSeenAt = new Date(Date.now() - 61_000);
  await fixture.jeepney.save();

  const driverAttempt = await request(app)
    .post(`/api/v1/trips/${fixture.trip._id}/passenger-eta`)
    .set(auth(fixture.tokens.driver))
    .send({
      destination: {
        latitude: routePath[3][1],
        longitude: routePath[3][0],
      },
    });
  assert.equal(driverAttempt.status, 403);

  const staleLocation = await request(app)
    .post(`/api/v1/trips/${fixture.trip._id}/passenger-eta`)
    .set(auth(fixture.tokens.passenger))
    .send({
      destination: {
        latitude: routePath[3][1],
        longitude: routePath[3][0],
      },
    });
  assert.equal(staleLocation.status, 409);
  assert.match(staleLocation.body.message, /not fresh enough/i);
});

test('stop alerts enforce onboard ownership and assigned-driver boundaries', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const ride = await RideSession.create({
    passengerId: fixture.passenger._id,
    tripSessionId: fixture.trip._id,
    pickupRequestId: pickup._id,
    boardingLocation: point(routePath[0][0], routePath[0][1]),
    destinationStopRef: 'P1-4',
    destinationLocation: point(routePath[3][0], routePath[3][1]),
    status: 'onboard',
    boardedAt: new Date(),
    canSendStopAlert: true,
  });

  const unrelatedPassenger = await request(app)
    .post('/api/v1/stop-alerts')
    .set(auth(fixture.tokens.otherPassenger))
    .send({
      tripSessionId: fixture.trip._id.toString(),
      stopRef: 'P1-4',
      location: point(routePath[3][0], routePath[3][1]),
    });
  assert.equal(unrelatedPassenger.status, 403);

  const created = await request(app)
    .post('/api/v1/stop-alerts')
    .set(auth(fixture.tokens.passenger))
    .send({
      tripSessionId: fixture.trip._id.toString(),
      stopRef: 'P1-4',
      location: point(routePath[3][0], routePath[3][1]),
    });
  assert.equal(created.status, 201, created.text);
  assert.equal(created.body.data.rideSessionId, ride._id.toString());

  const unrelatedDriver = await request(app)
    .get(`/api/v1/stop-alerts/trip/${fixture.trip._id}`)
    .set(auth(fixture.tokens.otherDriver));
  assert.equal(unrelatedDriver.status, 403);

  const assignedDriver = await request(app)
    .get(`/api/v1/stop-alerts/trip/${fixture.trip._id}`)
    .set(auth(fixture.tokens.driver));
  assert.equal(assignedDriver.status, 200, assignedDriver.text);
  assert.equal(assignedDriver.body.data.length, 1);
  assert.equal(await StopAlert.countDocuments(), 1);
});

test('Socket.IO accepts auth payload or authorization header and rejects missing authentication', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);
  assert.equal(socket.connected, true);
  const headerSocket = await connectClient(fixture.tokens.driver, {
    headerToken: true,
  });
  assert.equal(headerSocket.connected, true);

  await assert.rejects(
    () => connectClient(''),
    /Authentication token missing|Invalid or expired token/,
  );
});

test('Socket.IO rejects access tokens supplied only through the query string', async () => {
  const fixture = await seedCoreFixture();
  await assert.rejects(
    () =>
      connectClient(fixture.tokens.passenger, {
        queryToken: true,
      }),
    /Authentication token missing/,
  );
});

test('passenger route subscriptions require active ObjectIds and replace the previous route', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);

  const malformed = await emitWithAck(socket, 'subscribe.route', 'not-an-id');
  assert.equal(malformed.ok, false);
  assert.equal(malformed.code, 'INVALID_IDENTIFIER');

  fixture.otherRoute.status = 'inactive';
  await fixture.otherRoute.save();
  const inactive = await emitWithAck(
    socket,
    'subscribe.route',
    fixture.otherRoute._id.toString(),
  );
  assert.equal(inactive.ok, false);
  assert.equal(inactive.code, 'FORBIDDEN');
  await expectNoEvent(
    socket,
    'phase2.inactive-route',
    () =>
      emitToRoute(fixture.otherRoute._id, 'phase2.inactive-route', {
        routeId: fixture.otherRoute._id.toString(),
      }),
  );

  fixture.otherRoute.status = 'active';
  await fixture.otherRoute.save();
  const first = await emitWithAck(
    socket,
    'subscribe.route',
    fixture.route._id.toString(),
  );
  assert.equal(first.ok, true);
  const second = await emitWithAck(
    socket,
    'subscribe.route',
    fixture.otherRoute._id.toString(),
  );
  assert.equal(second.ok, true);
  assert.equal(second.replacedRouteId, fixture.route._id.toString());

  await expectNoEvent(
    socket,
    'phase2.old-route',
    () =>
      emitToRoute(fixture.route._id, 'phase2.old-route', {
        routeId: fixture.route._id.toString(),
      }),
  );
  const routePayload = await waitForEvent(
    socket,
    'phase2.selected-route',
    () =>
      emitToRoute(fixture.otherRoute._id, 'phase2.selected-route', {
        routeId: fixture.otherRoute._id.toString(),
      }),
  );
  assert.equal(routePayload.routeId, fixture.otherRoute._id.toString());
});

test('trip subscriptions enforce assigned driver, associated passenger, and admin access', async () => {
  const fixture = await seedCoreFixture();
  const passengerSocket = await connectClient(fixture.tokens.passenger);
  const unrelatedTrip = await emitWithAck(
    passengerSocket,
    'subscribe.trip',
    fixture.otherTrip._id.toString(),
  );
  assert.equal(unrelatedTrip.ok, false);
  assert.equal(unrelatedTrip.code, 'FORBIDDEN');
  await expectNoEvent(
    passengerSocket,
    'phase2.unrelated-trip',
    () =>
      emitToTrip(fixture.otherTrip._id, 'phase2.unrelated-trip', {
        tripId: fixture.otherTrip._id.toString(),
      }),
  );

  const ownBeforeAssociation = await emitWithAck(
    passengerSocket,
    'subscribe.trip',
    fixture.trip._id.toString(),
  );
  assert.equal(ownBeforeAssociation.ok, false);

  await createPickupRequest({ fixture });
  const ownAfterAssociation = await emitWithAck(
    passengerSocket,
    'subscribe.trip',
    fixture.trip._id.toString(),
  );
  assert.equal(ownAfterAssociation.ok, true);

  const driverSocket = await connectClient(fixture.tokens.driver);
  assert.equal(
    (
      await emitWithAck(
        driverSocket,
        'subscribe.trip',
        fixture.trip._id.toString(),
      )
    ).ok,
    true,
  );
  const otherDriverTrip = await emitWithAck(
    driverSocket,
    'subscribe.trip',
    fixture.otherTrip._id.toString(),
  );
  assert.equal(otherDriverTrip.ok, false);
  assert.equal(otherDriverTrip.code, 'FORBIDDEN');

  const adminSocket = await connectClient(fixture.tokens.admin);
  assert.equal(
    (
      await emitWithAck(
        adminSocket,
        'subscribe.trip',
        fixture.otherTrip._id.toString(),
      )
    ).ok,
    true,
  );
});

test('one location update produces one scoped delivery and zero unscoped deliveries', async () => {
  const fixture = await seedCoreFixture();
  const scopedSocket = await connectClient(fixture.tokens.passenger);
  const unscopedSocket = await connectClient(fixture.tokens.otherPassenger);
  await createPickupRequest({ fixture });
  const subscribed = await emitWithAck(
    scopedSocket,
    'subscribe.route',
    fixture.route._id.toString(),
  );
  assert.equal(subscribed.ok, true);
  const tripSubscribed = await emitWithAck(
    scopedSocket,
    'subscribe.trip',
    fixture.trip._id.toString(),
  );
  assert.equal(tripSubscribed.ok, true);

  let scopedDeliveries = 0;
  let unscopedDeliveries = 0;
  scopedSocket.on('jeepney.location.updated', () => {
    scopedDeliveries += 1;
  });
  unscopedSocket.on('jeepney.location.updated', () => {
    unscopedDeliveries += 1;
  });

  emitJeepneyLocationUpdate({
    tripId: fixture.trip._id,
    routeId: fixture.route._id,
    jeepneyId: fixture.jeepney._id,
    latitude: routePath[0][1],
    longitude: routePath[0][0],
    timestamp: new Date().toISOString(),
  });
  await delay(200);

  assert.equal(scopedDeliveries, 1);
  assert.equal(unscopedDeliveries, 0);
});

test('50 location updates emit one route batch and a reconnect snapshot', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);
  const subscribed = await emitWithAck(
    socket,
    'subscribe.route',
    fixture.route._id.toString(),
  );
  assert.equal(subscribed.ok, true);

  const batcher = getRouteLocationBatcher();
  batcher.clear();
  let deliveryCount = 0;
  socket.on('route.vehicles.updated', () => {
    deliveryCount += 1;
  });

  const batchPayload = await waitForEvent(
    socket,
    'route.vehicles.updated',
    () => {
      for (let index = 0; index < 50; index += 1) {
        emitJeepneyLocationUpdate({
          tripId: new mongoose.Types.ObjectId(),
          routeId: fixture.route._id,
          jeepneyId: new mongoose.Types.ObjectId(),
          latitude: 14.5 + index / 10_000,
          longitude: 120.9 + index / 10_000,
          timestamp: new Date().toISOString(),
        });
      }
      batcher.flushRoute(fixture.route._id.toString());
    },
  );

  assert.equal(batchPayload.routeId, fixture.route._id.toString());
  assert.equal(batchPayload.sequence, 1);
  assert.equal(batchPayload.vehicles.length, 50);
  await delay(100);
  assert.equal(deliveryCount, 1);

  const reconnectSocket = await connectClient(fixture.tokens.otherPassenger);
  const snapshot = await waitForEvent(
    reconnectSocket,
    'route.vehicles.updated',
    async () => {
      const result = await emitWithAck(
        reconnectSocket,
        'subscribe.route',
        fixture.route._id.toString(),
      );
      assert.equal(result.ok, true);
    },
  );
  assert.equal(snapshot.snapshot, true);
  assert.equal(snapshot.sequence, 1);
  assert.equal(snapshot.vehicles.length, 50);
});

test('Socket.IO disconnect removes socket-owned route and trip memberships', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);
  await createPickupRequest({ fixture });
  assert.equal(
    (
      await emitWithAck(
        socket,
        'subscribe.route',
        fixture.route._id.toString(),
      )
    ).ok,
    true,
  );
  assert.equal(
    (
      await emitWithAck(
        socket,
        'subscribe.trip',
        fixture.trip._id.toString(),
      )
    ).ok,
    true,
  );

  const socketId = socket.id;
  socket.close();
  clients.delete(socket);
  await delay(50);

  const io = getSocketServer();
  assert.equal(io.sockets.sockets.has(socketId), false);
  assert.equal(
    io.sockets.adapter.rooms
      .get(`route:${fixture.route._id}`)
      ?.has(socketId) ?? false,
    false,
  );
  assert.equal(
    io.sockets.adapter.rooms
      .get(`trip:${fixture.trip._id}`)
      ?.has(socketId) ?? false,
    false,
  );
});

test('subscription room limits and per-socket throttling are enforced', async () => {
  const fixture = await seedCoreFixture();
  const adminSocket = await connectClient(fixture.tokens.admin);
  const extraRoutes = await Route.create(
    Array.from({ length: maxCustomRoomsPerSocket + 1 }, (_, index) => ({
      name: `Room Limit Route ${index}`,
      code: `ROOM-LIMIT-${index}`,
      direction: 'up',
      status: 'active',
      path: { type: 'LineString', coordinates: routePath },
    })),
  );

  for (const route of extraRoutes.slice(0, maxCustomRoomsPerSocket)) {
    const result = await emitWithAck(
      adminSocket,
      'subscribe.route',
      route._id.toString(),
    );
    assert.equal(result.ok, true);
  }
  const roomLimited = await emitWithAck(
    adminSocket,
    'subscribe.route',
    extraRoutes[maxCustomRoomsPerSocket]._id.toString(),
  );
  assert.equal(roomLimited.ok, false);
  assert.equal(roomLimited.code, 'ROOM_LIMIT');

  const throttledSocket = await connectClient(fixture.tokens.passenger);
  let result;
  for (let index = 0; index <= maxSubscriptionEventsPerWindow; index += 1) {
    result = await emitWithAck(
      throttledSocket,
      'subscribe.route',
      'not-an-object-id',
    );
  }
  assert.equal(result.ok, false);
  assert.equal(result.code, 'RATE_LIMITED');
});

test('subscription rejection logs are structured and redact credentials and coordinates', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);
  const captured = [];
  const originalWarn = console.warn;
  console.warn = (value) => captured.push(String(value));

  try {
    const oversizedIdentifier = `not-an-id-${'x'.repeat(500)}`;
    const rejection = await emitWithAck(
      socket,
      'subscribe.route',
      oversizedIdentifier,
    );
    assert.equal(rejection.ok, false);
    assert.equal(rejection.resourceId.length, 64);
  } finally {
    console.warn = originalWarn;
  }

  assert.equal(captured.length, 1);
  const entry = JSON.parse(captured[0]);
  assert.equal(entry.type, 'socket.subscription.rejected');
  assert.equal(entry.reason, 'INVALID_IDENTIFIER');
  assert.equal(entry.userId, fixture.users.passenger._id.toString());
  assert.equal(entry.role, 'PASSENGER');
  assert.equal(entry.resourceId.length, 64);
  assert.equal(captured[0].includes(fixture.tokens.passenger), false);
  assert.equal(captured[0].includes('latitude'), false);
  assert.equal(captured[0].includes('longitude'), false);
});

test('simultaneous boarding is idempotent for one pickup request', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const boardingPayload = {
    tripSessionId: fixture.trip._id.toString(),
    pickupRequestId: pickup._id.toString(),
    lat: routePath[0][1],
    lng: routePath[0][0],
  };
  const responses = await Promise.all([
    request(app)
      .post('/api/v1/boarding/validate')
      .set(auth(fixture.tokens.passenger))
      .send(boardingPayload),
    request(app)
      .post('/api/v1/boarding/validate')
      .set(auth(fixture.tokens.passenger))
      .send(boardingPayload),
  ]);

  assert.deepEqual(
    responses.map((response) => response.status),
    [200, 200],
  );
  assert.equal(
    await RideSession.countDocuments({ pickupRequestId: pickup._id }),
    1,
  );
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 1);
});
