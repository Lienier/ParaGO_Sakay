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
    const cachedUser = await getOrLoadAuthenticatedUser({
      userId: payload.sub,
      loader: () => User.findById(payload.sub).select('-passwordHash').lean(),
    });
    const user = cachedUser.value;
    if (!user || user.status !== 'active') {
      return next(new ApiError(401, 'Invalid user session'));
    }
    req.user = user;
    next();
  } catch (_error) {
    next(new ApiError(401, 'Invalid or expired token'));
  }
};

module.exports = authenticate;
