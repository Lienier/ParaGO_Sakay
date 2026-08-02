const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const { MongoMemoryReplSet } = require('mongodb-memory-server');
const mongoose = require('mongoose');
const request = require('supertest');

const run = async () => {
  assert.equal(process.env.DEPLOYMENT_ENV, 'staging');
  assert.equal(process.env.ASYNC_LOCATION_PROCESSING_ENABLED, 'true');
  assert.match(process.env.REDIS_URL || '', /^rediss:\/\//);

  const memoryServer = await MongoMemoryReplSet.create({
    binary: { version: '8.0.28' },
    replSet: { count: 1, storageEngine: 'wiredTiger' },
  });
  const memoryUri = memoryServer.getUri('parago-phase7-worker-validation');
  assert.match(memoryUri, /^mongodb:\/\/127\.0\.0\.1:/);
  process.env.MONGO_URI = memoryUri;
  process.env.JWT_SECRET ||= 'phase7-isolated-validation-secret';
  process.env.RUN_API_JOBS = 'false';
  process.env.RUN_WORKER_JOBS = 'false';

  const app = require('../src/app');
  const User = require('../src/models/user');
  const Driver = require('../src/models/driver');
  const Jeepney = require('../src/models/jeepney');
  const Route = require('../src/models/route');
  const TripSession = require('../src/models/tripSession');
  const { signToken } = require('../src/utils/jwt');
  const {
    initializeRedis,
    shutdownRedis,
  } = require('../src/services/redis.service');
  const { getQueueHealth } = require(
    '../src/services/asyncJobQueue.service'
  );
  const { AsyncWorker } = require('../src/workers/asyncWorker');

  try {
    await mongoose.connect(memoryUri, { autoIndex: false });
    assert.equal(await initializeRedis(), true);

    const user = await User.create({
      email: 'phase7-driver@example.com',
      fullName: 'Phase 7 Driver',
      role: 'DRIVER',
      status: 'active',
    });
    const route = await Route.create({
      name: 'Phase 7 Synthetic Route',
      code: 'PHASE7-SYNTHETIC',
      status: 'active',
      path: {
        type: 'LineString',
        coordinates: [
          [120.98, 14.6],
          [120.99, 14.61],
        ],
      },
    });
    const driver = await Driver.create({
      userId: user._id,
      status: 'active',
      assignedRouteId: route._id,
    });
    const jeepney = await Jeepney.create({
      plateNumber: 'P7-TEST',
      capacity: 20,
      currentDriverId: driver._id,
      status: 'active',
    });
    driver.assignedJeepneyId = jeepney._id;
    await driver.save();
    await TripSession.create({
      jeepneyId: jeepney._id,
      driverId: driver._id,
      routeId: route._id,
      status: 'active',
      active: true,
      startedAt: new Date(),
    });

    const token = signToken({
      sub: user._id.toString(),
      role: 'DRIVER',
    });
    const streamId = '77777777-7777-4777-8777-777777777777';
    const firstPayload = {
      latitude: 14.6005,
      longitude: 120.9805,
      accuracyMeters: 5,
      speedMetersPerSecond: 7,
      headingDegrees: 90,
      streamId,
      sequence: 1,
      capturedAt: new Date().toISOString(),
    };

    const asyncStartedAt = performance.now();
    const accepted = await request(app)
      .patch('/api/v1/drivers/me/location')
      .set('Authorization', `Bearer ${token}`)
      .send(firstPayload);
    const asyncAcknowledgementMs = performance.now() - asyncStartedAt;
    assert.equal(accepted.status, 200, accepted.text);
    assert.equal(accepted.body.data.accepted, true);

    const beforeWorker = await Jeepney.findById(jeepney._id).lean();
    assert.equal(beforeWorker.lastKnownLocation, undefined);
    const queued = await getQueueHealth();
    assert.equal(queued.pendingLocations, 1);
    assert.equal(queued.pendingAutomation, 1);

    const worker = new AsyncWorker();
    const flush = await worker.flushLocations();
    const automation = await worker.processAutomation();
    assert.equal(flush.persisted, 1);
    assert.equal(automation.processed, 1);
    const afterWorker = await Jeepney.findById(jeepney._id).lean();
    assert.deepEqual(afterWorker.lastKnownLocation.coordinates, [
      firstPayload.longitude,
      firstPayload.latitude,
    ]);

    await shutdownRedis();
    const fallbackPayload = {
      ...firstPayload,
      latitude: 14.601,
      longitude: 120.981,
      sequence: 2,
      capturedAt: new Date().toISOString(),
    };
    const fallbackStartedAt = performance.now();
    const fallback = await request(app)
      .patch('/api/v1/drivers/me/location')
      .set('Authorization', `Bearer ${token}`)
      .send(fallbackPayload);
    const fallbackAcknowledgementMs = performance.now() - fallbackStartedAt;
    assert.equal(fallback.status, 200, fallback.text);
    const afterFallback = await Jeepney.findById(jeepney._id).lean();
    assert.deepEqual(afterFallback.lastKnownLocation.coordinates, [
      fallbackPayload.longitude,
      fallbackPayload.latitude,
    ]);

    console.log(
      JSON.stringify({
        database: 'isolated-in-memory',
        atlasContacted: false,
        redisTls: true,
        asyncAcknowledgementMs: Number(asyncAcknowledgementMs.toFixed(2)),
        persistedBeforeWorker: false,
        workerBulkPersisted: flush.persisted,
        workerAutomationProcessed: automation.processed,
        queueLagMs: worker.metrics.maxQueueLagMs,
        redisOutageFallback: true,
        fallbackAcknowledgementMs: Number(
          fallbackAcknowledgementMs.toFixed(2)
        ),
      })
    );
  } finally {
    await shutdownRedis();
    if (mongoose.connection.readyState) {
      await mongoose.connection.dropDatabase();
      await mongoose.disconnect();
    }
    await memoryServer.stop();
  }
};

run().catch((error) => {
  console.error(
    JSON.stringify({
      success: false,
      error: error.message,
    })
  );
  process.exitCode = 1;
});
