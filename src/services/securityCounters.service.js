const crypto = require('crypto');
const { executeRedis, redisKey } = require('./redis.service');
const ApiError = require('../utils/apiError');
const digest = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');
const incrementWindow = async (key, windowMs) => {
  const value = await executeRedis((client) => client.eval(
    "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('PEXPIRE',KEYS[1],ARGV[1]) end; return {n,redis.call('PTTL',KEYS[1])}",
    { keys: [key], arguments: [String(windowMs)] }
  ));
  if (!value) throw new ApiError(503, 'Authentication service is temporarily unavailable');
  return { count: Number(value[0]), ttlMs: Math.max(1, Number(value[1])) };
};
const reserveAuthEmail = async (email, { send = true } = {}) => {
  const now = Date.now();
  const day = new Date(now).toISOString().slice(0, 10);
  const nextDay = Date.parse(`${day}T00:00:00Z`) + 86400000;
  const keys = [redisKey('email', 'cooldown', digest(email)),
    redisKey('email', 'hour', digest(email)), redisKey('email', 'day', day)];
  const result = await executeRedis((client) => client.eval(`
    local cool=redis.call('PTTL',KEYS[1]); if cool>0 then return cool end
    if tonumber(redis.call('GET',KEYS[2]) or '0')>=5 then return redis.call('PTTL',KEYS[2]) end
    if tonumber(redis.call('GET',KEYS[3]) or '0')>=1000 then return redis.call('PTTL',KEYS[3]) end
    redis.call('SET',KEYS[1],'1','PX',60000)
    if redis.call('INCR',KEYS[2])==1 then redis.call('PEXPIRE',KEYS[2],3600000) end
    if ARGV[2]=='1' and redis.call('INCR',KEYS[3])==1 then redis.call('PEXPIRE',KEYS[3],ARGV[1]) end
    return 0`, { keys, arguments: [String(nextDay - now), send ? '1' : '0'] }));
  if (result === null) throw new ApiError(503, 'Authentication service is temporarily unavailable');
  if (Number(result) > 0) {
    const error = new ApiError(429, 'Please wait before requesting another email');
    error.retryAfter = Math.ceil(Number(result) / 1000);
    throw error;
  }
};
module.exports = { incrementWindow, reserveAuthEmail, digest };
