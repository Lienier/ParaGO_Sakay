const {
  redisDelete,
  redisGetJson,
  redisSetJson,
} = require('./redis.service');

const pendingReads = new Map();

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
  getOrLoadCachedRead,
  invalidateCachedRead,
  resetReadCacheForTests,
};
