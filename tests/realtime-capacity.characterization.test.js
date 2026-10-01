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

const tokenFor = async (user) => {
  const sid = require('crypto').randomUUID();
  await require('../src/models/authSession').create({ _id: sid, userId: user._id,
    authVersion: user.authVersion || 0, expiresAt: new Date(Date.now() + 3600000) });
  return signToken({ sub: user._id.toString(), sid });
};
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
      admin: await tokenFor(adminUser),
      driver: await tokenFor(driverUser),
      otherDriver: await tokenFor(otherDriverUser),
      passenger: await tokenFor(passengerUser),
      otherPassenger: await tokenFor(otherPassengerUser),
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

test('active trips can be route-scoped without returning full populated routes', async () => {
  const fixture = await seedCoreFixture();
  const response = await request(app)
    .get(`/api/v1/trips/active?routeId=${fixture.route._id}`)
    .set(auth(fixture.tokens.passenger));

  assert.equal(response.status, 200, response.text);
  assert.equal(response.body.data.length, 1);
  assert.equal(response.body.data[0]._id, fixture.trip._id.toString());
  assert.equal(response.body.data[0].routeId.name, fixture.route.name);
  assert.equal(response.body.data[0].routeId.path, undefined);
  assert.equal(response.body.data[0].jeepneyId.plateNumber, fixture.jeepney.plateNumber);

  const invalid = await request(app)
    .get('/api/v1/trips/active?routeId=not-an-object-id')
    .set(auth(fixture.tokens.passenger));
  assert.equal(invalid.status, 400, invalid.text);
});

test('account suspension immediately invalidates cached authentication', async () => {
  const fixture = await seedCoreFixture();
  const warm = await request(app)
    .get('/api/v1/routes')
    .set(auth(fixture.tokens.passenger));
  assert.equal(warm.status, 200, warm.text);

  const suspended = await request(app)
    .patch(`/api/v1/users/${fixture.users.passenger._id}/status`)
    .set(auth(fixture.tokens.admin))
    .send({ status: 'suspended' });
  assert.equal(suspended.status, 200, suspended.text);

  const rejected = await request(app)
    .get('/api/v1/routes')
    .set(auth(fixture.tokens.passenger));
  assert.equal(rejected.status, 401, rejected.text);
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

test('revoked sessions lose existing socket access within thirty seconds', async () => {
  const fixture = await seedCoreFixture();
  const socket = await connectClient(fixture.tokens.passenger);
  const disconnected = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Revoked socket stayed connected')), 30000);
    socket.once('disconnect', () => { clearTimeout(timer); resolve(); });
  });
  await require('../src/services/sessionSecurity.service').revokeSessions({ userId: fixture.users.passenger._id });
  await disconnected;
  assert.equal(socket.connected, false);
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

test('boarding rejects a changed destination and preserves the saved booking', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const response = await request(app).post('/api/v1/boarding/validate')
    .set(auth(fixture.tokens.passenger)).send({
      tripSessionId: String(fixture.trip._id), pickupRequestId: String(pickup._id),
      lat: routePath[0][1], lng: routePath[0][0],
      destinationStopRef: 'Changed destination', destinationLocation: point(routePath[2][0], routePath[2][1]),
    });
  assert.equal(response.status, 409, response.text);
  assert.equal(await RideSession.countDocuments({ pickupRequestId: pickup._id }), 0);
  assert.equal((await PickupRequest.findById(pickup._id)).destinationStopRef, 'P1-4');
  const accepted = await request(app).post('/api/v1/boarding/validate')
    .set(auth(fixture.tokens.passenger)).send({
      tripSessionId: String(fixture.trip._id), pickupRequestId: String(pickup._id),
      lat: routePath[0][1], lng: routePath[0][0],
      destinationStopRef: pickup.destinationStopRef, destinationLocation: pickup.destinationLocation,
    });
  assert.equal(accepted.status, 200, accepted.text);
});

test('concurrent cancellation and boarding cannot produce a cancelled boarded pickup', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const responses = await Promise.all([
    request(app).post('/api/v1/boarding/validate').set(auth(fixture.tokens.passenger)).send({
      tripSessionId: String(fixture.trip._id), pickupRequestId: String(pickup._id),
      lat: routePath[0][1], lng: routePath[0][0],
    }),
    request(app).patch(`/api/v1/pickup-requests/${pickup._id}/cancel`).set(auth(fixture.tokens.passenger)),
  ]);
  assert.ok(responses.every((response) => [200, 409].includes(response.status)));
  const saved = await PickupRequest.findById(pickup._id);
  const rides = await RideSession.countDocuments({ pickupRequestId: pickup._id });
  assert.equal(rides, saved.status === 'completed' ? 1 : 0);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, rides);
});

