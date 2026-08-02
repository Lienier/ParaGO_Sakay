const { redisKey } = require('./redis.service');
const {
  getOrLoadCachedRead,
  invalidateCachedRead,
} = require('./readCache.service');

const authUserCacheKey = (userId) => redisKey('auth', 'user', userId);

const getOrLoadAuthenticatedUser = async ({ userId, loader }) =>
  getOrLoadCachedRead({
    key: authUserCacheKey(userId),
    ttlSeconds: 5,
    loader,
  });

const invalidateAuthenticatedUser = async (userId) => {
  if (!userId) return true;
  return invalidateCachedRead(authUserCacheKey(userId));
};

module.exports = {
  authUserCacheKey,
  getOrLoadAuthenticatedUser,
  invalidateAuthenticatedUser,
};
