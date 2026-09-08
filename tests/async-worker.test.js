const test = require('node:test');
const assert = require('node:assert/strict');

process.env.MONGO_URI ||= 'mongodb://127.0.0.1:27017/parago-async-worker-test';
process.env.JWT_SECRET ||= 'phase7-test-secret';

const {
  injectRedisClientForTests,
  resetRedisForTests,
  acquireRedisLock,
  releaseRedisLock,
} = require('../src/services/redis.service');
const {
  enqueueLocationWork,
  enqueueAutomationWork,
  drainLocationWork,
  getQueueHealth,
  listFailedJobs,
  isJobProcessed,
  markJobProcessed,
} = require('../src/services/asyncJobQueue.service');
const {
  AsyncWorker,
  locationOperation,
  retryDelayMs,
} = require('../src/workers/asyncWorker');
const { emitToUser } = require('../src/realtime/socketServer');
const { operationalEventChannel } = require(
  '../src/services/operationalEventBridge.service'
);

class FakeRedisClient {
  constructor() {
    this.isReady = true;
    this.isOpen = true;
    this.strings = new Map();
    this.sets = new Map();
    this.sortedSets = new Map();
    this.lists = new Map();
    this.published = [];
  }

  async get(key) {
    return this.strings.get(key) ?? null;
  }

  async set(key, value, options = {}) {
    if (options.NX && this.strings.has(key)) return null;
    this.strings.set(key, value);
    return 'OK';
  }

  async del(keys) {
    const values = Array.isArray(keys) ? keys : [keys];
    let removed = 0;
    for (const key of values) {
      removed += this.strings.delete(key) ? 1 : 0;
      removed += this.sets.delete(key) ? 1 : 0;
      removed += this.sortedSets.delete(key) ? 1 : 0;
      removed += this.lists.delete(key) ? 1 : 0;
    }
    return removed;
  }

  multi() {
    const operations = [];
    const transaction = {
      set: (...args) => {
        operations.push(() => this.set(...args));
        return transaction;
      },
      sAdd: (...args) => {
        operations.push(() => this.sAdd(...args));
        return transaction;
      },
      exec: async () => Promise.all(operations.map((operation) => operation())),
    };
    return transaction;
  }

  async sAdd(key, ...members) {
    const target = this.sets.get(key) || new Set();
    let added = 0;
    for (const member of members.flat()) {
      const size = target.size;
      target.add(String(member));
      if (target.size > size) added += 1;
    }
    this.sets.set(key, target);
    return added;
  }

  async sPop(key, count = 1) {
    const target = this.sets.get(key);
    if (!target?.size) return count === 1 ? null : [];
    const values = [];
    while (values.length < count && target.size) {
      const value = target.values().next().value;
      target.delete(value);
      values.push(value);
    }
    return count === 1 ? values[0] : values;
  }

  async sCard(key) {
    return this.sets.get(key)?.size || 0;
  }

  async zAdd(key, entries) {
    const target = this.sortedSets.get(key) || new Map();
    for (const entry of entries) target.set(entry.value, Number(entry.score));
    this.sortedSets.set(key, target);
    return entries.length;
  }

  async zRangeByScore(key, minimum, maximum, options = {}) {
    const entries = Array.from(this.sortedSets.get(key) || [])
      .filter(([, score]) => score >= minimum && score <= maximum)
      .sort((left, right) => left[1] - right[1])
      .map(([value]) => value);
    const offset = options.LIMIT?.offset || 0;
    const count = options.LIMIT?.count || entries.length;
    return entries.slice(offset, offset + count);
  }

  async zRem(key, members) {
    const target = this.sortedSets.get(key) || new Map();
    let removed = 0;
    for (const member of Array.isArray(members) ? members : [members]) {
      removed += target.delete(member) ? 1 : 0;
    }
    return removed;
  }

  async zCard(key) {
    return this.sortedSets.get(key)?.size || 0;
  }