test('manual occupancy is authoritative, reaches final capacity, and can return to zero', async () => {
  const fixture = await seedCoreFixture();
  await Jeepney.findByIdAndUpdate(fixture.jeepney._id, { $set: { capacity: 1 } });

  const added = await request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver))
    .send({ manualOccupancyCount: 1, expectedManualOccupancyCount: 0 });
  assert.equal(added.status, 200, added.text);
  assert.equal(added.body.data.manualOccupancyCount, 1);
  assert.equal(added.body.data.occupancyCount, 1);

  const removed = await request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver))
    .send({ manualOccupancyCount: 0, expectedManualOccupancyCount: 1 });
  assert.equal(removed.status, 200, removed.text);
  assert.equal(removed.body.data.manualOccupancyCount, 0);
  assert.equal(removed.body.data.occupancyCount, 0);

  const negative = await request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver))
    .send({ manualOccupancyCount: -1 });
  assert.equal(negative.status, 400, negative.text);
});

test('manual occupancy preserves app-tracked rides and publishes an update to the passenger', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const boarding = await request(app)
    .post('/api/v1/boarding/validate')
    .set(auth(fixture.tokens.passenger))
    .send({
      tripSessionId: fixture.trip._id.toString(),
      pickupRequestId: pickup._id.toString(),
      lat: routePath[0][1],
      lng: routePath[0][0],
    });
  assert.equal(boarding.status, 200, boarding.text);

  const socket = await connectClient(fixture.tokens.passenger);
  const event = await waitForEvent(socket, 'ops.changed', async () => {
    const response = await request(app)
      .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
      .set(auth(fixture.tokens.driver))
      .send({ manualOccupancyCount: 1, expectedManualOccupancyCount: 0 });
    assert.equal(response.status, 200, response.text);
  });

  assert.equal(event.type, 'trip.occupancy.updated');
  assert.equal(event.tripId, fixture.trip._id.toString());
  assert.equal(event.manualOccupancyCount, 1);
  assert.equal(event.occupancyCount, 2);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 2);
});

test('automatic offboarding rejects locations older than 15 seconds and completes on the third fresh check', async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const boarding = await request(app)
    .post('/api/v1/boarding/validate')
    .set(auth(fixture.tokens.passenger))
    .send({
      tripSessionId: fixture.trip._id.toString(),
      pickupRequestId: pickup._id.toString(),
      lat: routePath[0][1],
      lng: routePath[0][0],
    });
  assert.equal(boarding.status, 200, boarding.text);
  const ride = await RideSession.findOne({ pickupRequestId: pickup._id });
  const now = new Date();

  const passenger = await Passenger.findById(fixture.passenger._id);
  passenger.lastKnownLocation = point(121.5, 15.1);
  passenger.lastSeenAt = new Date(now.getTime() - 16_000);
  await passenger.save();
  await Jeepney.findByIdAndUpdate(fixture.jeepney._id, {
    $set: {
      lastKnownLocation: point(routePath[0][0], routePath[0][1]),
      lastSeenAt: now,
    },
  });

  const staleResponse = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: routePath[0][1], lng: routePath[0][0] });
  assert.equal(staleResponse.status, 200, staleResponse.text);
  assert.equal((await RideSession.findById(ride._id)).status, 'onboard');

  passenger.lastSeenAt = new Date();
  await passenger.save();
  const rideWithWindow = await RideSession.findById(ride._id);
  rideWithWindow.autoOffboarding = {
    separationStartedAt: new Date(),
    outsideCount: 2,
    lastDistanceMeters: 1000,
  };
  await rideWithWindow.save();

  const freshResponse = await request(app)
    .patch('/api/v1/drivers/me/location')
    .set(auth(fixture.tokens.driver))
    .send({ lat: routePath[0][1], lng: routePath[0][0] });
  assert.equal(freshResponse.status, 200, freshResponse.text);
  const completed = await RideSession.findById(ride._id);
  assert.equal(completed.status, 'completed');
  assert.equal(completed.offboardingMethod, 'auto_separation');
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 0);
});


