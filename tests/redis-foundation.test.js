const assert = require('node:assert/strict');
const { afterEach, test } = require('node:test');
const {
  namespace,
  redisKey,
  getRedisHealth,
  injectRedisClientForTests,
  resetRedisForTests,
} = require('../src/services/redis.service');
const {
  latestJeepLocationKey,
  driverActiveContextKey,
  etaCacheKey,
  cacheLatestJeepLocation,
  getLatestJeepLocation,
  getOrLoadDriverActiveContext,
  invalidateDriverActiveContext,
  coalesceEtaRequest,
} = require('../src/services/transientState.service');
const {
  getOrLoadCachedRead,
  invalidateCachedRead,
  resetReadCacheForTests,
} = require('../src/services/readCache.service');
const {
  authUserCacheKey,
  getOrLoadAuthenticatedUser,
  invalidateAuthenticatedUser,
} = require('../src/services/authUserCache.service');

class FakeRedisClient {
  constructor() {
    this.isReady = true;
    this.values = new Map();
    this.expirations = new Map();
    this.setCalls = [];
    this.deletedKeys = [];
    this.failOperations = false;
  }

  checkFailure() {
    if (this.failOperations) throw new Error('simulated redis outage');
  }

  purgeExpired(key) {
    const expiration = this.expirations.get(key);
    if (expiration != null && expiration <= Date.now()) {
      this.values.delete(key);
      this.expirations.delete(key);
    }
  }

  async get(key) {
    this.checkFailure();
    this.purgeExpired(key);
    return this.values.get(key) ?? null;
  }

  async set(key, value, options = {}) {
    this.checkFailure();
    this.purgeExpired(key);
    if (options.NX && this.values.has(key)) return null;
    this.values.set(key, value);
    if (options.EX) {
      this.expirations.set(key, Date.now() + options.EX * 1000);
    } else if (options.PX) {
      this.expirations.set(key, Date.now() + options.PX);
    }
    this.setCalls.push({ key, value, options });
    return 'OK';
  }

  async del(keys) {
    this.checkFailure();
    const entries = Array.isArray(keys) ? keys : [keys];
    let deleted = 0;
    for (const key of entries) {
      if (this.values.delete(key)) deleted += 1;
      this.expirations.delete(key);
      this.deletedKeys.push(key);
    }
    return deleted;
  }

  async eval(_script, { keys, arguments: args }) {
    this.checkFailure();
    const [key] = keys;
    const [token] = args;
    if (this.values.get(key) !== token) return 0;
    this.values.delete(key);
    this.expirations.delete(key);
    return 1;
  }
}

afterEach(() => {
  resetReadCacheForTests();
  resetRedisForTests();
});

test('read-through cache coalesces identical loads and supports invalidation', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });
  const key = redisKey('read', 'routes', 'all');
  let loads = 0;
  const loader = async () => {
    loads += 1;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return [{ id: 'route-1' }];
  };

  const results = await Promise.all(
    Array.from({ length: 20 }, () =>
      getOrLoadCachedRead({ key, ttlSeconds: 30, loader })
    )
  );
  assert.equal(loads, 1);
  assert.deepEqual(results[0].value, [{ id: 'route-1' }]);
  assert.equal(results.some((entry) => entry.source === 'coalesced'), true);

  const cached = await getOrLoadCachedRead({ key, ttlSeconds: 30, loader });
  assert.equal(cached.source, 'redis');
  assert.equal(loads, 1);

  await invalidateCachedRead(key);
  await getOrLoadCachedRead({ key, ttlSeconds: 30, loader });
  assert.equal(loads, 2);
});

test('read-through cache coalesces MongoDB fallback while Redis is unavailable', async () => {
  const fake = new FakeRedisClient();
  fake.failOperations = true;
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;
  const key = redisKey('read', 'active-trips', 'route-1');
  const loader = async () => {
    loads += 1;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return [];
  };

  await Promise.all(
    Array.from({ length: 10 }, () =>
      getOrLoadCachedRead({ key, ttlSeconds: 2, loader })
    )
  );
  assert.equal(loads, 1);
  assert.equal(getRedisHealth().status, 'unhealthy');
});

test('authenticated users are briefly cached and explicitly invalidated', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;
  const loader = async () => {
    loads += 1;
    return { _id: 'user-1', role: 'PASSENGER', status: 'active' };
  };

  const firstWave = await Promise.all(
    Array.from({ length: 3 }, () =>
      getOrLoadAuthenticatedUser({ userId: 'user-1', loader })
    )
  );
  assert.equal(loads, 1);
  assert.equal(firstWave[0].value.status, 'active');
  assert.equal(fake.setCalls.at(-1).options.EX, 5);
  assert.equal(
    authUserCacheKey('user-1'),
    `${namespace}:auth:user:user-1`
  );

  await invalidateAuthenticatedUser('user-1');
  await getOrLoadAuthenticatedUser({ userId: 'user-1', loader });
  assert.equal(loads, 2);
});