  async lPush(key, value) {
    const target = this.lists.get(key) || [];
    target.unshift(value);
    this.lists.set(key, target);
    return target.length;
  }

  async lTrim(key, start, end) {
    const target = this.lists.get(key) || [];
    this.lists.set(key, target.slice(start, end + 1));
    return 'OK';
  }

  async lRange(key, start, end) {
    return (this.lists.get(key) || []).slice(start, end + 1);
  }

  async lLen(key) {
    return this.lists.get(key)?.length || 0;
  }

  async eval(_script, { keys, arguments: args }) {
    if (this.strings.get(keys[0]) !== args[0]) return 0;
    this.strings.delete(keys[0]);
    return 1;
  }

  async publish(channel, message) {
    this.published.push({ channel, message });
    return 1;
  }
}

const baseJob = (overrides = {}) => ({
  kind: 'location',
  idempotencyKey: 'jeep-1:stream-1:1',
  jeepneyId: 'jeep-1',
  tripId: 'trip-1',
  driverUserId: 'user-1',
  latitude: 14.6,
  longitude: 120.98,
  streamId: '11111111-1111-4111-8111-111111111111',
  sequence: 1,
  capturedAt: '2026-07-30T10:00:00.000Z',
  serverReceivedAt: '2026-07-30T10:00:00.100Z',
  queuedAt: '2026-07-30T10:00:00.100Z',
  attempts: 0,
  ...overrides,
});

test.beforeEach(() => {
  injectRedisClientForTests({ testClient: new FakeRedisClient() });
});

test.afterEach(() => {
  resetRedisForTests();
});

test('location queue coalesces many updates to the newest job per jeep', async () => {
  for (let sequence = 1; sequence <= 50; sequence += 1) {
    await enqueueLocationWork(
      baseJob({
        sequence,
        latitude: 14.6 + sequence / 10000,
        idempotencyKey: `jeep-1:stream-1:${sequence}`,
      })
    );
  }
  const health = await getQueueHealth();
  assert.equal(health.pendingLocations, 1);

  const drained = await drainLocationWork(500);
  assert.equal(drained.available, true);
  assert.equal(drained.jobs.length, 1);
  assert.equal(drained.jobs[0].sequence, 50);
});

test('a worker created after enqueue recovers and bulk persists pending jobs', async () => {
  await enqueueLocationWork(baseJob());
  const writes = [];
  const worker = new AsyncWorker({
    now: () => new Date('2026-07-30T10:00:04.000Z'),
    dependencies: {
      jeepneyModel: {
        bulkWrite: async (operations, options) => {
          writes.push({ operations, options });
        },
      },
    },
  });

  const result = await worker.flushLocations();
  assert.equal(result.persisted, 1);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].operations.length, 1);
  assert.equal(writes[0].options.ordered, false);
  assert.equal(worker.metrics.maxQueueLagMs, 3900);
});

test('two workers cannot process automation for one trip concurrently', async () => {
  let destinationRuns = 0;
  let boardingRuns = 0;
  let offboardingRuns = 0;
  const dependencies = {
    processDestinationApproachAlerts: async () => {
      destinationRuns += 1;
      await new Promise((resolve) => setTimeout(resolve, 25));
    },
    processAutomaticBoardingForTrip: async () => {
      boardingRuns += 1;
    },
    processAutomaticOffboardingForTrip: async () => {
      offboardingRuns += 1;
    },
  };
  const first = new AsyncWorker({ dependencies });
  const second = new AsyncWorker({ dependencies });
  const job = baseJob({ kind: 'automation' });

  const results = await Promise.all([
    first.processAutomationJob(job),
    second.processAutomationJob(job),
  ]);

  assert.deepEqual(results.sort(), [false, true]);
  assert.equal(destinationRuns, 1);
  assert.equal(boardingRuns, 1);
  assert.equal(offboardingRuns, 1);
  assert.equal(await isJobProcessed(job.idempotencyKey), true);
});

