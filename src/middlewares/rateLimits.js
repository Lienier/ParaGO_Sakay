const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const { verifyAccessToken } = require('../utils/jwt');
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

const buildLimiter = ({ max, message, keyGenerator = verifiedUserRateLimitKey }) =>
  rateLimit({
    windowMs: rateLimitWindowMs,
    max,
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator,
    message: {
      success: false,
      message,
    },
  });

const createApiRateLimiters = (overrides = {}) => ({
  auth: buildLimiter({
    max: overrides.auth ?? rateLimitAuthMax,
    keyGenerator: clientRateLimitKey,
    message: 'Too many authentication requests. Please try again in a minute.',
  }),
  driverLocation: buildLimiter({
    max: overrides.driverLocation ?? rateLimitDriverLocationMax,
    message: 'Driver location update limit reached. Please slow down.',
  }),
  passengerLocation: buildLimiter({
    max: overrides.passengerLocation ?? rateLimitPassengerLocationMax,
    message: 'Passenger location update limit reached. Please slow down.',
  }),
  eta: buildLimiter({
    max: overrides.eta ?? rateLimitEtaMax,
    message: 'ETA request limit reached. Please try again shortly.',
  }),
  support: buildLimiter({
    max: overrides.support ?? rateLimitSupportMax,
    message: 'Support request limit reached. Please try again shortly.',
  }),
  admin: buildLimiter({
    max: overrides.admin ?? rateLimitAdminMax,
    message: 'Admin operation limit reached. Please try again shortly.',
  }),
  general: buildLimiter({
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
