const { verifyAccessToken } = require('../utils/jwt');
const User = require('../models/user');
const ApiError = require('../utils/apiError');
const {
  getOrLoadAuthenticatedUser,
} = require('../services/authUserCache.service');

const authenticate = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new ApiError(401, 'Authorization token missing'));
  }

  const token = authHeader.replace('Bearer ', '');
  try {
    const payload = verifyAccessToken(token);
    const { user } = await require('../services/sessionSecurity.service').requireSession(payload);
    req.user = user;
    req.authSessionId = payload.sid;
    next();
  } catch (_error) {
    if (_error.code === 'SESSION_REPLACED') return next(_error);
    next(new ApiError(401, 'Invalid or expired token'));
  }
};

module.exports = authenticate;
