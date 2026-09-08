const crypto = require('crypto');
const { verifyAccessToken, verifyRefreshToken } = require('../utils/jwt');
const {
  rateLimitWindowMs,
  rateLimitAuthMax,
  rateLimitDriverLocationMax,
  rateLimitPassengerLocationMax,
  rateLimitEtaMax,
  rateLimitSupportMax,
  rateLimitAdminMax,
  rateLimitGeneralMax,
} = require('../config/env');

const hashIdentity = (value) =>
  crypto.createHash('sha256').update(String(value || '')).digest('hex');

const verifiedUserRateLimitKey = (req) => {
  const header = String(req.headers.authorization || '');
  if (header.startsWith('Bearer ')) {
    try {
      const payload = verifyAccessToken(header.slice(7));
      if (payload?.sub) return `user:${payload.sub}`;
    } catch (_error) {
      // Authentication middleware returns the canonical unauthorized response.
    }
  }
  return `client:${hashIdentity(req.ip || req.socket?.remoteAddress)}`;
};

const clientRateLimitKey = (req) =>
  `client:${hashIdentity(req.ip || req.socket?.remoteAddress)}`;

const { incrementWindow } = require('../services/securityCounters.service');
const { redisKey } = require('../services/redis.service');
const buildLimiter = ({ max, message, group, sensitive = false, keyGenerator = verifiedUserRateLimitKey }) => {
  const fallback = new Map();
  return async (req, res, next) => {
    const identity = keyGenerator(req);
    let count, ttlMs;
    try {
      ({ count, ttlMs } = await incrementWindow(redisKey('http-limit', group, identity), rateLimitWindowMs));
    } catch (error) {
      if (sensitive) return next(error);
      const now = Date.now();
      for (const [key, value] of fallback) if (value.until <= now) fallback.delete(key);
      if (!fallback.has(identity) && fallback.size >= 10000) {
        return res.status(503).json({ success: false, message: 'Service is temporarily busy' });
      }
      const value = fallback.get(identity) || { count: 0, until: now + rateLimitWindowMs };
      value.count += 1;
      fallback.set(identity, value);
      count = value.count; ttlMs = value.until - now;
    }
    const reset = Math.max(1, Math.ceil(ttlMs / 1000));
    res.set('RateLimit', `limit=${max}, remaining=${Math.max(0, max - count)}, reset=${reset}`);
    res.set('RateLimit-Policy', `${max};w=${Math.ceil(rateLimitWindowMs / 1000)}`);
    if (count > max) return res.set('Retry-After', String(reset)).status(429).json({ success: false, message });
    next();
  };
};

const sessionKey = (req) => {
  try { const payload = verifyRefreshToken(req.body?.refreshToken); return `user:${payload.sub}`; }
  catch (_) { return verifiedUserRateLimitKey(req); }
};
const credentialKey = (req) => req.body?.email
  ? `email:${hashIdentity(String(req.body.email).trim().toLowerCase())}`
  : clientRateLimitKey(req);

const createApiRateLimiters = (overrides = {}) => ({
  authIp: buildLimiter({ group: 'auth-ip', max: 300, sensitive: true, keyGenerator: clientRateLimitKey, message: 'Authentication request limit reached' }),
  session: buildLimiter({ group: 'session', max: 60, sensitive: true, keyGenerator: sessionKey, message: 'Session request limit reached' }),
  auth: buildLimiter({
    group: 'auth', sensitive: true,
    max: overrides.auth ?? rateLimitAuthMax,
    keyGenerator: credentialKey,
    message: 'Too many authentication requests. Please try again in a minute.',
  }),
  driverLocation: buildLimiter({
    group: 'driverLocation',
    max: overrides.driverLocation ?? rateLimitDriverLocationMax,
    message: 'Driver location update limit reached. Please slow down.',
  }),
  passengerLocation: buildLimiter({
    group: 'passengerLocation',
    max: overrides.passengerLocation ?? rateLimitPassengerLocationMax,
    message: 'Passenger location update limit reached. Please slow down.',
  }),
  eta: buildLimiter({
    group: 'eta',
    max: overrides.eta ?? rateLimitEtaMax,
    message: 'ETA request limit reached. Please try again shortly.',
  }),
  support: buildLimiter({
    group: 'support',
    max: overrides.support ?? rateLimitSupportMax,
    message: 'Support request limit reached. Please try again shortly.',
  }),
  admin: buildLimiter({
    group: 'admin',
    max: overrides.admin ?? rateLimitAdminMax,
    message: 'Admin operation limit reached. Please try again shortly.',
  }),
  general: buildLimiter({
    group: 'general',
    max: overrides.general ?? rateLimitGeneralMax,
    message: 'API request limit reached. Please try again shortly.',
  }),
});

const apiRateLimiters = createApiRateLimiters();

module.exports = {
  apiRateLimiters,
  createApiRateLimiters,
  verifiedUserRateLimitKey,
  clientRateLimitKey,
};