test('Redis keys are environment-namespaced and reject empty parts', () => {
  assert.match(namespace, /^parago:/);
  assert.equal(
    latestJeepLocationKey('jeep-1'),
    `${namespace}:location:jeepney:jeep-1`
  );
  assert.equal(
    driverActiveContextKey('driver-1'),
    `${namespace}:context:driver:driver-1`
  );
  assert.equal(etaCacheKey('trip:14.5:121.0').startsWith(`${namespace}:eta:result:`), true);
  assert.throws(() => redisKey('location', ''), /non-empty/i);
});

test('latest jeep locations are JSON cached with a 60-second TTL', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });

  const stored = await cacheLatestJeepLocation({
    jeepneyId: 'jeep-1',
    latitude: 14.6,
    longitude: 121.0,
    lastSeenAt: '2026-07-29T12:00:00.000Z',
    streamId: 'stream-1',
    sequence: 7,
  });
  assert.equal(stored, true);
  assert.equal(fake.setCalls[0].options.EX, 60);

  const cached = await getLatestJeepLocation('jeep-1');
  assert.equal(cached.available, true);
  assert.deepEqual(cached.value, {
    jeepneyId: 'jeep-1',
    latitude: 14.6,
    longitude: 121,
    lastSeenAt: '2026-07-29T12:00:00.000Z',
    streamId: 'stream-1',
    sequence: 7,
  });
});

test('active context caches MongoDB fallback and supports targeted invalidation', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;
  const loader = async () => {
    loads += 1;
    return {
      driverId: 'driver-1',
      jeepneyId: 'jeep-1',
      tripId: 'trip-1',
      routeId: 'route-1',
      tripStatus: 'active',
    };
  };

  const first = await getOrLoadDriverActiveContext({
    driverId: 'driver-1',
    loader,
  });
  const second = await getOrLoadDriverActiveContext({
    driverId: 'driver-1',
    loader,
  });
  assert.equal(first.source, 'mongodb');
  assert.equal(second.source, 'redis');
  assert.equal(loads, 1);

  await invalidateDriverActiveContext('driver-1');
  const third = await getOrLoadDriverActiveContext({
    driverId: 'driver-1',
    loader,
  });
  assert.equal(third.source, 'mongodb');
  assert.equal(loads, 2);
});

test('Redis outage falls back to MongoDB and records unhealthy readiness', async () => {
  const fake = new FakeRedisClient();
  fake.failOperations = true;
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;

  const result = await getOrLoadDriverActiveContext({
    driverId: 'driver-1',
    loader: async () => {
      loads += 1;
      return { driverId: 'driver-1', jeepneyId: 'jeep-1' };
    },
  });
  assert.equal(result.source, 'mongodb');
  assert.equal(loads, 1);
  assert.equal(getRedisHealth().status, 'unhealthy');

  fake.failOperations = false;
  const recovered = await getOrLoadDriverActiveContext({
    driverId: 'driver-1',
    loader: async () => {
      loads += 1;
      return { driverId: 'driver-1', jeepneyId: 'jeep-1' };
    },
  });
  assert.equal(recovered.source, 'mongodb');
  assert.equal(getRedisHealth().status, 'healthy');
});

test('ETA coalescing runs one loader and shares the cached result', async () => {
  const fake = new FakeRedisClient();
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;
  const loader = async () => {
    loads += 1;
    await new Promise((resolve) => setTimeout(resolve, 30));
    return { durationSeconds: 120, source: 'google' };
  };
  const options = {
    key: 'trip-1:14.6000:121.0000',
    ttlSeconds: 25,
    loader,
    pollIntervalMs: 5,
    waitTimeoutMs: 200,
  };

  const [first, second] = await Promise.all([
    coalesceEtaRequest(options),
    coalesceEtaRequest(options),
  ]);
  assert.deepEqual(first, second);
  assert.equal(loads, 1);
  assert.equal(
    fake.setCalls.some(
      (call) =>
        call.key === etaCacheKey(options.key) && call.options.EX === 25
    ),
    true
  );
});

test('ETA loader continues directly when Redis is unavailable', async () => {
  const fake = new FakeRedisClient();
  fake.failOperations = true;
  injectRedisClientForTests({ testClient: fake });
  let loads = 0;
  const result = await coalesceEtaRequest({
    key: 'trip-2:14.6000:121.0000',
    ttlSeconds: 25,
    loader: async () => {
      loads += 1;
      return { durationSeconds: 180, source: 'google' };
    },
    waitTimeoutMs: 10,
  });
  assert.equal(loads, 1);
  assert.equal(result.durationSeconds, 180);
});