test('retry backoff is bounded and terminal failures become visible', async () => {
  assert.equal(retryDelayMs(1), 500);
  assert.equal(retryDelayMs(20), 5000);

  const scheduled = [];
  const failed = [];
  const worker = new AsyncWorker({
    maxAttempts: 3,
    dependencies: {
      scheduleRetry: async (job, delayMs) => {
        scheduled.push({ job, delayMs });
      },
      recordFailedJob: async (entry) => {
        failed.push(entry);
      },
    },
  });
  await worker.handleFailure(baseJob({ attempts: 0 }), new Error('temporary'));
  await worker.handleFailure(baseJob({ attempts: 2 }), new Error('terminal'));

  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].delayMs, 500);
  assert.equal(failed.length, 1);
  assert.equal(failed[0].job.attempts, 3);
});

test('failed queue is bounded and exposes redacted operational fields', async () => {
  const worker = new AsyncWorker({ maxAttempts: 1 });
  await worker.handleFailure(
    baseJob({ attempts: 0 }),
    new Error('database temporarily unavailable')
  );
  const failures = await listFailedJobs(10);
  assert.equal(failures.length, 1);
  assert.equal(failures[0].kind, 'location');
  assert.equal(failures[0].jeepneyId, 'jeep-1');
  assert.equal(failures[0].error, 'database temporarily unavailable');
  assert.equal(Object.hasOwn(failures[0], 'latitude'), false);
  assert.equal(Object.hasOwn(failures[0], 'longitude'), false);
});

test('location bulk operation keeps ordering metadata in the same write', () => {
  const operation = locationOperation(baseJob());
  assert.deepEqual(
    operation.updateOne.update.$set.lastKnownLocation.coordinates,
    [120.98, 14.6]
  );
  assert.equal(
    operation.updateOne.update.$set.latestLocationOrder.sequence,
    1
  );
  assert.equal(operation.updateOne.filter._id, 'jeep-1');
});

test('distributed scheduler lock allows only one worker run', async () => {
  let reassignmentRuns = 0;
  let announcementRuns = 0;
  const dependencies = {
    pauseInactiveTrips: async () => 0,
    checkAndReassignPassedRequests: async () => {
      reassignmentRuns += 1;
      await new Promise((resolve) => setTimeout(resolve, 25));
    },
    reconcileAnnouncementStatuses: async () => {
      announcementRuns += 1;
      return { published: 0, expired: 0 };
    },
  };
  const first = new AsyncWorker({ dependencies });
  const second = new AsyncWorker({ dependencies });

  const results = await Promise.all([
    first.runScheduledJobs(),
    second.runScheduledJobs(),
  ]);

  assert.equal(results.filter((result) => result.skipped).length, 1);
  assert.equal(reassignmentRuns, 1);
  assert.equal(announcementRuns, 1);
});

test('worker realtime output is published to the API bridge without coordinates', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });

  emitToUser('user-1', 'notification.created', {
    id: 'notification-1',
    title: 'Ride updated',
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(fake.published.length, 1);
  assert.equal(fake.published[0].channel, operationalEventChannel);
  const event = JSON.parse(fake.published[0].message);
  assert.equal(event.target, 'user');
  assert.equal(event.targetId, 'user-1');
  assert.equal(event.eventName, 'notification.created');
  assert.equal(Object.hasOwn(event.payload, 'latitude'), false);
  assert.equal(Object.hasOwn(event.payload, 'longitude'), false);
});

test('worker drain waits for active work and flushes pending locations', async () => {
  let locationDrains = 0;
  const worker = new AsyncWorker({
    dependencies: {
      promoteDueRetries: async () => 0,
      drainLocationWork: async () => {
        locationDrains += 1;
        return { available: true, jobs: [] };
      },
    },
  });
  worker.automationRunning = true;
  setTimeout(() => {
    worker.automationRunning = false;
  }, 20);

  const result = await worker.drain({ timeoutMs: 500, pollIntervalMs: 5 });
  assert.equal(result.persisted, 0);
  assert.equal(locationDrains, 1);
});