test('ending a trip atomically closes rides, pending pickups and alerts', async () => {
  const f = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture: f });
  const boarded = await request(app).post('/api/v1/boarding/validate').set(auth(f.tokens.passenger))
    .send({ tripSessionId: String(f.trip._id), pickupRequestId: String(pickup._id), lat: routePath[0][1], lng: routePath[0][0] });
  assert.equal(boarded.status, 200, boarded.text);
  const ride = await RideSession.findOne({ tripSessionId: f.trip._id });
  await StopAlert.create({ passengerId: f.passenger._id, tripSessionId: f.trip._id,
    rideSessionId: ride._id, routeId: f.route._id, stopRef: 'P1-4' });
  await createPickupRequest({ fixture: f, passenger: f.otherPassenger });
  const closed = await request(app).patch(`/api/v1/trips/${f.trip._id}/end`).set(auth(f.tokens.driver));
  assert.equal(closed.status, 200, closed.text);
  assert.equal(closed.body.data.occupancyCount, 0);
  assert.equal((await RideSession.findById(ride._id)).offboardingMethod, 'trip_ended');
  assert.equal(await StopAlert.countDocuments({ tripSessionId: f.trip._id, status: { $ne: 'dismissed' } }), 0);
  assert.equal(await PickupRequest.countDocuments({ tripSessionId: f.trip._id, status: { $in: ['pending', 'acknowledged'] } }), 0);
  assert.equal((await request(app).patch(`/api/v1/trips/${f.trip._id}/availability`).set(auth(f.tokens.driver)).send({ acceptRequests: true })).status, 409);
});

test('ending a trip racing boarding leaves no onboard rides or occupancy', async () => {
  const f = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture: f });
  const [boarding, ending] = await Promise.all([
    request(app).post('/api/v1/boarding/validate').set(auth(f.tokens.passenger))
      .send({ tripSessionId: String(f.trip._id), pickupRequestId: String(pickup._id), lat: routePath[0][1], lng: routePath[0][0] }),
    request(app).patch(`/api/v1/trips/${f.trip._id}/end`).set(auth(f.tokens.driver)),
  ]);
  assert.equal(ending.status, 200, ending.text);
  assert.ok([200, 409].includes(boarding.status), boarding.text);
  assert.equal(await RideSession.countDocuments({ tripSessionId: f.trip._id, status: 'onboard' }), 0);
  assert.equal((await TripSession.findById(f.trip._id)).occupancyCount, 0);
});

test('inactivity pauses only stale trips and requires explicit resume without closing riders', async () => {
  const { pauseInactiveTrips, setAvailability } = require('../src/services/tripLifecycle.service');
  const f = await seedCoreFixture();
  const now = new Date(Date.now() + 10 * 60000);
  await Jeepney.updateOne({ _id: f.otherJeepney._id }, { $set: { lastSeenAt: now } });
  await pauseInactiveTrips(now);
  const trip = await TripSession.findById(f.trip._id);
  assert.equal(trip.status, 'active');
  assert.equal(trip.acceptRequests, false);
  assert.ok(trip.inactivityPausedAt);
  assert.equal((await TripSession.findById(f.otherTrip._id)).inactivityPausedAt, undefined);
  assert.equal(await pauseInactiveTrips(now), 0);
  const resumed = await setAvailability(f.trip._id, true);
  assert.equal(resumed.acceptRequests, true);
  assert.equal(resumed.inactivityPausedAt, undefined);
  assert.equal(await pauseInactiveTrips(new Date()), 0);
});


test('terminal check-in without GPS serializes promotion, departure and retry', async () => {
  const f = await seedCoreFixture();
  const q = require('../src/services/terminalQueue.service');
  await TripSession.createIndexes();
  await require('../src/models/terminalQueueAction').createIndexes();
  const document = { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id };
  const first = await q.checkIn({ document, actor: f.users.driver, requestId: 'checkin-first' });
  const second = await q.checkIn({ document: { ...document, driverId: f.otherDriver._id, jeepneyId: f.otherJeepney._id }, actor: f.users.otherDriver, requestId: 'checkin-second' });
  assert.equal(first.terminalQueueStatus, 'loading');
  assert.equal(second.terminalQueueStatus, 'waiting');
  assert.equal((await q.checkIn({ document, actor: f.users.driver, requestId: 'checkin-first' })).id, first.id);
  const departed = await q.change({ tripId: first._id, actor: f.users.driver, action: 'depart', requestId: 'departure-first' });
  assert.equal(departed.operatingMode, 'route');
  assert.equal(departed.status, 'active');
  assert.equal((await TripSession.findById(second._id)).terminalQueueStatus, 'loading');
  assert.equal((await q.change({ tripId: first._id, actor: f.users.driver, action: 'depart', requestId: 'departure-first' })).id, first.id);
});

