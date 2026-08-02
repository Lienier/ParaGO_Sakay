const {
  redisLatestLocationTtlSeconds,
  redisActiveContextTtlSeconds,
} = require('../config/env');
const {
  redisKey,
  redisGetJson,
  redisSetJson,
  redisDelete,
  acquireRedisLock,
  releaseRedisLock,
} = require('./redis.service');

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

const latestJeepLocationKey = (jeepneyId) =>
  redisKey('location', 'jeepney', jeepneyId);
const driverActiveContextKey = (driverId) =>
  redisKey('context', 'driver', driverId);
const etaCacheKey = (key) => redisKey('eta', 'result', key);
const etaLockKey = (key) => redisKey('eta', 'lock', key);

const cacheLatestJeepLocation = async ({
  jeepneyId,
  latitude,
  longitude,
  lastSeenAt,
  streamId = null,
  sequence = null,
}) =>
  redisSetJson(
    latestJeepLocationKey(jeepneyId),
    {
      jeepneyId: String(jeepneyId),
      latitude: Number(latitude),
      longitude: Number(longitude),
      lastSeenAt: new Date(lastSeenAt).toISOString(),
      streamId,
      sequence,
    },
    redisLatestLocationTtlSeconds
  );

const getLatestJeepLocation = async (jeepneyId) =>
  redisGetJson(latestJeepLocationKey(jeepneyId));

const getOrLoadDriverActiveContext = async ({ driverId, loader }) => {
  const key = driverActiveContextKey(driverId);
  const cached = await redisGetJson(key);
  if (cached.value) {
    return { value: cached.value, source: 'redis' };
  }
  const value = await loader();
  if (value) {
    await redisSetJson(key, value, redisActiveContextTtlSeconds);
  }
  return { value, source: 'mongodb' };
};

const invalidateDriverActiveContext = async (driverId) => {
  if (!driverId) return true;
  return redisDelete(driverActiveContextKey(driverId));
};

const getCachedEta = async (key) => redisGetJson(etaCacheKey(key));

const setCachedEta = async (key, payload, ttlSeconds) =>
  redisSetJson(etaCacheKey(key), payload, ttlSeconds);

const coalesceEtaRequest = async ({
  key,
  ttlSeconds,
  loader,
  lockTtlMs = 20000,
  waitTimeoutMs = 15500,
  pollIntervalMs = 100,
}) => {
  const cached = await getCachedEta(key);
  if (cached.value) return cached.value;
  if (!cached.available) return loader();

  let token = await acquireRedisLock(etaLockKey(key), lockTtlMs);
  if (token) {
    try {
      const value = await loader();
      await setCachedEta(key, value, ttlSeconds);
      return value;
    } finally {
      await releaseRedisLock(etaLockKey(key), token);
    }
  }

  const deadline = Date.now() + waitTimeoutMs;
  while (Date.now() < deadline) {
    await delay(pollIntervalMs);
    const pendingResult = await getCachedEta(key);
    if (pendingResult.value) return pendingResult.value;
    if (!pendingResult.available) return loader();
  }

  token = await acquireRedisLock(etaLockKey(key), lockTtlMs);
  if (!token) {
    return loader();
  }
  try {
    const value = await loader();
    await setCachedEta(key, value, ttlSeconds);
    return value;
  } finally {
    await releaseRedisLock(etaLockKey(key), token);
  }
};

module.exports = {
  latestJeepLocationKey,
  driverActiveContextKey,
  etaCacheKey,
  etaLockKey,
  cacheLatestJeepLocation,
  getLatestJeepLocation,
  getOrLoadDriverActiveContext,
  invalidateDriverActiveContext,
  getCachedEta,
  setCachedEta,
  coalesceEtaRequest,
};
