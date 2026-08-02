const {
  redisDelete,
  redisGetJson,
  redisSetJson,
} = require('./redis.service');

const pendingReads = new Map();

const coalesceRead = async ({ key, loader }) => {
  const existing = pendingReads.get(key);
  if (existing) return existing;
  const pending = Promise.resolve()
    .then(loader)
    .finally(() => {
      pendingReads.delete(key);
    });
  pendingReads.set(key, pending);
  return pending;
};

const getOrLoadCachedRead = async ({ key, ttlSeconds, loader }) => {
  const cached = await redisGetJson(key);
  if (cached.value != null) {
    return { value: cached.value, source: 'redis' };
  }

  const existing = pendingReads.get(key);
  if (existing) {
    return { value: await existing, source: 'coalesced' };
  }

  const pending = Promise.resolve()
    .then(loader)
    .then(async (value) => {
      await redisSetJson(key, value, ttlSeconds);
      return value;
    })
    .finally(() => {
      pendingReads.delete(key);
    });
  pendingReads.set(key, pending);
  return { value: await pending, source: 'loader' };
};

const invalidateCachedRead = async (key) => {
  pendingReads.delete(key);
  return redisDelete(key);
};

const resetReadCacheForTests = () => {
  pendingReads.clear();
};

module.exports = {
  coalesceRead,
  getOrLoadCachedRead,
  invalidateCachedRead,
  resetReadCacheForTests,
};