test('terminal capacity reservations and transfer acceptance are atomic', async () => {
  const f = await seedCoreFixture();
  const q = require('../src/services/terminalQueue.service');
  await TripSession.createIndexes();
  await require('../src/models/terminalQueueAction').createIndexes();
  const { createTripRecord } = require('../src/services/tripLifecycle.service');
  await Jeepney.updateOne({ _id: f.jeepney._id }, { $set: { capacity: 1 } });
  const first = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'reserve-first' });
  const second = await q.checkIn({ document: { driverId: f.otherDriver._id, jeepneyId: f.otherJeepney._id, routeId: f.route._id }, actor: f.users.otherDriver, requestId: 'reserve-second' });
  const booking = { passengerId: f.passenger._id, tripSessionId: first._id, routeId: f.route._id, pickupType: 'terminal',
    pickupLocation: point(...routePath[0]), destinationLocation: point(...routePath[3]), destinationStopRef: 'P1-4', fareSnapshot: { amount: 25 }, expiresAt: new Date(Date.now() + 60000) };
  const results = await Promise.allSettled([1,2].map(() => createTripRecord(PickupRequest, booking, { accepting: true })));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const original = results.find(r => r.status === 'fulfilled').value;
  await q.change({ tripId: first._id, actor: f.users.driver, action: 'skip', requestId: 'skip-first' });
  const offer = await PickupRequest.findById(original._id);
  assert.equal(offer.status, 'transfer_offered');
  const transfers = await Promise.all([1,2].map(() => q.transfer({ requestId: offer._id, passengerId: f.passenger._id, offerId: offer.transferOfferId, accept: true })));
  assert.ok(transfers.every(r => String(r.tripSessionId) === String(second._id)));
  assert.equal(transfers[0].fareSnapshot.amount, 25);
  assert.equal(transfers[0].expiresAt.getTime(), original.expiresAt.getTime());
  assert.equal(await PickupRequest.countDocuments({ tripSessionId: second._id, status: 'pending' }), 1);
});

test('terminal status endpoint requires reason and enforces driver ownership', async () => {
  const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
  const first = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'endpoint-checkin' });
  const path = `/api/v1/admin/terminal-queue/${first._id}/status`;
  assert.equal((await request(app).patch(path).set(auth(f.tokens.admin)).send({ terminalQueueStatus: 'departed', requestId: 'admin-departure' })).status, 400);
  assert.equal((await request(app).patch(`/api/v1/trips/${first._id}/terminal/depart`).set(auth(f.tokens.otherDriver)).send({ requestId: 'wrong-departure' })).status, 403);
  const result = await request(app).patch(path).set(auth(f.tokens.admin)).send({ terminalQueueStatus: 'departed', requestId: 'admin-departure', reason: 'Driver requested dispatch' });
  assert.equal(result.status, 200, result.text);
});


test('terminal boarding needs fresh GPS and departure preserves onboard rides', async () => {
  const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
  await TripSession.createIndexes();
  const trip = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'boarding-checkin' });
  const pickup = await createPickupRequest({ fixture: f, trip });
  pickup.pickupType = 'terminal'; pickup.terminalLocation = point(...routePath[0]); await pickup.save();
  const board = () => request(app).post('/api/v1/boarding/validate').set(auth(f.tokens.passenger))
    .send({ tripSessionId: String(trip._id), pickupRequestId: String(pickup._id), lat: routePath[0][1], lng: routePath[0][0] });
  await Passenger.updateOne({ _id: f.passenger._id }, { $unset: { lastSeenAt: 1 } });
  assert.equal((await board()).status, 409);
  await Passenger.updateOne({ _id: f.passenger._id }, { $set: { lastSeenAt: new Date(), lastKnownLocation: point(...routePath[0]) } });
  await Jeepney.updateOne({ _id: f.jeepney._id }, { $set: { lastSeenAt: new Date(), lastKnownLocation: point(...routePath[0]) } });
  const result = await board(); assert.equal(result.status, 200, result.text);
  assert.equal((await TripSession.findById(trip._id)).terminalQueueStatus, 'loading');
  const departed = await q.change({ tripId: trip._id, actor: f.users.driver, action: 'depart', requestId: 'boarded-departure' });
  assert.equal(departed.occupancyCount, 1);
  assert.equal(await RideSession.countDocuments({ tripSessionId: trip._id, status: 'onboard' }), 1);
});

test('terminal GPS inactivity is advisory and returning jeeps go to the back', async () => {
  const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
  const trip = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'inactive-checkin' });
  const originalPosition = trip.terminalQueueNumber;
  await require('../src/services/tripLifecycle.service').pauseInactiveTrips(new Date(Date.now() + 600000));
  const active = await TripSession.findById(trip._id);
  assert.equal(active.acceptRequests, true); assert.equal(active.inactivityPausedAt, undefined);
  await q.change({ tripId: trip._id, actor: f.users.driver, action: 'skip', requestId: 'inactive-skip' });
  const restored = await q.change({ tripId: trip._id, actor: f.users.driver, action: 'restore', requestId: 'inactive-restore' });
  assert.ok(restored.terminalQueueNumber > originalPosition);
  assert.equal(restored.terminalQueueStatus, 'loading');
});

test('terminal transfer cannot be accepted by another passenger or after expiry', async () => {
  const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
  const pickup = await createPickupRequest({ fixture: f });
  pickup.status = 'transfer_offered'; pickup.transferOfferId = 'test-offer'; pickup.expiresAt = new Date(Date.now() - 1000); await pickup.save();
  await assert.rejects(q.transfer({ requestId: pickup._id, passengerId: f.otherPassenger._id, offerId: 'test-offer', accept: true }), error => error.statusCode === 404);
  await assert.rejects(q.transfer({ requestId: pickup._id, passengerId: f.passenger._id, offerId: 'test-offer', accept: true }), error => error.statusCode === 409);
});


test('terminal waiting reorder keeps unique positions and does not move loading jeep', async () => {
 const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
 await TripSession.createIndexes();
 const first = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'order-first' });
 const second = await q.checkIn({ document: { driverId: f.otherDriver._id, jeepneyId: f.otherJeepney._id, routeId: f.route._id }, actor: f.users.otherDriver, requestId: 'order-second' });
 const third = await TripSession.create({ routeId: f.route._id, driverId: new mongoose.Types.ObjectId(), jeepneyId: new mongoose.Types.ObjectId(), status: 'active', operatingMode: 'terminal_queue', terminalQueueStatus: 'waiting', terminalQueueNumber: 10 });
 await q.change({ tripId: third._id, actor: f.users.admin, action: 'reorder', direction: 'up', reason: 'Correct arrival order', requestId: 'order-third-up' });
 assert.equal((await TripSession.findById(third._id)).terminalQueueNumber, second.terminalQueueNumber);
 assert.equal((await TripSession.findById(first._id)).terminalQueueStatus, 'loading');
 await assert.rejects(q.change({ tripId: first._id, actor: f.users.admin, action: 'reorder', direction: 'down', reason: 'Test', requestId: 'order-loading' }), error => error.statusCode === 409);
 const audit = await require('../scripts/terminal-queue-migration').inspect();
 assert.equal(audit.conflicts.length, 0);
});


test('terminal end-trip audits closure and promotes the next jeep', async () => {
 const f = await seedCoreFixture(); const q = require('../src/services/terminalQueue.service');
 const first = await q.checkIn({ document: { driverId: f.driver._id, jeepneyId: f.jeepney._id, routeId: f.route._id }, actor: f.users.driver, requestId: 'end-first' });
 const next = await q.checkIn({ document: { driverId: f.otherDriver._id, jeepneyId: f.otherJeepney._id, routeId: f.route._id }, actor: f.users.otherDriver, requestId: 'end-next' });
 const ended = await request(app).patch(`/api/v1/trips/${first._id}/end`).set(auth(f.tokens.driver)).send({ requestId: 'end-terminal' });
 assert.equal(ended.status, 200, ended.text);
 assert.equal((await TripSession.findById(next._id)).terminalQueueStatus, 'loading');
 assert.ok(await require('../src/models/terminalQueueAction').exists({ tripId: first._id, action: 'end_trip', actorId: f.users.driver._id }));
});
const createOnboardRepairFixture = async () => {
  const fixture = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture });
  const response = await request(app).post('/api/v1/boarding/validate')
    .set(auth(fixture.tokens.passenger)).send({
      tripSessionId: fixture.trip._id.toString(), pickupRequestId: pickup._id.toString(),
      lat: routePath[0][1], lng: routePath[0][0],
    });
  assert.equal(response.status, 200, response.text);
  return { fixture, ride: await RideSession.findOne({ pickupRequestId: pickup._id }) };
};

test('ride repair: concurrent completion decrements occupancy only once', async () => {
  const { fixture, ride } = await createOnboardRepairFixture();
  const { completeRideSession } = require('../src/services/rideCompletion.service');
  await Promise.all(Array.from({ length: 3 }, () => completeRideSession({ session: ride, trip: fixture.trip })));
  assert.equal((await RideSession.findById(ride._id)).status, 'completed');
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 0);
});

test('ride repair: failed alert write rolls back ride and occupancy', async () => {
  const { fixture, ride } = await createOnboardRepairFixture();
  const { completeRideSession } = require('../src/services/rideCompletion.service');
  const original = StopAlert.updateMany;
  StopAlert.updateMany = async () => { throw new Error('injected alert failure'); };
  try {
    await assert.rejects(completeRideSession({ session: ride, trip: fixture.trip }), /injected/);
  } finally { StopAlert.updateMany = original; }
  assert.equal((await RideSession.findById(ride._id)).status, 'onboard');
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 1);
});

test('ride repair: duplicate GPS sample cannot count three times', async () => {
  const { fixture, ride } = await createOnboardRepairFixture();
  const { processAutomaticOffboardingForPassenger } = require('../src/services/automaticOffboarding.service');
  const now = new Date();
  await Passenger.findByIdAndUpdate(fixture.passenger._id, { $set: { lastSeenAt: now, lastKnownLocation: point(121.5, 15.1) } });
  await Jeepney.findByIdAndUpdate(fixture.jeepney._id, { $set: { lastSeenAt: now, lastKnownLocation: point(routePath[0][0], routePath[0][1]) } });
  await Promise.all(Array.from({ length: 3 }, () => processAutomaticOffboardingForPassenger({ passengerId: fixture.passenger._id, now })));
  let result = await RideSession.findById(ride._id);
  assert.equal(result.status, 'onboard'); assert.equal(result.autoOffboarding.outsideCount, 1);
  for (let i = 1; i <= 2; i++) {
    const sample = new Date(now.getTime() + i * 1000);
    await Passenger.findByIdAndUpdate(fixture.passenger._id, { $set: { lastSeenAt: sample } });
    await processAutomaticOffboardingForPassenger({ passengerId: fixture.passenger._id, now: sample });
  }
  result = await RideSession.findById(ride._id);
  assert.equal(result.status, 'completed');
});

test('ride repair: stale captured passenger GPS is rejected without refreshing lastSeenAt', async () => {
  const fixture = await seedCoreFixture();
  const previous = await Passenger.findById(fixture.passenger._id);
  const response = await request(app).post('/api/v1/passengers/me/location').set(auth(fixture.tokens.passenger))
    .send({lat: 15.1, lng: 121.5, capturedAt: new Date(Date.now() - 60000).toISOString()});
  assert.equal(response.status, 409, response.text);
  assert.equal(String((await Passenger.findById(fixture.passenger._id)).lastSeenAt), String(previous.lastSeenAt));
});

test('boarding review: retry returns the existing ride without increasing occupancy', async () => {
  const { fixture, ride } = await createOnboardRepairFixture();
  const response = await request(app).post('/api/v1/boarding/validate').set(auth(fixture.tokens.passenger))
    .send({ tripSessionId: fixture.trip._id.toString(), pickupRequestId: ride.pickupRequestId.toString(), lat: routePath[0][1], lng: routePath[0][0] });
  assert.equal(response.status, 200, response.text);
  assert.equal(await RideSession.countDocuments({ pickupRequestId: ride.pickupRequestId }), 1);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 1);
});

test('boarding review: roadside passenger near pickup cannot board a distant jeep', async () => {
  const fixture = await seedCoreFixture(); const pickup = await createPickupRequest({ fixture });
  await Jeepney.findByIdAndUpdate(fixture.jeepney._id, {$set:{lastKnownLocation:point(121.5,15.1),lastSeenAt:new Date()}});
  const response = await request(app).post('/api/v1/boarding/validate').set(auth(fixture.tokens.passenger))
    .send({tripSessionId:fixture.trip._id.toString(),pickupRequestId:pickup._id.toString(),lat:routePath[0][1],lng:routePath[0][0]});
  assert.equal(response.status,409,response.text);
  assert.equal(await RideSession.countDocuments({pickupRequestId:pickup._id}),0);
});

test('boarding review: transaction rejects a booking that expired after initial validation', async () => {
  const fixture = await seedCoreFixture(); const pickup = await createPickupRequest({fixture});
  await PickupRequest.findByIdAndUpdate(pickup._id,{$set:{expiresAt:new Date(Date.now()-1)}});
  const {completeBoardingForPickupRequest}=require('../src/services/boarding.service');
  await assert.rejects(completeBoardingForPickupRequest({pickupRequest:pickup,trip:fixture.trip,passengerId:fixture.passenger._id}),/expired/);
  assert.equal(await RideSession.countDocuments({pickupRequestId:pickup._id}),0);
});

test('unloading review: notification failure cannot report committed unloading as failed', async () => {
  const {fixture,ride}=await createOnboardRepairFixture();
  const Notification=require('../src/models/notification'); const original=Notification.create; let attempts=0;
  Notification.create=async()=>{attempts++;throw new Error('injected notification failure');};
  try {
    const response=await request(app).patch(`/api/v1/ride-sessions/${ride._id}/complete`).set(auth(fixture.tokens.passenger)).send({});
    assert.equal(response.status,200,response.text);
    assert.equal((await RideSession.findById(ride._id)).status,'completed');
    assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount,0);
    assert.equal(attempts,2);
  } finally {Notification.create=original;}
});

test('GPS review: older and duplicate samples do not overwrite passenger position', async () => {
 const fixture=await seedCoreFixture(); const timestamp=new Date();
 await Passenger.findByIdAndUpdate(fixture.passenger._id,{$set:{lastSeenAt:timestamp,lastKnownLocation:point(121.1,15.1)}});
 for(const time of [timestamp,new Date(timestamp.getTime()-1000)]) {
  const response=await request(app).post('/api/v1/passengers/me/location').set(auth(fixture.tokens.passenger)).send({lat:15.2,lng:121.2,capturedAt:time.toISOString()});
  assert.equal(response.status,200,response.text);assert.equal(response.body.data.accepted,false);
 }
 assert.deepEqual((await Passenger.findById(fixture.passenger._id)).lastKnownLocation.coordinates,[121.1,15.1]);
});


test('new driver login disconnects old socket without ending the trip', async () => {
  const fixture = await seedCoreFixture();
  const user = fixture.users.driver;
  await User.updateOne({ _id: user._id }, { $set: { passwordHash: await require('bcryptjs').hash('Session-test-password-42', 4) } });
  const oldSocket = await connectClient(fixture.tokens.driver);
  const beforeTrip = await TripSession.findById(fixture.trip._id).lean();
  const disconnected = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Replaced socket stayed connected')), 30000);
    oldSocket.once('disconnect', () => { clearTimeout(timer); resolve(); });
  });
  const login = await require('../src/services/auth.service').loginEmail({ email: user.email, password: 'Session-test-password-42' });
  const currentSocket = await connectClient(login.token);
  await disconnected;
  assert.equal(currentSocket.connected, true);
  assert.deepEqual(await TripSession.findById(fixture.trip._id).lean(), beforeTrip);
});


test('manual adjustments serialize, deduplicate retries, and reject stale absolute writes', async () => {
  const fixture = await seedCoreFixture();
  await Jeepney.updateOne({ _id: fixture.jeepney._id }, { capacity: 20 });
  const adjust = (delta, operationId) => request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver)).send({ delta, operationId });
  const results = await Promise.all(Array.from({ length: 8 }, (_, i) => adjust(1, `manual-count-test-${i}`)));
  for (const result of results) assert.equal(result.status, 200, result.text);
  assert.equal((await TripSession.findById(fixture.trip._id)).manualOccupancyCount, 8);
  const retries = await Promise.all(Array.from({ length: 4 }, () => adjust(1, 'manual-count-test-0')));
  for (const result of retries) assert.equal(result.status, 200, result.text);
  assert.equal((await TripSession.findById(fixture.trip._id)).manualOccupancyCount, 8);
  assert.equal((await adjust(-1, 'manual-count-test-0')).status, 409);
  const stale = await request(app).patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver)).send({ manualOccupancyCount: 1, expectedManualOccupancyCount: 0 });
  assert.equal(stale.status, 409);
  for (let i = 0; i < 8; i++) assert.equal((await adjust(-1, `manual-count-minus-${i}`)).status, 200);
  assert.equal((await adjust(-1, 'manual-count-below-zero')).status, 409);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 0);
});


test('manual adjustments protect last seat, ownership, and concurrent first retries', async () => {
  const fixture = await seedCoreFixture();
  await Jeepney.updateOne({ _id: fixture.jeepney._id }, { capacity: 1 });
  const adjust = (operationId, token = fixture.tokens.driver) => request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`).set(auth(token)).send({ delta: 1, operationId });
  const duplicate = await Promise.all([adjust('same-first-operation'), adjust('same-first-operation')]);
  for (const result of duplicate) assert.equal(result.status, 200, result.text);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 1);
  assert.equal((await adjust('capacity-extra-operation')).status, 409);
  assert.equal((await adjust('wrong-owner-operation', fixture.tokens.otherDriver)).status, 403);
  assert.equal((await TripSession.findById(fixture.trip._id)).occupancyCount, 1);
});


test('manual group adjustments apply supported batch deltas exactly once', async () => {
  const fixture = await seedCoreFixture();
  await Jeepney.updateOne({ _id: fixture.jeepney._id }, { capacity: 10 });
  const adjust = (delta, operationId) => request(app)
    .patch(`/api/v1/trips/${fixture.trip._id}/occupancy`)
    .set(auth(fixture.tokens.driver)).send({ delta, operationId });

  assert.equal((await adjust(5, 'manual-group-add-five')).status, 200);
  assert.equal((await TripSession.findById(fixture.trip._id)).manualOccupancyCount, 5);
  assert.equal((await adjust(-3, 'manual-group-remove-three')).status, 200);
  assert.equal((await TripSession.findById(fixture.trip._id)).manualOccupancyCount, 2);
  assert.equal((await adjust(-3, 'manual-group-remove-three')).status, 200);
  assert.equal((await TripSession.findById(fixture.trip._id)).manualOccupancyCount, 2);
  assert.equal((await adjust(2, 'manual-group-remove-three')).status, 409);
  assert.equal((await adjust(4, 'manual-group-invalid-four')).status, 400);
});


test('one passenger cannot reserve competing trips; cancellation and expiry permit a new booking', async () => {
  const f = await seedCoreFixture();
  const { createTripRecord } = require('../src/services/tripLifecycle.service');
  const book = trip => createTripRecord(PickupRequest, {
    passengerId: f.passenger._id, tripSessionId: trip._id, routeId: trip.routeId,
    pickupType: 'roadside', expiresAt: new Date(Date.now() + 600000),
  }, { accepting: true });
  const results = await Promise.allSettled([book(f.trip), book(f.otherTrip)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.statusCode, 409);
  await PickupRequest.updateMany({ passengerId: f.passenger._id }, { status: 'cancelled' });
  const second = await book(f.trip);
  await PickupRequest.updateOne({ _id: second._id }, { expiresAt: new Date(Date.now() - 1000) });
  await book(f.trip);
});

test('onboard passenger cannot book another jeep even when their booking is completed', async () => {
  const f = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture: f });
  await request(app).post('/api/v1/boarding/validate').set(auth(f.tokens.passenger))
    .send({ tripSessionId: String(f.trip._id), pickupRequestId: String(pickup._id), lat: routePath[0][1], lng: routePath[0][0] }).expect(200);
  const { createTripRecord } = require('../src/services/tripLifecycle.service');
  const book = () => createTripRecord(PickupRequest, {
    passengerId: f.passenger._id, tripSessionId: f.otherTrip._id, routeId: f.otherRoute._id,
    pickupType: 'roadside', expiresAt: new Date(Date.now() + 600000),
  }, { accepting: true });
  await assert.rejects(book(), /active ride/);
  await RideSession.updateMany({ passengerId: f.passenger._id }, { status: 'completed' });
  await book();
});


test('pickup toast acknowledgement enforces ownership before idempotent replies and rejects expiry', async () => {
  const f = await seedCoreFixture();
  const pickup = await createPickupRequest({ fixture: f, status: 'pending' });
  const ack = token => request(app).patch(`/api/v1/pickup-requests/${pickup._id}/acknowledge`).set(auth(token));
  await ack(f.tokens.otherDriver).expect(403);
  const results = await Promise.all([ack(f.tokens.driver), ack(f.tokens.driver)]);
  for (const result of results) assert.equal(result.status, 200, result.text);
  await ack(f.tokens.otherDriver).expect(403);
  assert.equal(await RideSession.countDocuments({ pickupRequestId: pickup._id }), 0);
  const expired = await createPickupRequest({ fixture: f, status: 'pending' });
  await PickupRequest.updateOne({ _id: expired._id }, { expiresAt: new Date(Date.now() - 1000) });
  await request(app).patch(`/api/v1/pickup-requests/${expired._id}/acknowledge`).set(auth(f.tokens.driver)).expect(409);
});
